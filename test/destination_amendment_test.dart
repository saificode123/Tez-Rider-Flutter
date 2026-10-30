import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/services/destination_amendment.dart';
import 'package:flutter_application_1/screens/customer/change_delivery_destination_screen.dart';

class Backend implements DestinationAmendmentBackend {
  @override
  String account = 'customer';
  Map<String, dynamic> snapshot = {
    'code': 'OK',
    'order_id': 3180,
    'can_change': true,
    'revision': '2026-10-29T00:00:00Z',
    'latitude': 33.7,
    'longitude': 73.1,
  };
  Map<String, dynamic> result = {
    'code': 'OK',
    'order_id': 3180,
    'revision': '2026-10-30T00:00:00Z',
  };
  final calls = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pending, loading;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> context(int order) async =>
      loading == null ? snapshot : loading!.future;
  @override
  Future<Map<String, dynamic>> change(Map<String, dynamic> args) async {
    calls.add(Map.from(args));
    if (fail) throw StateError('offline');
    return pending == null ? result : pending!.future;
  }
}

void main() {
  late Backend backend;
  late DestinationAmendmentFlow flow;
  setUp(() {
    backend = Backend();
    flow = DestinationAmendmentFlow(3180, backend);
  });
  tearDown(() {
    flow.dispose();
    Get.reset();
  });
  test(
    'confirmed owned revision is sent once with the selected real point',
    () async {
      await flow.load();
      await flow.submit(33.71, 73.11, confirmed: true);
      expect(flow.code, 'OK');
      expect(
        backend.calls.single['p_expected_revision'],
        '2026-10-29T00:00:00Z',
      );
      expect(backend.calls.single['p_lat'], 33.71);
      expect(
        backend.calls.single.keys,
        unorderedEquals([
          'p_order_id',
          'p_request_id',
          'p_expected_revision',
          'p_lat',
          'p_lng',
          'p_address',
          'p_confirmed',
        ]),
      );
    },
  );
  test('unconfirmed and invalid points never reach the backend', () async {
    await flow.load();
    await flow.submit(33.7, 73.1, confirmed: false);
    await flow.submit(double.nan, 73.1, confirmed: true);
    await flow.submit(91, 73.1, confirmed: true);
    expect(backend.calls, isEmpty);
    expect(flow.code, 'INVALID_DESTINATION');
  });
  test('malformed or wrong-order context cannot enable a change', () async {
    for (final patch in [
      {'order_id': 2},
      {'latitude': double.infinity},
      {'revision': 'invalid'},
    ]) {
      backend.snapshot = {...Backend().snapshot, ...patch};
      await flow.load();
      expect(flow.canChange, isFalse);
    }
  });
  test(
    'duplicate submission while pending cannot issue another operation',
    () async {
      await flow.load();
      backend.pending = Completer();
      final first = flow.submit(33.71, 73.11, confirmed: true);
      await flow.submit(33.72, 73.12, confirmed: true);
      expect(backend.calls.length, 1);
      backend.pending!.complete(backend.result);
      await first;
    },
  );
  test(
    'network uncertainty retries identical UUID, revision and coordinates',
    () async {
      await flow.load();
      backend.fail = true;
      await flow.submit(33.71, 73.11, confirmed: true);
      expect(flow.uncertain, isTrue);
      await flow.submit(34, 74, confirmed: true);
      expect(backend.calls.length, 1);
      backend.fail = false;
      await flow.retry();
      expect(backend.calls[1], backend.calls[0]);
      expect(flow.uncertain, isFalse);
      expect(flow.code, 'OK');
    },
  );
  test(
    'business denial never becomes successful destination confirmation',
    () async {
      await flow.load();
      backend.result = {'code': 'RIDER_MUST_PAUSE'};
      await flow.submit(33.71, 73.11, confirmed: true);
      expect(flow.code, 'RIDER_MUST_PAUSE');
      expect(flow.message, contains('Offline'));
    },
  );
  test('account change during read discards the old destination', () async {
    backend.loading = Completer();
    final load = flow.load();
    backend.account = 'other';
    backend.loading!.complete(backend.snapshot);
    await load;
    expect(flow.context, isNull);
    expect(flow.code, 'FORBIDDEN');
  });
  test(
    'account change during update never accepts the prior account result',
    () async {
      await flow.load();
      backend.pending = Completer();
      final save = flow.submit(33.71, 73.11, confirmed: true);
      backend.account = 'other';
      backend.pending!.complete(backend.result);
      await save;
      expect(flow.code, 'FORBIDDEN');
      expect(flow.context, isNull);
      await flow.retry();
      expect(backend.calls.length, 1);
    },
  );
  test(
    'malformed success remains uncertain for safe same-request reconciliation',
    () async {
      await flow.load();
      backend.result = {'code': 'OK', 'order_id': 2};
      await flow.submit(33.71, 73.11, confirmed: true);
      expect(flow.uncertain, isTrue);
      expect(flow.code, isNot('OK'));
    },
  );
  test(
    'switching away and back cannot resurrect the previous session response',
    () async {
      await flow.load();
      backend.pending = Completer();
      final save = flow.submit(33.71, 73.11, confirmed: true);
      backend.account = 'other';
      flow.accountChanged();
      backend.account = 'customer';
      backend.pending!.complete(backend.result);
      await save;
      expect(flow.code, isNot('OK'));
      expect(flow.context, isNull);
    },
  );
  test('closed screen cannot accept a delayed update or retry it', () async {
    await flow.load();
    backend.pending = Completer();
    final save = flow.submit(33.71, 73.11, confirmed: true);
    flow.dispose();
    backend.pending!.complete(backend.result);
    await save;
    await flow.retry();
    expect(flow.code, isNot('OK'));
    expect(backend.calls.length, 1);
  });
  testWidgets('denied role sees no map selection or update control', (
    tester,
  ) async {
    backend.snapshot = {'code': 'FORBIDDEN'};
    await tester.pumpWidget(
      GetMaterialApp(
        home: ChangeDeliveryDestinationScreen(orderId: 3180, backend: backend),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Only this order’s signed-in Customer can change its destination.',
      ),
      findsOneWidget,
    );
    expect(find.text('Choose delivery point'), findsNothing);
    expect(find.text('Save delivery location'), findsNothing);
    expect(backend.calls, isEmpty);
  });
  testWidgets(
    'paused-delivery prerequisite remains visible without any update action',
    (tester) async {
      backend.snapshot = {
        ...backend.snapshot,
        'can_change': false,
        'reason': 'RIDER_MUST_PAUSE',
      };
      await tester.pumpWidget(
        GetMaterialApp(
          home: ChangeDeliveryDestinationScreen(
            orderId: 3180,
            backend: backend,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('go Offline'), findsOneWidget);
      expect(find.text('Choose delivery point'), findsNothing);
      expect(backend.calls, isEmpty);
    },
  );
}
