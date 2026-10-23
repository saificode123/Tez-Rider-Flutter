import 'package:get/get.dart';
import 'dart:async';
import '../services/inventory_service.dart';
import '../services/cart_persistence.dart';
import '../services/admin_users_service.dart' show blockRequestId;

class CartController extends GetxController {
  CartController({
    InventoryReader? inventoryReader,
    CartPersistence? persistence,
  }) : _read = inventoryReader ?? InventoryApi.read,
       _persistence =
           persistence ??
           (inventoryReader == null ? SupabaseCartPersistence() : null);
  final InventoryReader _read;
  final CartPersistence? _persistence;
  StreamSubscription<String?>? _identityChanges;
  String? _identity;
  int _generation = 0, _revision = 0;
  List<Map<String, dynamic>>? _pendingItems;
  String? _pendingRequest;
  final syncing = false.obs;
  final restored = false.obs;
  bool get synchronizationReady =>
      _persistence == null ||
      (restored.value &&
          !syncing.value &&
          _pendingRequest == null &&
          _identity != null);
  void forgetSession() => _switchIdentity(null);
  final cartItems = <Map<String, dynamic>>[].obs;
  final checking = <String>{}.obs;
  final lastError = ''.obs;
  @override
  void onInit() {
    super.onInit();
    if (_persistence != null) {
      _identityChanges = _persistence.identityChanges.listen(_switchIdentity);
      _switchIdentity(_persistence.identity);
    } else {
      restored.value = true;
    }
  }

  void _switchIdentity(String? identity) {
    if (_identity == identity && restored.value) return;
    _generation++;
    _identity = identity;
    _revision = 0;
    _pendingItems = null;
    _pendingRequest = null;
    cartItems.clear();
    checking.clear();
    syncing.value = false;
    restored.value = identity == null;
    lastError.value = '';
    if (identity != null) unawaited(restore());
  }

  @override
  void onClose() {
    _generation++;
    unawaited(_identityChanges?.cancel());
    super.onClose();
  }

  Future<bool> restore() async {
    if (_persistence == null) {
      restored.value = true;
      return true;
    }
    if (_identity == null || syncing.value) return false;
    if (_pendingRequest != null) return retrySync();
    final generation = _generation;
    syncing.value = true;
    try {
      final saved = await _persistence.load();
      if (!_current(generation)) return false;
      _apply(saved);
      return true;
    } catch (_) {
      if (_current(generation)) {
        lastError.value =
            'Saved cart could not be restored. Retry when connected.';
      }
      return false;
    } finally {
      if (_current(generation)) syncing.value = false;
    }
  }

  bool _current(int generation) =>
      !isClosed &&
      generation == _generation &&
      (_persistence == null || _identity == _persistence.identity);

  void _apply(SavedCart saved) {
    _revision = saved.revision;
    cartItems.assignAll(saved.items);
    restored.value = true;
    lastError.value = switch (saved.code) {
      'CART_CHANGED' =>
        'Your cart changed on another device. Review the restored cart before retrying.',
      'UNAVAILABLE' =>
        'A product or its requested stock is unavailable. Review your cart.',
      _ => '',
    };
  }

  Future<bool> _save(List<Map<String, dynamic>> desired) async {
    if (_persistence == null) {
      cartItems.assignAll(desired);
      return true;
    }
    if (syncing.value ||
        !restored.value ||
        _identity == null ||
        _pendingRequest != null) {
      lastError.value =
          'Finish restoring or retrying cart synchronization first.';
      return false;
    }
    _pendingItems = desired
        .map((row) => {'product_id': int.parse(_key(row)), 'qty': row['qty']})
        .toList();
    _pendingRequest = blockRequestId();
    return retrySync();
  }

  Future<bool> retrySync() async {
    if (_persistence == null || _pendingRequest == null) return restore();
    if (syncing.value || _identity == null) return false;
    final generation = _generation;
    syncing.value = true;
    try {
      final saved = await _persistence.replace(
        _revision,
        _pendingRequest!,
        _pendingItems!,
      );
      if (!_current(generation)) return false;
      _pendingRequest = null;
      _pendingItems = null;
      _apply(saved);
      return saved.code == 'OK' || saved.code == 'ALREADY_APPLIED';
    } catch (_) {
      if (_current(generation)) {
        lastError.value =
            'Cart save was not confirmed. Retry cart synchronization before editing.';
      }
      return false;
    } finally {
      if (_current(generation)) syncing.value = false;
    }
  }

  String _key(Map item) => (item['product_id'] ?? item['id']).toString();
  bool canIncrement(Map item) =>
      ProductStock(Map<String, dynamic>.from(item)).purchasable &&
      (item['qty'] as num? ?? 1) <
          ProductStock(Map<String, dynamic>.from(item)).quantity &&
      (item['qty'] as num? ?? 1) < 100;

