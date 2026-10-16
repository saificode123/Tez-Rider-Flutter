import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/order_timeout_service.dart';
import 'package:flutter_application_1/widgets/order_timeout_summary.dart';

class Backend implements OrderTransitionBackend {
  String code = 'ACCEPTED';
  String? saved = 'pending';
  Object? failure;
  bool offline = false;
  int calls = 0, reads = 0;
  Completer<String>? wait;
  @override
  Future<String> transition(int id, String status) async {
    calls++;
    if (failure != null) throw failure!;
    return wait == null ? code : await wait!.future;
  }

  @override
  Future<String?> status(int id) async {
    reads++;
    if (offline) throw const SocketException('offline');
    return saved;
  }
}

void main() {
  for (final entry in {
    'ACCEPTED': 'Order accepted.',
    'ALREADY_ACCEPTED': 'Order accepted.',
    'ORDER_EXPIRED': 'This order has expired and can no longer be accepted.',
    'ORDER_CANCELLED': 'This order is cancelled.',
    'REVIEW_REQUIRED':
        'Fulfillment has started. This cancellation needs review.',
    'FORBIDDEN': 'You cannot update this order.',
  }.entries) {
    test('server result ${entry.key}', () async {
      final backend = Backend()..code = entry.key;
      final flow = OrderTransitionFlow(backend);
      expect(await flow.change(1, 'accepted'), entry.value);
      expect(flow.busy, isEmpty);
      expect(backend.calls, 1);
    });
  }
  test('duplicate vendor tap cannot issue a second transition', () async {
    final backend = Backend()..wait = Completer<String>();
    final flow = OrderTransitionFlow(backend);
    final first = flow.change(1, 'accepted');
    expect(await flow.change(1, 'accepted'), contains('already in progress'));
    expect(backend.calls, 1);
    backend.wait!.complete('ACCEPTED');
    expect(await first, 'Order accepted.');
  });
  test('ambiguous timeout refreshes committed server state', () async {
    final backend = Backend()
      ..failure = TimeoutException('uncertain')
      ..saved = 'accepted';
    final message = await OrderTransitionFlow(backend).change(1, 'accepted');
    expect(message, 'Server confirmed the order is accepted.');
    expect(backend.reads, 1);
  });
  test('timeout racing cancellation shows cancelled state', () async {
    final backend = Backend()
      ..failure = TimeoutException('uncertain')
      ..saved = 'cancelled';
    expect(
      await OrderTransitionFlow(backend).change(1, 'accepted'),
      'This order is cancelled.',
    );
  });
  test('offline mutation and refresh never report success', () async {
    final backend = Backend()
      ..failure = const SocketException('offline')
      ..offline = true;
    expect(
      await OrderTransitionFlow(backend).change(1, 'accepted'),
      contains('could not be confirmed'),
    );
    expect(backend.reads, 1);
  });
  test(
    'checkout retry retains UUID and original payload after timeout',
    () async {
      final requests = <Map<String, dynamic>>[];
      final flow = OrderCheckoutFlow((request) async {
        requests.add(Map.of(request));
        if (requests.length == 1) throw TimeoutException('uncertain');
        return {'code': 'ALREADY_PLACED', 'order_id': 7};
      });
      final items = [
        {'product_id': 1, 'quantity': 2},
      ];
      final delivery = {
        'address': 'synthetic',
        'lat': 1,
        'lng': 1,
        'speed': 'standard',
      };
      await expectLater(
        flow.place(items, delivery),
        throwsA(isA<TimeoutException>()),
      );
      expect((await flow.place(items, delivery))['order_id'], 7);
      expect(requests[0], requests[1]);
      await expectLater(
        flow.place(items, {...delivery, 'speed': 'express'}),
        throwsStateError,
      );
    },
  );
  test('duplicate checkout is rejected while request is pending', () async {
    final wait = Completer<Map<String, dynamic>>();
    final flow = OrderCheckoutFlow((_) => wait.future);
    final first = flow.place(
      [
        {'product_id': 1, 'quantity': 1},
      ],
      {'address': 'synthetic'},
    );
    await expectLater(flow.place([], {}), throwsStateError);
    wait.complete({'code': 'PLACED', 'order_id': 7});
    expect((await first)['order_id'], 7);
  });
  test('checkout cannot turn a denied result into success', () async {
    final flow = OrderCheckoutFlow((_) async => {'code': 'FORBIDDEN'});
    await expectLater(flow.place([], {}), throwsStateError);
    expect(flow.busy, false);
  });
  testWidgets('cancelled reason, real timeline and pending refund render', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderTimeoutSummary(
            order: {
              'order_status': 'cancelled',
              'cancellation_reason': 'vendor_timeout',
              'order_refund_actions': {'status': 'PENDING', 'amount': 200},
              'order_timeline_events': [
                {'status': 'pending', 'created_at': '2026-10-16T00:00:00Z'},
                {
                  'status': 'cancelled',
                  'reason': 'vendor_timeout',
                  'created_at': '2026-10-16T00:03:00Z',
                },
              ],
            },
          ),
        ),
      ),
    );
    expect(find.text('Order cancelled — vendor unavailable.'), findsOneWidget);
    expect(
      find.text('Refund pending — money has not yet been returned.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Order timeline'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('cancelled'), findsOneWidget);
    expect(find.textContaining('2026-10-16'), findsNWidgets(2));
  });
  testWidgets('COD cancellation does not display a monetary refund', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderTimeoutSummary(
            order: {
              'cancellation_reason': 'vendor_timeout',
              'order_refund_actions': [],
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('Refund pending'), findsNothing);
    expect(find.text('Order cancelled — vendor unavailable.'), findsOneWidget);
  });
}
