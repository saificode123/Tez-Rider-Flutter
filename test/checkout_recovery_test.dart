import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/order_timeout_service.dart';

class Journal implements CheckoutRequestStore {
  @override
  String? identity = 'synthetic-customer';
  String? saved;
  bool unavailable = false;
  Completer<void>? writing;
  @override
  Future<Map<String, dynamic>?> read() async => saved == null
      ? null
      : Map<String, dynamic>.from(jsonDecode(saved!) as Map);
  @override
  Future<void> write(Map<String, dynamic> request) async {
    if (unavailable) throw StateError('Secure storage unavailable');
    saved = jsonEncode(request);
    await writing?.future;
  }

  @override
  Future<void> clear() async => saved = null;
}

void main() {
  final items = [
    {'product_id': 224, 'quantity': 1},
  ];
  final delivery = {'address': 'synthetic destination'};
  test('unconfirmed recovery cannot be cleared as completed', () async {
    final journal = Journal();
    final flow = OrderCheckoutFlow(
      (_) async => throw TimeoutException('uncertain'),
      store: journal,
    );
    await expectLater(
      flow.place(items, delivery),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(flow.complete(), throwsStateError);
    expect(journal.saved, isNotNull);
  });
  test(
    'lost committed response and recreated screen reuse one server order',
    () async {
      final journal = Journal(), committed = <String, int>{};
      var calls = 0;
      Future<Map<String, dynamic>> submit(Map<String, dynamic> request) async {
        final id = request['p_request_id'] as String;
        committed.putIfAbsent(id, () => committed.length + 1);
        if (++calls == 1) throw TimeoutException('Response lost after commit');
        return {'code': 'ALREADY_PLACED', 'order_id': committed[id]};
      }

      await expectLater(
        OrderCheckoutFlow(submit, store: journal).place(items, delivery),
        throwsA(isA<TimeoutException>()),
      );
      final recreated = OrderCheckoutFlow(submit, store: journal);
      expect((await recreated.restore())!['p_delivery'], delivery);
      expect((await recreated.place(items, delivery))['order_id'], 1);
      expect(committed.length, 1);
      expect(journal.saved, isNotNull);
      await recreated.complete();
      expect(journal.saved, isNull);
    },
  );
  test('unresolved checkout cannot change payload after recreation', () async {
    final journal = Journal();
    await expectLater(
      OrderCheckoutFlow(
        (_) async => throw TimeoutException('offline'),
        store: journal,
      ).place(items, delivery),
      throwsA(isA<TimeoutException>()),
    );
    var calls = 0;
    await expectLater(
      OrderCheckoutFlow((_) async {
        calls++;
        return {};
      }, store: journal).place(items, {'address': 'changed'}),
      throwsStateError,
    );
    expect(calls, 0);
  });
  test('storage failure prevents submission and releases busy state', () async {
    final journal = Journal()..unavailable = true;
    var calls = 0;
    final flow = OrderCheckoutFlow((_) async {
      calls++;
      return {};
    }, store: journal);
    await expectLater(flow.place(items, delivery), throwsStateError);
    expect(calls, 0);
    expect(flow.busy, false);
  });
  test('two screens cannot race account journal creation', () async {
    final journal = Journal()..writing = Completer<void>();
    var calls = 0;
    Future<Map<String, dynamic>> submit(Map<String, dynamic> _) async {
      calls++;
      return {'code': 'PLACED', 'order_id': 1};
    }

    final first = OrderCheckoutFlow(
      submit,
      store: journal,
    ).place(items, delivery);
    await expectLater(
      OrderCheckoutFlow(submit, store: journal).place(items, delivery),
      throwsStateError,
    );
    journal.writing!.complete();
    await first;
    expect(calls, 1);
  });
  test('account switch during durable write prevents submission', () async {
    final journal = Journal()..writing = Completer<void>();
    var calls = 0;
    final pending = OrderCheckoutFlow((_) async {
      calls++;
      return {};
    }, store: journal).place(items, delivery);
    await Future<void>.delayed(Duration.zero);
    journal.identity = null;
    journal.writing!.complete();
    await expectLater(pending, throwsStateError);
    expect(calls, 0);
  });
  test('definitive stock rejection clears only the rejected request', () async {
    final journal = Journal();
    final flow = OrderCheckoutFlow(
      (_) async => {
        'code': 'INSUFFICIENT_STOCK',
        'shortages': <Map<String, dynamic>>[],
      },
      store: journal,
    );
    await expectLater(
      flow.place(items, delivery),
      throwsA(isA<CheckoutStockShortage>()),
    );
    expect(journal.saved, isNull);
  });
}
