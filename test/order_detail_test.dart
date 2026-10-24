import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/order_detail_service.dart';
import 'package:flutter_application_1/screens/customer/order_detail_screen.dart';

Map<String, dynamic> historyFixture() {
  const stamp = '2026-10-23T10:00:00Z';
  List<Map<String, dynamic>> events() => [
    for (var i = 0; i < 3; i++)
      {
        'id': i + 1,
        'status': ['pending', 'accepted', 'preparing'][i],
        'created_at': stamp,
      },
  ];
  return {
    'code': 'OK',
    'order_id': 44,
    'status': 'preparing',
    'created_at': stamp,
    'delivered_at': null,
    'cancelled_at': null,
    'history_limited': false,
    'item_source': 'CHECKOUT_SNAPSHOT',
    'items': [
      {
        'item_id': 1,
        'product_id': 101,
        'product': 'Original item A',
        'vendor_id': 7,
        'vendor': 'Store A',
        'quantity': 2,
        'unit_cents': '1125',
        'line_cents': '2250',
      },
      {
        'item_id': 2,
        'product_id': 102,
        'product': 'Original item B',
        'vendor_id': 8,
        'vendor': 'Store B',
        'quantity': 1,
        'unit_cents': '725',
        'line_cents': '725',
      },
    ],
    'vendor_orders': [
      {
        'id': 901,
        'vendor_id': 7,
        'vendor': 'Store A',
        'status': 'preparing',
        'events': events(),
      },
      {
        'id': 902,
        'vendor_id': 8,
        'vendor': 'Store B',
        'status': 'preparing',
        'events': events(),
      },
    ],
    'events': events(),
    'totals': {
      'currency': 'PKR',
      'state': 'CONFIRMED',
      'subtotal_cents': '2975',
      'delivery_cents': '20000',
      'total_cents': '22975',
    },
    'payment': {
      'code': 'OK',
      'order_id': 44,
      'order_status': 'preparing',
      'method': 'COD',
      'state': 'UNPAID',
      'amount': 229.75,
      'refunded_amount': 0,
      'refunds': [],
      'events': [],
    },
  };
}

Map<String, dynamic> copy(Map<String, dynamic> data) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(data)));
OrderDetailService service(Future<dynamic> Function(int) reader) =>
    OrderDetailService(reader: reader, identity: () => 'A');
