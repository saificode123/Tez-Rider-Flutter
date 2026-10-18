import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/pre_delivery_checklist_service.dart';
import 'package:flutter_application_1/services/delivery_otp_service.dart';
import 'package:flutter_application_1/widgets/pre_delivery_checklist_card.dart';

Map<String, dynamic> state({int assignment = 10, bool completed = false}) => {
  'code': 'OK',
  'assignment_id': assignment,
  'assignment_status': 'Accepted',
  'version': 1,
  'order_status': 'ready',
  'completed': completed,
  'legacy_exempt': false,
  'items': [
    {'id': 'server-one', 'label': 'Items match the order.'},
    {'id': 'server-two', 'label': 'Packaging is sealed and undamaged.'},
    {
      'id': 'server-three',
      'label': 'Delivery address and customer details are confirmed.',
    },
  ],
};

class Backend implements ChecklistBackend {
  @override
  String accountId = 'rider-one';
  final calls = <String>[];
  final payloads = <Map<String, dynamic>>[];
  Map<String, dynamic> server = state();
  Future<Map<String, dynamic>> Function(String name)? pending;
  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> parameters,
  ) async {
    calls.add(name);
    payloads.add(parameters);
    if (pending != null) return pending!(name);
    if (name == 'pre_delivery_checklist') return server;
    if (name == 'start_checklisted_delivery') {
      return {'code': 'STARTED', 'order_status': 'on_the_way'};
    }
    return {
      'code': 'COMPLETED',
      'assignment_id': server['assignment_id'],
      'version': 1,
      'completed': true,
      'completed_at': '2026-10-17T12:00:00Z',
    };
  }
}

void all(PreDeliveryChecklistFlow flow) {
  for (final item in flow.items) {
    flow.choose(item['id'] as String, true);
  }
}

