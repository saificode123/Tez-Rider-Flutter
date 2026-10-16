import 'package:get/get.dart';
import '../services/inventory_service.dart';

class CartController extends GetxController {
  CartController({InventoryReader? inventoryReader})
    : _read = inventoryReader ?? InventoryApi.read;
  final InventoryReader _read;
  final cartItems = <Map<String, dynamic>>[].obs;
  final checking = <String>{}.obs;
  final lastError = ''.obs;
  String _key(Map item) => (item['product_id'] ?? item['id']).toString();
  bool canIncrement(Map item) =>
      ProductStock(Map<String, dynamic>.from(item)).purchasable &&
      (item['qty'] as num? ?? 1) <
          ProductStock(Map<String, dynamic>.from(item)).quantity &&
      (item['qty'] as num? ?? 1) < 100;

  Future<bool> addItem(Map item) async {
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
      if (i >= 0) {
        cartItems[i] = value;
      } else {
        cartItems.add(value);
      }
      return true;
    } catch (e) {
      lastError.value = e is StateError
          ? e.message.toString()
          : 'Product availability could not be refreshed. Retry when connected.';
      return false;
    } finally {
      checking.remove(key);
    }
  }

  Future<bool> incrementQty(Map item) => addItem(item);
  void removeItem(Map item) =>
      cartItems.removeWhere((e) => _key(e) == _key(item));
  void decrementQty(Map item) {
    final i = cartItems.indexWhere((e) => _key(e) == _key(item));
    if (i < 0) return;
    final qty = (cartItems[i]['qty'] as num).toInt();
    if (qty <= 1) {
      cartItems.removeAt(i);
    } else {
      cartItems[i] = {...cartItems[i], 'qty': qty - 1};
    }
  }

  Future<bool> refreshAvailability() async {
    if (cartItems.isEmpty) return true;
    try {
      final rows = await _read(
        cartItems.map((e) => int.parse(_key(e))).toList(),
      );
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
      lastError.value =
          'Cart availability could not be refreshed. Retry when connected.';
      return false;
    }
  }

  /// Called only after the customer explicitly chooses to apply shortages.
  void applyShortages(List<Map<String, dynamic>> shortages) {
    for (final shortage in shortages) {
      final i = cartItems.indexWhere(
        (e) => _key(e) == shortage['product_id'].toString(),
      );
      if (i < 0) continue;
      final available = (shortage['available'] as num).toInt();
      if (available <= 0) {
        cartItems.removeAt(i);
      } else {
        final qty = (cartItems[i]['qty'] as num).toInt();
        cartItems[i] = {
          ...cartItems[i],
          'qty': qty > available ? available : qty,
          'stock_qty': available,
        };
      }
    }
  }

  void clear() => cartItems.clear();
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