void main() {
  test(
    'fractional multi-Vendor quantities and immutable exact cents remain distinct',
    () async {
      final value = await service((id) async {
        expect(id, 44);
        return historyFixture();
      }).load(44);
      expect(value.items.map((i) => i['vendor_id']), [7, 8]);
      expect(
        historyMoney(historyCents(value.totals['total_cents'])),
        'PKR 229.75',
      );
      expect(historyMoney(1125), 'PKR 11.25');
      expect(historyMoney(null), 'Unavailable');
    },
  );
  test(
    'invalid amounts, quantities, duplicate rows and mismatched confirmed totals fail closed',
    () {
      final cases = <Map<String, dynamic>>[];
      var value = historyFixture();
      value['items'][0]['quantity'] = 1.5;
      cases.add(value);
      value = historyFixture();
      value['items'][0]['line_cents'] = '2200';
      cases.add(value);
      value = historyFixture();
      value['items'][1]['item_id'] = 1;
      cases.add(value);
      value = historyFixture();
      value['totals']['total_cents'] = '22976';
      cases.add(value);
      value = historyFixture();
      value['items'][0]['unit_cents'] = '-1';
      cases.add(value);
      value = historyFixture();
      value['items'][0]['quantity'] = 2147483647;
      value['items'][0]['unit_cents'] = '100000000000000';
      cases.add(value);
      for (final item in cases) {
        expect(() => OrderDetail.parse(item, 44), throwsFormatException);
      }
    },
  );
  test(
    'wrong order, malformed event and payment identity cannot be displayed as confirmed',
    () {
      final cases = <Map<String, dynamic>>[];
      var value = historyFixture();
      value['order_id'] = 45;
      cases.add(value);
      value = historyFixture();
      value['events'][0]['created_at'] = 'not a date';
      cases.add(value);
      value = historyFixture();
      value['vendor_orders'][0]['events'][1]['id'] = 1;
      cases.add(value);
      value = historyFixture();
      value['payment']['order_id'] = 45;
      cases.add(value);
      value = historyFixture();
      value['payment']['order_status'] = 'delivered';
      cases.add(value);
      for (final item in cases) {
        expect(() => OrderDetail.parse(item, 44), throwsFormatException);
      }
    },
  );
  test(
    'legacy unknown items/payment remain review-required without fabricated reconciliation',
    () {
      final value = historyFixture()
        ..['item_source'] = 'UNAVAILABLE'
        ..['items'] = []
        ..['history_limited'] = true;
      value['totals'] = {
        'currency': 'PKR',
        'state': 'REVIEW_REQUIRED',
        'subtotal_cents': null,
        'delivery_cents': null,
        'total_cents': '5000',
      };
      value['payment'] = {'code': 'REVIEW_REQUIRED'};
      final parsed = OrderDetail.parse(value, 44);
      expect(parsed.items, isEmpty);
      expect(parsed.totals['subtotal_cents'], isNull);
    },
  );
  test(
    'unauthenticated reads issue no request; old-account late data is discarded',
    () async {
      var calls = 0;
      await expectLater(
        OrderDetailService(
          identity: () => null,
          reader: (_) async {
            calls++;
            return historyFixture();
          },
        ).load(44),
        throwsStateError,
      );
      expect(calls, 0);
      var account = 'A';
      final pending = Completer<dynamic>();
      final reader = OrderDetailService(
        identity: () => account,
        reader: (_) => pending.future,
      );
      final result = reader.load(44);
      account = 'B';
      pending.complete(historyFixture());
      await expectLater(result, throwsStateError);
    },
  );
  testWidgets(
    'actual refresh, Vendor expansion and static event timeline render exact readable history',
    (t) async {
      await t.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var calls = 0;
      var disposed = false;
      await t.pumpWidget(
        MaterialApp(
          home: OrderDetailScreen(
            orderId: 44,
            service: service((_) async {
              calls++;
              return historyFixture();
            }),
            watcher: (_, __) =>
                () => disposed = true,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Order #44 details'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Original item A'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('2 × PKR 11.25'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Order total: PKR 229.75'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Order total: PKR 229.75'), findsOneWidget);
      final vendor = find.widgetWithText(ExpansionTile, 'Store A');
      await t.scrollUntilVisible(
        vendor,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(vendor);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.byTooltip('Refresh order'));
      await t.pumpAndSettle();
      expect(calls, 2);
      await t.pumpWidget(const SizedBox());
      expect(disposed, true);
    },
  );
  testWidgets(
    'failure shows Retry, and its actual reader recovers without fabricated detail',
    (t) async {
      var fail = true;
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: OrderDetailScreen(
            orderId: 44,
            service: service((_) async {
              calls++;
              if (fail) throw TimeoutException('offline');
              return historyFixture();
            }),
            watcher: (_, __) => () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Order total: PKR 229.75'), findsNothing);
      fail = false;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('preparing'), findsWidgets);
    },
  );
  testWidgets(
    'live invalidation reloads confirmed status and disposal removes watcher',
    (t) async {
      late void Function() event;
      var value = historyFixture();
      var calls = 0;
      var disposed = false;
      await t.pumpWidget(
        MaterialApp(
          home: OrderDetailScreen(
            orderId: 44,
            service: service((_) async {
              calls++;
              return copy(value);
            }),
            watcher: (_, changed) {
              event = changed;
              return () => disposed = true;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      value['status'] = 'delivered';
      value['payment']['order_status'] = 'delivered';
      value['delivered_at'] = '2026-10-23T11:00:00Z';
      event();
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('delivered'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      expect(disposed, true);
      event();
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'account switch immediately clears private item history and rejects a foreign reload',
    (t) async {
      var account = 'A';
      final changes = StreamController<void>.broadcast(sync: true);
      final api = OrderDetailService(
        identity: () => account,
        accountChanges: changes.stream,
        reader: (_) async {
          if (account != 'A') throw StateError('denied');
          return historyFixture();
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: OrderDetailScreen(
            orderId: 44,
            service: api,
            watcher: (_, __) => () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Original item A'), findsOneWidget);
      account = 'B';
      changes.add(null);
      await t.pumpAndSettle();
      expect(find.text('Original item A'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await changes.close();
    },
  );
  testWidgets(
    'legacy unavailable state does not render invented item rows or completed steps',
    (t) async {
      final value = historyFixture()
        ..['items'] = []
        ..['vendor_orders'] = []
        ..['events'] = []
        ..['item_source'] = 'UNAVAILABLE'
        ..['history_limited'] = true;
      value['totals'] = {
        'currency': 'PKR',
        'state': 'REVIEW_REQUIRED',
        'subtotal_cents': null,
        'delivery_cents': null,
        'total_cents': '5000',
      };
      value['payment'] = {'code': 'REVIEW_REQUIRED'};
      await t.pumpWidget(
        MaterialApp(
          home: OrderDetailScreen(
            orderId: 44,
            service: service((_) async => value),
            watcher: (_, __) => () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Itemized records are unavailable for this older order.'),
        findsOneWidget,
      );
      expect(find.text('Original item A'), findsNothing);
      expect(find.text('Order Placed'), findsNothing);
      expect(find.text('Enjoy your order! 🎉'), findsNothing);
    },
  );
}
