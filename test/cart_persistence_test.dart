import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/controllers/cart_controller.dart';
import 'package:flutter_application_1/services/cart_persistence.dart';

Map<String, dynamic> stock(int id) => {
  'id': id,
  'product_id': id,
  'vendor_id': id + 10,
  'name': 'Actual $id',
  'price': 25.75,
  'stock_qty': 5,
  'stock_confirmed': true,
  'is_available': true,
  'qty': 1,
};

class MemoryPersistence implements CartPersistence {
  String? user = 'A';
  final changes = StreamController<String?>.broadcast(sync: true);
  final carts = <String, SavedCart>{};
  final requests = <String>[];
  bool fail = false, conflict = false;
  Completer<SavedCart>? delayedLoad, delayedWrite;
  @override
  String? get identity => user;
  @override
  Stream<String?> get identityChanges => changes.stream;
  @override
  Future<SavedCart> load() async =>
      delayedLoad?.future ?? (carts[user] ?? SavedCart('OK', 0, []));
  @override
  Future<SavedCart> replace(
    int revision,
    String request,
    List<Map<String, dynamic>> items,
  ) async {
    requests.add(request);
    if (delayedWrite != null) return delayedWrite!.future;
    if (fail) throw StateError('uncertain network result');
    final current = carts[user] ?? SavedCart('OK', 0, []);
    if (conflict || current.revision != revision) {
      return SavedCart('CART_CHANGED', current.revision, current.items);
    }
    final saved = SavedCart(
      'OK',
      revision + 1,
      items
          .map((row) => {...stock(row['product_id']), 'qty': row['qty']})
          .toList(),
    );
    carts[user!] = saved;
    return saved;
  }

  void switchTo(String? value) {
    user = value;
    changes.add(value);
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
CartController controller(MemoryPersistence backend) => CartController(
  persistence: backend,
  inventoryReader: (ids) async => ids.map(stock).toList(),
);
void main() {
  test(
    'confirmed multi-vendor cart restores after controller restart with real prices',
    () async {
      final backend = MemoryPersistence();
      final first = controller(backend)..onInit();
      await tick();
      expect(await first.addItem({'id': 1, 'price': 999}), true);
      expect(await first.addItem({'id': 2}), true);
      expect(first.totalPrice, 51.5);
      first.onClose();
      final second = controller(backend)..onInit();
      await tick();
      expect(second.cartItems.map((p) => p['vendor_id']), [11, 12]);
      expect(second.totalPrice, 51.5);
      second.onClose();
      await backend.changes.close();
    },
  );
  test(
    'uncertain save blocks new edits and retries the same UUID exactly',
    () async {
      final backend = MemoryPersistence();
      final cart = controller(backend)..onInit();
      await tick();
      backend.fail = true;
      expect(await cart.addItem({'id': 1}), false);
      expect(cart.cartItems, isEmpty);
      expect(cart.synchronizationReady, false);
      expect(await cart.addItem({'id': 2}), false);
      backend.fail = false;
      expect(await cart.retrySync(), true);
      expect(backend.requests.length, 2);
      expect(backend.requests.toSet().length, 1);
      expect(cart.cartItems.single['product_id'], 1);
      cart.onClose();
      await backend.changes.close();
    },
  );
  test(
    'device revision conflict restores server cart without overwriting it',
    () async {
      final backend = MemoryPersistence();
      final cart = controller(backend)..onInit();
      await tick();
      backend.carts['A'] = SavedCart('OK', 3, [stock(2)]);
      expect(await cart.addItem({'id': 1}), false);
      expect(cart.cartItems.single['product_id'], 2);
      expect(cart.lastError.value, contains('another device'));
      cart.onClose();
      await backend.changes.close();
    },
  );
  test(
    'logout clears immediately, preserves remote cart, and late load cannot leak across accounts',
    () async {
      final backend = MemoryPersistence()..delayedLoad = Completer<SavedCart>();
      final old = backend.delayedLoad!;
      final cart = controller(backend)..onInit();
      backend.delayedLoad = null;
      backend.carts['B'] = SavedCart('OK', 1, [stock(2)]);
      backend.switchTo('B');
      await tick();
      old.complete(SavedCart('OK', 1, [stock(1)]));
      await tick();
      expect(cart.cartItems.single['product_id'], 2);
      cart.forgetSession();
      expect(cart.cartItems, isEmpty);
      expect(backend.carts['B']!.items.single['product_id'], 2);
      cart.onClose();
      await backend.changes.close();
    },
  );
  test(
    'late account-A save response cannot replace account-B restored cart',
    () async {
      final backend = MemoryPersistence();
      final cart = controller(backend)..onInit();
      await tick();
      backend.delayedWrite = Completer<SavedCart>();
      final pending = cart.addItem({'id': 1});
      await tick();
      backend.carts['B'] = SavedCart('OK', 4, [stock(2)]);
      backend.switchTo('B');
      await tick();
      backend.delayedWrite!.complete(SavedCart('OK', 1, [stock(1)]));
      expect(await pending, false);
      expect(cart.cartItems.single['product_id'], 2);
      cart.onClose();
      await backend.changes.close();
    },
  );
  test(
    'restore failure never appears as a confirmed empty cart and has recovery',
    () async {
      final backend = MemoryPersistence()..delayedLoad = Completer<SavedCart>();
      final cart = controller(backend)..onInit();
      backend.delayedLoad!.completeError(StateError('offline'));
      await tick();
      expect(cart.restored.value, false);
      expect(cart.lastError.value, contains('could not be restored'));
      backend.delayedLoad = null;
      expect(await cart.restore(), true);
      expect(cart.restored.value, true);
      expect(cart.lastError.value, isEmpty);
      cart.onClose();
      await backend.changes.close();
    },
  );
  test('malformed saved data never becomes usable cart state', () {
    for (final value in [
      null,
      {},
      {
        'code': 'OK',
        'revision': 0,
        'items': [
          {...stock(1), 'qty': 101},
        ],
      },
    ]) {
      expect(() => SavedCart.parse(value), throwsFormatException);
    }
  });
}