void main() {
  test(
    'server definition and all confirmations required; no automatic confirmations',
    () async {
      final backend = Backend();
      final flow = PreDeliveryChecklistFlow(backend);
      await flow.open(1);
      expect(flow.items.first['id'], 'server-one');
      expect(flow.selected, isEmpty);
      expect(flow.canSubmit, false);
      expect(flow.canStart, false);
      flow.choose('not-server-defined', true);
      expect(flow.selected, isEmpty);
      flow.choose('server-one', true);
      expect(flow.canSubmit, false);
      all(flow);
      expect(flow.canSubmit, true);
      expect(flow.canStart, false);
      expect(await flow.submit(), true);
      expect(flow.completed.value, true);
      expect(flow.canStart, true);
      expect(backend.payloads.last['p_confirmations'], [
        {'id': 'server-one', 'confirmed': true},
        {'id': 'server-two', 'confirmed': true},
        {'id': 'server-three', 'confirmed': true},
      ]);
      expect(await flow.start(), true);
      expect(flow.orderStatus.value, 'on_the_way');
    },
  );
  test('double submit blocked while server confirmation is pending', () async {
    final backend = Backend();
    final flow = PreDeliveryChecklistFlow(backend);
    await flow.open(1);
    all(flow);
    final completer = Completer<Map<String, dynamic>>();
    backend.pending = (_) => completer.future;
    final first = flow.submit();
    expect(flow.busy.value, true);
    expect(flow.completed.value, false);
    expect(flow.canStart, false);
    expect(await flow.submit(), false);
    expect(backend.calls.where((n) => n.startsWith('submit')).length, 1);
    completer.complete({
      'code': 'COMPLETED',
      'assignment_id': 10,
      'completed': true,
      'completed_at': 'server-time',
    });
    expect(await first, true);
    expect(flow.busy.value, false);
  });
  test(
    'network failure never shows success; same-assignment retry is safe',
    () async {
      final backend = Backend();
      final flow = PreDeliveryChecklistFlow(backend);
      await flow.open(1);
      all(flow);
      backend.pending = (_) async => throw TimeoutException('private detail');
      expect(await flow.submit(), false);
      expect(flow.completed.value, false);
      expect(flow.canStart, false);
      expect(flow.error.value, contains('Retry'));
      expect(flow.error.value, isNot(contains('private detail')));
      backend.pending = null;
      expect(await flow.submit(), true);
    },
  );
  test('server rejection is actionable and completion stays false', () async {
    final backend = Backend();
    final flow = PreDeliveryChecklistFlow(backend);
    await flow.open(1);
    all(flow);
    backend.pending = (_) async => {'code': 'PICKUP_REQUIRED'};
    expect(await flow.submit(), false);
    expect(flow.completed.value, false);
    expect(flow.error.value, contains('every vendor'));
  });
  test(
    'restores server completion after reopening; no cached local authority',
    () async {
      final backend = Backend()..server = state(completed: true);
      final flow = PreDeliveryChecklistFlow(backend);
      await flow.open(1);
      expect(flow.completed.value, true);
      expect(flow.canStart, true);
      expect(flow.selected, isEmpty);
      backend.server = state();
      await flow.refresh();
      expect(flow.completed.value, false);
      expect(flow.canStart, false);
    },
  );
  test('assignment switch resets confirmations and completed state', () async {
    final backend = Backend();
    final flow = PreDeliveryChecklistFlow(backend);
    await flow.open(1);
    all(flow);
    backend.server = state(assignment: 11);
    await flow.open(2);
    expect(flow.assignmentId.value, 11);
    expect(flow.selected, isEmpty);
    expect(flow.canStart, false);
    all(flow);
    backend.server = state(assignment: 12);
    await flow.refresh();
    expect(flow.selected, isEmpty);
  });
  test('stale load cannot restore previous assignment authority', () async {
    final backend = Backend();
    final completer = Completer<Map<String, dynamic>>();
    backend.pending = (_) => completer.future;
    final flow = PreDeliveryChecklistFlow(backend);
    final first = flow.open(1);
    backend.pending = null;
    backend.server = state(assignment: 20);
    await flow.open(2);
    completer.complete(state(completed: true));
    await first;
    expect(flow.assignmentId.value, 20);
    expect(flow.completed.value, false);
  });
  test('account change discards an old completion response', () async {
    final backend = Backend();
    final flow = PreDeliveryChecklistFlow(backend);
    await flow.open(1);
    all(flow);
    final completer = Completer<Map<String, dynamic>>();
    backend.pending = (_) => completer.future;
    final first = flow.submit();
    backend.accountId = 'rider-two';
    backend.pending = null;
    backend.server = state(assignment: 30);
    await flow.open(2);
    completer.complete({
      'code': 'COMPLETED',
      'assignment_id': 10,
      'completed': true,
      'completed_at': 'server-time',
    });
    expect(await first, false);
    expect(flow.assignmentId.value, 30);
    expect(flow.completed.value, false);
  });
  test('start rejection never changes parent status or consumes OTP', () async {
    final backend = Backend()..server = state(completed: true);
    final flow = PreDeliveryChecklistFlow(backend);
    await flow.open(1);
    backend.pending = (_) async => {'code': 'CHECKLIST_REQUIRED'};
    expect(await flow.start(), false);
    expect(flow.orderStatus.value, 'ready');
    expect(flow.error.value, contains('checklist'));
    expect(backend.calls, isNot(contains('verify_delivery_otp')));
  });
  test(
    'pending assignment and vendor preparation cannot enable submission',
    () async {
      final backend = Backend()
        ..server = {...state(), 'assignment_status': 'Pending'};
      final flow = PreDeliveryChecklistFlow(backend);
      await flow.open(1);
      all(flow);
      expect(flow.canSubmit, false);
      backend.server = {...state(), 'order_status': 'preparing'};
      await flow.refresh();
      all(flow);
      expect(flow.canSubmit, false);
    },
  );
  test('load failure can retry without fabricated items', () async {
    final backend = Backend()
      ..pending = (_) async => throw StateError('offline');
    final flow = PreDeliveryChecklistFlow(backend);
    await flow.open(1);
    expect(flow.loaded.value, false);
    expect(flow.items, isEmpty);
    expect(flow.canStart, false);
    backend.pending = null;
    await flow.refresh();
    expect(flow.loaded.value, true);
  });
  test('CHECKLIST_REQUIRED maps existing OTP UI to pickup action', () {
    expect(
      deliveryOtpMessage({'code': 'CHECKLIST_REQUIRED'}),
      contains('pickup checklist'),
    );
  });
  testWidgets(
    'visible server items, disabled incomplete submit/start, enables only after server completion',
    (tester) async {
      final backend = Backend();
      final flow = PreDeliveryChecklistFlow(backend);
      await flow.open(1);
      var started = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PreDeliveryChecklistCard(
                flow: flow,
                onAccept: () {},
                onStart: () {
                  started = true;
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('Items match the order.'), findsOneWidget);
      expect(find.text('Packaging is sealed and undamaged.'), findsOneWidget);
      expect(
        find.text('Delivery address and customer details are confirmed.'),
        findsOneWidget,
      );
      FilledButton button(String key) =>
          tester.widget<FilledButton>(find.byKey(Key(key)));
      expect(button('checklist-submit').onPressed, isNull);
      expect(button('checklist-start').onPressed, isNull);
      for (final id in ['server-one', 'server-two', 'server-three']) {
        await tester.tap(find.byKey(ValueKey('checklist-$id')));
        await tester.pump();
      }
      expect(button('checklist-submit').onPressed, isNotNull);
      expect(button('checklist-start').onPressed, isNull);
      await tester.tap(find.byKey(const Key('checklist-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Checklist completed'), findsOneWidget);
      expect(button('checklist-start').onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('checklist-start')));
      expect(started, true);
    },
  );
  testWidgets('loading and retry shown for real pending/error states', (
    tester,
  ) async {
    final backend = Backend();
    final completer = Completer<Map<String, dynamic>>();
    backend.pending = (_) => completer.future;
    final flow = PreDeliveryChecklistFlow(backend);
    final opening = flow.open(1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreDeliveryChecklistCard(
            flow: flow,
            onAccept: () {},
            onStart: () {},
          ),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    completer.completeError(TimeoutException('offline'));
    await opening;
    await tester.pump();
    expect(find.text('Retry checklist'), findsOneWidget);
    backend.pending = null;
    await tester.tap(find.text('Retry checklist'));
    await tester.pumpAndSettle();
    expect(find.text('Items match the order.'), findsOneWidget);
  });
}