  Future<bool> addItem(Map item) async {
    final generation = _generation;
    if (_persistence != null &&
        (!restored.value || syncing.value || _pendingRequest != null)) {
      lastError.value =
          'Restore or retry cart synchronization before adding products.';
      return false;
    }
    final key = _key(item);
    if (!checking.add(key)) {
      lastError.value = 'Availability is being checked.';
      return false;
    }
    lastError.value = '';
    try {
      final id = int.tryParse(key);
      if (id == null || id <= 0) {
        throw StateError('Product availability could not be confirmed.');
      }
      final rows = await _read([id]);
      if (!_current(generation)) return false;
      if (rows.length != 1) throw StateError(outOfStockMessage);
      final row = rows.single;
      final stock = ProductStock(row);
      final i = cartItems.indexWhere((e) => _key(e) == key);
      final qty = i >= 0 ? (cartItems[i]['qty'] as num).toInt() : 0;
      if (i >= 0) {
        cartItems[i] = {...cartItems[i], ...row, 'product_id': id, 'qty': qty};
      }
      if (!stock.purchasable) {
        throw StateError(
          stock.confirmed ? outOfStockMessage : 'Stock confirmation required.',
        );
      }
      if (qty >= stock.quantity || qty >= 100) {
        throw StateError(
          'Only ${stock.quantity} units are currently available.',
        );
      }
      if (i < 0 && cartItems.length >= 100) {
        throw StateError('Your cart can contain up to 100 products.');
      }
      final value = {
        ...Map<String, dynamic>.from(item),
        ...row,
        'product_id': id,
        'qty': qty + 1,
      };
      final desired = cartItems
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (i >= 0) {
        desired[i] = value;
      } else {
        desired.add(value);
      }
      return await _save(desired);
    } catch (e) {
      if (_current(generation)) {
        lastError.value = e is StateError
            ? e.message.toString()
            : 'Product availability could not be refreshed. Retry when connected.';
      }
      return false;
    } finally {
      if (_current(generation)) checking.remove(key);
    }
  }

  Future<bool> incrementQty(Map item) => addItem(item);
  Future<bool> removeItem(Map item) =>
      _save(cartItems.where((e) => _key(e) != _key(item)).toList());
  Future<bool> decrementQty(Map item) async {
    final i = cartItems.indexWhere((e) => _key(e) == _key(item));
    if (i < 0) return false;
    final desired = cartItems
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final qty = (cartItems[i]['qty'] as num).toInt();
    if (qty <= 1) {
      desired.removeAt(i);
    } else {
      desired[i] = {...cartItems[i], 'qty': qty - 1};
    }
    return _save(desired);
  }

  Future<bool> refreshAvailability() async {
    final generation = _generation;
    if (cartItems.isEmpty) return true;
    try {
      final rows = await _read(
        cartItems.map((e) => int.parse(_key(e))).toList(),
      );
      if (!_current(generation)) return false;
      final byId = {for (final row in rows) row['id'].toString(): row};
      cartItems.assignAll(
        cartItems
            .map(
              (item) => {
                ...item,
                ...?byId[_key(item)],
                if (!byId.containsKey(_key(item))) 'is_available': false,
              },
            )
            .toList(),
      );
      lastError.value = '';
      return true;
    } catch (_) {
      if (_current(generation)) {
        lastError.value =
            'Cart availability could not be refreshed. Retry when connected.';
      }
      return false;
    }
  }

  /// Called only after the customer explicitly chooses to apply shortages.
  Future<bool> applyShortages(List<Map<String, dynamic>> shortages) async {
    final desired = cartItems
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    for (final shortage in shortages) {
      final i = desired.indexWhere(
        (e) => _key(e) == shortage['product_id'].toString(),
      );
      if (i < 0) continue;
      final available = (shortage['available'] as num).toInt();
      if (available <= 0) {
        desired.removeAt(i);
      } else {
        final qty = (desired[i]['qty'] as num).toInt();
        desired[i] = {
          ...desired[i],
          'qty': qty > available ? available : qty,
          'stock_qty': available,
        };
      }
    }
    return _save(desired);
  }

  Future<bool> clear() => _save([]);
  double get totalPrice => cartItems.fold(0, (sum, item) {
    final price = item['price'];
    final p = price is num
        ? price.toDouble()
        : double.tryParse(price?.toString() ?? '0') ?? 0.0;
    return sum + p * (item['qty'] as num? ?? 1);
  });
  int get totalItems => cartItems.fold(
    0,
    (sum, item) => sum + (item['qty'] as num? ?? 1).toInt(),
  );
}
