import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/cart_controller.dart';
import 'package:flutter_application_1/models/product_model.dart';
import 'package:flutter_application_1/services/inventory_service.dart';
import 'package:flutter_application_1/services/order_timeout_service.dart';
import 'package:flutter_application_1/widgets/stock_indicator.dart';

Map<String, dynamic> product(
  int id,
  int stock, {
  bool confirmed = true,
  bool available = true,
}) => {
  'id': id,
  'vendor_id': 10,
  'name': 'Product $id',
  'price': 80,
  'stock_qty': stock,
  'stock_confirmed': confirmed,
  'is_available': available,
  'low_stock_threshold': 5,
  'stock_version': 1,
};

void main() {
  test('unknown stock is not invented as purchasable', () {
    final s = ProductStock({'is_available': true});
    expect(s.confirmed, false);
    expect(s.purchasable, false);
    expect(s.label, 'Stock confirmation required');
  });
  test('stock indicators distinguish high low zero and unavailable', () {
    expect(ProductStock(product(1, 6)).label, 'In stock');
    expect(ProductStock(product(1, 5)).label, 'Low stock');
    expect(ProductStock(product(1, 0)).label, 'Out of stock');
    expect(ProductStock(product(1, 10, available: false)).purchasable, false);
  });
  test('form accepts only nonnegative bounded whole numbers', () {
    for (final invalid in ['', '-1', '1.2', 'abc', '2e3', '1000000001']) {
      expect(ProductStock.nonnegativeInteger(invalid), isNull, reason: invalid);
    }
    expect(ProductStock.nonnegativeInteger('0'), 0);
    expect(ProductStock.nonnegativeInteger(' 15 '), 15);
  });
  test('model preserves authoritative stock fields', () {
    final p = ProductModel.fromJson(product(1, 12));
    expect(p.isPurchasable, true);
    expect(p.toJson()['stock_qty'], 12);
    expect(p.stockVersion, 1);
    expect(ProductModel.fromJson(product(1, 0)).isPurchasable, false);
  });
  test(
    'stock write uses server quantity rather than requested success',
    () async {
      final flow = InventoryWriteFlow(
        writer: (rpc, params) async => {
          'code': 'UPDATED',
          'stock_qty': 7,
          'stock_version': 2,
        },
      );
      final r = await flow.save('vendor_adjust_stock', {'p_quantity': 8});
      expect(r['stock_qty'], 7);
      expect(flow.busy, false);
    },
  );
  test('in-flight inventory write blocks duplicate submission', () async {
    final wait = Completer<Map<String, dynamic>>();
    var calls = 0;
    final flow = InventoryWriteFlow(
      writer: (rpc, p) {
        calls++;
        return wait.future;
      },
    );
    final first = flow.save('vendor_adjust_stock', {'p_quantity': 8});
    expect(flow.busy, true);
    await expectLater(
      flow.save('vendor_adjust_stock', {'p_quantity': 8}),
      throwsStateError,
    );
    wait.complete({'code': 'UPDATED'});
    await first;
    expect(calls, 1);
    expect(flow.busy, false);
  });
  test(
    'uncertain write retry retains request UUID and payload snapshot',
    () async {
      final requests = <Map<String, dynamic>>[];
      var first = true;
      final flow = InventoryWriteFlow(
        writer: (rpc, p) async {
          requests.add(p);
          if (first) {
            first = false;
            throw StateError('offline');
          }
          return {'code': 'ALREADY_UPDATED'};
        },
      );
      final params = {
        'p_data': {'name': 'Original'},
        'p_quantity': 8,
      };
      await expectLater(
        flow.save('fr17_save_product', params),
        throwsStateError,
      );
      await expectLater(
        flow.save('fr17_save_product', {'p_quantity': 9}),
        throwsStateError,
      );
      await flow.save('fr17_save_product', params);
      expect(requests[0], requests[1]);
      expect(flow.busy, false);
    },
  );
  test(
    'definitive stock conflict allows vendor to review and retry new count',
    () async {
      final ids = <String>[];
      var first = true;
      final flow = InventoryWriteFlow(
        writer: (rpc, p) async {
          ids.add(p['p_request_id'] as String);
          if (first) {
            first = false;
            return {
              'code': 'STOCK_CHANGED',
              'stock_qty': 4,
              'stock_version': 2,
            };
          }
          return {'code': 'UPDATED', 'stock_qty': 4};
        },
      );
      expect(
        (await flow.save('vendor_adjust_stock', {'p_quantity': 5}))['code'],
        'STOCK_CHANGED',
      );
      await flow.save('vendor_adjust_stock', {'p_quantity': 4});
      expect(ids[0], isNot(ids[1]));
    },
  );
  test('server validation failure clears rejected inventory request', () async {
    var first = true;
    final flow = InventoryWriteFlow(
      writer: (rpc, p) async {
        if (first) {
          first = false;
          throw const PostgrestException(message: 'Invalid', code: '22023');
        }
        return {'code': 'UPDATED'};
      },
    );
    await expectLater(
      flow.save('vendor_adjust_stock', {'p_quantity': -1}),
      throwsA(isA<PostgrestException>()),
    );
    expect(
      (await flow.save('vendor_adjust_stock', {'p_quantity': 1}))['code'],
      'UPDATED',
    );
  });
  test('cart adds only refreshed available product', () async {
    final cart = CartController(
      inventoryReader: (ids) async => [product(1, 2)],
    );
    expect(
      await cart.addItem({'id': 1, 'name': 'Cached fake price', 'price': 1}),
      true,
    );
    expect(cart.cartItems.single['price'], 80);
    expect(cart.cartItems.single['qty'], 1);
    expect(cart.totalPrice, 80);
  });
  test('cart identity uses product ID even when names match', () async {
    final cart = CartController(
      inventoryReader: (ids) async => [
        for (final id in ids) {...product(id, 2), 'name': 'Same'},
      ],
    );
    await cart.addItem({'id': 1});
    await cart.addItem({'id': 2});
    expect(cart.cartItems.length, 2);
    cart.removeItem({'id': 1});
    expect(cart.cartItems.single['product_id'], 2);
  });
  test(
    'last-known quantity disables increment and server refresh enforces it',
    () async {
      var stock = 2;
      final cart = CartController(
        inventoryReader: (ids) async => [product(1, stock)],
      );
      await cart.addItem({'id': 1});
      expect(cart.canIncrement(cart.cartItems.single), true);
      await cart.incrementQty(cart.cartItems.single);
      expect(cart.canIncrement(cart.cartItems.single), false);
      expect(await cart.incrementQty(cart.cartItems.single), false);
      expect(cart.cartItems.single['qty'], 2);
      stock = 0;
      expect(await cart.incrementQty(cart.cartItems.single), false);
      expect(cart.lastError.value, outOfStockMessage);
      expect(cart.cartItems.single['qty'], 2);
    },
  );
  test('unavailable and unconfirmed stock cannot enter cart', () async {
    for (final row in [
      product(1, 0),
      product(1, 5, available: false),
      product(1, 5, confirmed: false),
    ]) {
      final cart = CartController(inventoryReader: (ids) async => [row]);
      expect(await cart.addItem({'id': 1}), false);
      expect(cart.cartItems, isEmpty);
    }
  });
  test('no simulated add when product query fails', () async {
    final cart = CartController(
      inventoryReader: (ids) async => throw StateError('offline'),
    );
    expect(await cart.addItem({'id': 1}), false);
    expect(cart.cartItems, isEmpty);
    expect(cart.checking, isEmpty);
  });
  test('cart concurrent same-product taps are gated', () async {
    final wait = Completer<List<Map<String, dynamic>>>();
    var calls = 0;
    final cart = CartController(
      inventoryReader: (ids) {
        calls++;
        return wait.future;
      },
    );
    final first = cart.addItem({'id': 1});
    expect(await cart.addItem({'id': 1}), false);
    wait.complete([product(1, 5)]);
    expect(await first, true);
    expect(calls, 1);
    expect(cart.totalItems, 1);
  });
  test(
    'restoration refresh updates stock but preserves chosen quantity',
    () async {
      var stock = 2;
      final cart = CartController(
        inventoryReader: (ids) async => [product(1, stock)],
      );
      await cart.addItem({'id': 1});
      stock = 10;
      await cart.refreshAvailability();
      expect(cart.cartItems.single['stock_qty'], 10);
      expect(cart.cartItems.single['qty'], 1);
    },
  );
  test(
    'removed product refresh disables purchase without deleting cached cart',
    () async {
      var removed = false;
      final cart = CartController(
        inventoryReader: (ids) async => removed ? [] : [product(1, 2)],
      );
      await cart.addItem({'id': 1});
      removed = true;
      await cart.refreshAvailability();
      expect(cart.cartItems.length, 1);
      expect(cart.canIncrement(cart.cartItems.single), false);
    },
  );
  test(
    'multi-item shortage preserves valid items and requires explicit apply',
    () async {
      final cart = CartController(
        inventoryReader: (ids) async =>
            ids.map((id) => product(id, 10)).toList(),
      );
      for (final id in [1, 2, 3]) {
        await cart.addItem({'id': id});
      }
      await cart.incrementQty(cart.cartItems[1]);
      await cart.incrementQty(cart.cartItems[1]);
      final shortages = [
        {'product_id': 1, 'requested': 1, 'available': 0},
        {'product_id': 2, 'requested': 3, 'available': 2},
      ];
      expect(cart.cartItems.length, 3);
      cart.applyShortages(shortages);
      expect(cart.cartItems.map((p) => p['product_id']), [2, 3]);
      expect(cart.cartItems[0]['qty'], 2);
      expect(cart.cartItems[1]['qty'], 1);
    },
  );
  test(
    'checkout shortage is definitive and allows changed cart with new UUID',
    () async {
      final ids = <String>[];
      var first = true;
      final flow = OrderCheckoutFlow((p) async {
        ids.add(p['p_request_id'] as String);
        if (first) {
          first = false;
          return {
            'code': 'INSUFFICIENT_STOCK',
            'shortages': [
              {
                'product_id': 1,
                'name': 'Product 1',
                'requested': 3,
                'available': 2,
              },
            ],
          };
        }
        return {'code': 'PLACED', 'order_id': 10};
      });
      await expectLater(
        flow.place([
          {'product_id': 1, 'quantity': 3},
        ], {}),
        throwsA(
          isA<CheckoutStockShortage>().having(
            (e) => e.products.single['available'],
            'available',
            2,
          ),
        ),
      );
      expect(flow.busy, false);
      expect(
        (await flow.place([
          {'product_id': 1, 'quantity': 2},
        ], {}))['order_id'],
        10,
      );
      expect(ids[0], isNot(ids[1]));
    },
  );
  test(
    'unavailable vendor does not masquerade as successful checkout',
    () async {
      final flow = OrderCheckoutFlow((p) async => {'code': 'UNAVAILABLE'});
      await expectLater(
        flow.place([
          {'product_id': 1, 'quantity': 1},
        ], {}),
        throwsStateError,
      );
      expect(flow.busy, false);
    },
  );
  testWidgets('customer sees exact out-of-stock message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StockIndicator(product: product(1, 0))),
      ),
    );
    expect(find.text(outOfStockMessage), findsOneWidget);
  });
  testWidgets('vendor sees low-stock count and threshold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockIndicator(product: product(1, 3), vendor: true),
        ),
      ),
    );
    expect(find.text('Low stock · 3 units · Low stock at 5'), findsOneWidget);
  });
  testWidgets('unknown stock is explicitly labelled for vendor confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockIndicator(
            product: product(1, 0, confirmed: false),
            vendor: true,
          ),
        ),
      ),
    );
    expect(
      find.text('Stock confirmation required · Low stock at 5'),
      findsOneWidget,
    );
  });
}
