import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/admin_monitor_service.dart';
import 'package:flutter_application_1/screens/admin_monitor_screen.dart';

Map<String, dynamic> snapshot({bool export = false, bool assigned = false}) => {
  'code': 'OK',
  'generated_at': '2026-10-24T12:00:00Z',
  'has_more': false,
  'export_complete': export,
  'locations_truncated': false,
  'summary': {
    'total_orders': 2,
    'active_orders': 1,
    'delivered_orders': 1,
    'delivered_value_cents': '2575',
    'unconfirmed_amounts': 0,
    'online_riders': 0,
    'status_counts': {'ready': 1, 'delivered': 1},
  },
  'orders': [
    {
      'order_id': 20,
      'status': 'ready',
      'created_at': '2026-10-24T10:00:00Z',
      'delivered_at': null,
      'rider_id': assigned ? 301 : null,
      'manual_assignment': !assigned,
      'amount_cents': '1225',
    },
    {
      'order_id': 19,
      'status': 'delivered',
      'created_at': '2026-10-24T09:00:00Z',
      'delivered_at': '2026-10-24T09:30:00Z',
      'rider_id': 302,
      'manual_assignment': false,
      'amount_cents': '2575',
    },
  ],
  'rider_locations': [],
};
Map<String, dynamic> candidates() => {
  'code': 'OK',
  'order_id': 20,
  'candidates': [
    {'rider_id': 301, 'name': 'Unit Rider A', 'distance_m': 12000},
    {'rider_id': 302, 'name': 'Unit Rider B', 'distance_m': 13000},
  ],
};
Map<String, dynamic> response(Map<String, dynamic> params) {
  final value = snapshot(export: params['p_export'] == true);
  final status = params['p_status'];
  if (status != null) {
    final rows = (value['orders'] as List)
        .where((r) => r['status'] == status)
        .toList();
    value['orders'] = rows;
    value['summary'] = {
      ...value['summary'],
      'total_orders': rows.length,
      'active_orders': status == 'delivered' || status == 'cancelled'
          ? 0
          : rows.length,
      'delivered_orders': status == 'delivered' ? rows.length : 0,
      'delivered_value_cents': status == 'delivered' ? '2575' : '0',
      'status_counts': {if (rows.isNotEmpty) status: rows.length},
    };
  }
  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('export locks its filter until the platform copy completes', (
    t,
  ) async {
    final pending = Completer<dynamic>();
    final service = AdminMonitorService(
      identity: () => 'a',
      rpc: (_, params) async {
        if (params['p_export'] == true) return pending.future;
        return snapshot();
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await t.pumpWidget(
      MaterialApp(
        home: AdminMonitorPanel(
          service: service,
          events: const Stream<void>.empty(),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Copy CSV'));
    await t.pump();
    expect(
      t
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged,
      isNull,
    );
    expect(
      t
          .widget<TextButton>(find.widgetWithText(TextButton, 'Filter dates'))
          .onPressed,
      isNull,
    );
    pending.complete(snapshot(export: true));
    await t.pumpAndSettle();
    expect(
      t
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged,
      isNotNull,
    );
    await t.pumpWidget(const SizedBox());
  });
  test(
    'monitor sends actual filters, bound and export flag; exact cents preserved',
    () async {
      Map<String, dynamic>? sent;
      final service = AdminMonitorService(
        identity: () => 'admin-a',
        rpc: (name, p) async {
          expect(name, 'final2_admin_order_monitor');
          sent = p;
          return response(p);
        },
      );
      final value = await service.load(
        before: 25,
        status: 'delivered',
        from: DateTime.utc(2026, 10, 1),
        to: DateTime.utc(2026, 11, 1),
      );
      expect(sent!['p_before'], 25);
      expect(sent!['p_status'], 'delivered');
      expect(sent!['p_limit'], 30);
      expect(sent!['p_export'], false);
      expect(sent!['p_from'], '2026-10-01T00:00:00.000Z');
      expect(value['summary']['delivered_value_cents'], '2575');
    },
  );
  test(
    'malformed/inconsistent counts, duplicate orders and bad location fail closed',
    () async {
      for (final value in [
        {
          ...snapshot(),
          'summary': {...snapshot()['summary'], 'total_orders': 3},
        },
        {
          ...snapshot(),
          'orders': [snapshot()['orders'][0], snapshot()['orders'][0]],
        },
        {
          ...snapshot(),
          'rider_locations': [
            {
              'rider_id': 301,
              'available': true,
              'latitude': double.nan,
              'longitude': 0,
              'observed_at': '2026-10-24T12:00:00Z',
            },
          ],
        },
        {...snapshot(), 'export_complete': true},
      ]) {
        await expectLater(
          AdminMonitorService(
            identity: () => 'a',
            rpc: (_, p) async => value,
          ).load(),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'export refuses a truncated result and CSV neutralizes formula cells',
    () async {
      final partial = {
        ...snapshot(export: true),
        'orders': [snapshot()['orders'][0]],
      };
      await expectLater(
        AdminMonitorService(
          identity: () => 'a',
          rpc: (_, p) async => partial,
        ).load(export: true),
        throwsFormatException,
      );
      expect(() => monitorCsv(snapshot()), throwsFormatException);
      final full = snapshot(export: true);
      full['orders'][0]['status'] = '=HYPERLINK("bad")';
      final csv = monitorCsv(full);
      expect(csv, contains('"\'=HYPERLINK(""bad"")"'));
      expect(csv.split('\r\n').length, 3);
      expect(csv, contains('"2575"'));
    },
  );
  test(
    'candidate errors and forged distances cannot produce eligible choices',
    () async {
      await expectLater(
        AdminMonitorService(
          identity: () => 'a',
          rpc: (_, p) async => {
            'code': 'NOT_ELIGIBLE',
            'order_id': 20,
            'candidates': [],
          },
        ).candidates(20),
        throwsStateError,
      );
      final bad = candidates();
      bad['candidates'][0]['distance_m'] = -1;
      await expectLater(
        AdminMonitorService(
          identity: () => 'a',
          rpc: (_, p) async => bad,
        ).candidates(20),
        throwsFormatException,
      );
    },
  );
  test(
    'uncertain assignment retry uses identical selected Rider and request UUID',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = AdminMonitorService(
        identity: () => 'a',
        rpc: (_, p) async {
          calls.add(Map.of(p));
          if (calls.length == 1) {
            throw TimeoutException('injected response loss');
          }
          return {
            'code': 'ALREADY_APPLIED',
            'order_id': 20,
            'rider_id': 301,
            'assignment_id': 900,
          };
        },
      );
      final submission = ManualRiderAssignment(service, 20);
      await expectLater(
        submission.assign(301),
        throwsA(isA<TimeoutException>()),
      );
      expect(submission.uncertain, isTrue);
      final result = await submission.assign(302);
      expect(result['assignment_id'], 900);
      expect(calls[1], calls[0]);
      expect(submission.uncertain, isFalse);
    },
  );
  test(
    'duplicate in-flight request and cross-account uncertain replay are rejected',
    () async {
      String? account = 'a';
      final pending = Completer<dynamic>();
      var calls = 0;
      final service = AdminMonitorService(
        identity: () => account,
        rpc: (_, p) {
          calls++;
          return pending.future;
        },
      );
      final submission = ManualRiderAssignment(service, 20);
      final saving = expectLater(submission.assign(301), throwsStateError);
      await expectLater(submission.assign(301), throwsStateError);
      account = 'b';
      pending.complete({
        'code': 'ASSIGNED',
        'order_id': 20,
        'rider_id': 301,
        'assignment_id': 900,
      });
      await saving;
      await expectLater(submission.assign(301), throwsStateError);
      expect(calls, 1);
    },
  );
  test(
    'assignment conflict never reports success or replaces an unconfirmed response',
    () async {
      final service = AdminMonitorService(
        identity: () => 'a',
        rpc: (_, p) async => {'code': 'RETRYABLE_CONFLICT', 'order_id': 20},
      );
      final submission = ManualRiderAssignment(service, 20);
      expect((await submission.assign(301))['code'], 'RETRYABLE_CONFLICT');
      expect(submission.uncertain, isTrue);
    },
  );
  Future<void> open(
    WidgetTester t,
    AdminMonitorService service, {
    Stream<void>? events,
  }) async {
    await t.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: AdminMonitorPanel(
          service: service,
          events: events ?? const Stream<void>.empty(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'actual filter and complete CSV action use backend data rather than loaded-page assumptions',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'];
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final service = AdminMonitorService(
        identity: () => 'a',
        rpc: (_, p) async {
          calls.add(p);
          return response(p);
        },
      );
      await open(t, service);
      expect(find.text('Delivered order value: PKR 25.75'), findsOneWidget);
      expect(
        find.text('No fresh online Rider locations to display.'),
        findsOneWidget,
      );
      await t.tap(find.byType(DropdownButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('ready').last);
      await t.pumpAndSettle();
      expect(calls.last['p_status'], 'ready');
      await t.tap(find.text('Copy CSV'));
      await t.pumpAndSettle();
      expect(calls.last['p_export'], true);
      expect(copied, contains('gross_order_cents_PKR'));
      expect(copied!.split('\r\n').length, 2);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual Cancel makes no assignment; Confirm waits for server and refreshes assigned state',
    (t) async {
      var assigned = false;
      var writes = 0;
      final service = AdminMonitorService(
        identity: () => 'a',
        rpc: (name, p) async {
          if (name == 'final2_admin_assignment_candidates') return candidates();
          if (name == 'final2_admin_assign_rider') {
            writes++;
            assigned = true;
            return {
              'code': 'ASSIGNED',
              'order_id': 20,
              'rider_id': 301,
              'assignment_id': 900,
            };
          }
          return snapshot(assigned: assigned);
        },
      );
      await open(t, service);
      await t.ensureVisible(find.text('Assign Rider'));
      await t.tap(find.text('Assign Rider'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(writes, 0);
      await t.ensureVisible(find.text('Assign Rider'));
      await t.tap(find.text('Assign Rider'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm assignment'));
      await t.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Rider: 301'), findsOneWidget);
      expect(find.text('Assign Rider'), findsNothing);
      expect(
        find.text('Assignment confirmed. Rider acceptance is pending.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual response-loss dialog locks selection and Retry repeats one request',
    (t) async {
      final writes = <Map<String, dynamic>>[];
      var assigned = false;
      final service = AdminMonitorService(
        identity: () => 'a',
        rpc: (name, p) async {
          if (name == 'final2_admin_assignment_candidates') return candidates();
          if (name == 'final2_admin_assign_rider') {
            writes.add(Map.of(p));
            if (writes.length == 1) throw TimeoutException('injected');
            assigned = true;
            return {
              'code': 'ALREADY_APPLIED',
              'order_id': 20,
              'rider_id': 301,
              'assignment_id': 900,
            };
          }
          return snapshot(assigned: assigned);
        },
      );
      await open(t, service);
      await t.ensureVisible(find.text('Assign Rider'));
      await t.tap(find.text('Assign Rider'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm assignment'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Result not confirmed. Retry uses the same assignment request.',
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .onChanged,
        isNull,
      );
      await t.tap(find.text('Retry assignment'));
      await t.pumpAndSettle();
      expect(writes.length, 2);
      expect(writes[1], writes[0]);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'replayed historical receipt does not claim a cancelled order is pending',
    (t) async {
      var attempts = 0;
      final service = AdminMonitorService(
        identity: () => 'a',
        rpc: (name, params) async {
          if (name == 'final2_admin_assignment_candidates') return candidates();
          if (name == 'final2_admin_assign_rider') {
            if (++attempts == 1) {
              throw TimeoutException('original response lost');
            }
            return {
              'code': 'ALREADY_APPLIED',
              'order_id': 20,
              'rider_id': 301,
              'assignment_id': 900,
            };
          }
          final value = snapshot(assigned: attempts > 0);
          if (attempts > 0) {
            value['orders'][0]['status'] = 'cancelled';
            value['orders'][0]['manual_assignment'] = false;
            value['summary']['active_orders'] = 0;
            value['summary']['status_counts'] = {
              'cancelled': 1,
              'delivered': 1,
            };
          }
          return value;
        },
      );
      await open(t, service);
      await t.ensureVisible(find.text('Assign Rider'));
      await t.tap(find.text('Assign Rider'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm assignment'));
      await t.pumpAndSettle();
      await t.tap(find.text('Retry assignment'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Original assignment receipt confirmed. Review the refreshed order status.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Assignment confirmed. Rider acceptance is pending.'),
        findsNothing,
      );
      expect(find.text('Order #20 • cancelled'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual account switch removes open private candidate dialog and order data',
    (t) async {
      String? account = 'a';
      final changes = StreamController<void>.broadcast(sync: true);
      final service = AdminMonitorService(
        identity: () => account,
        accountChanges: changes.stream,
        rpc: (name, p) async => name == 'final2_admin_assignment_candidates'
            ? candidates()
            : snapshot(),
      );
      await open(t, service);
      await t.ensureVisible(find.text('Assign Rider'));
      await t.tap(find.text('Assign Rider'));
      await t.pumpAndSettle();
      expect(find.textContaining('Unit Rider A'), findsOneWidget);
      account = 'b';
      changes.add(null);
      await t.pump();
      await t.pumpAndSettle();
      expect(find.textContaining('Unit Rider A'), findsNothing);
      expect(find.textContaining('Order #20'), findsNothing);
      expect(
        find.text('Account changed. Open monitoring again.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await changes.close();
    },
  );
  testWidgets(
    'actual live event refresh is bounded and Retry recovers from a real error state',
    (t) async {
      var reads = 0;
      final events = StreamController<void>.broadcast();
      final service = AdminMonitorService(
        identity: () => 'a',
        rpc: (_, p) async {
          if (++reads == 1) throw TimeoutException('injected');
          return snapshot();
        },
      );
      await open(t, service, events: events.stream);
      expect(find.text('Retry'), findsOneWidget);
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(reads, 2);
      events.add(null);
      events.add(null);
      events.add(null);
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(reads, 3);
      await t.pumpWidget(const SizedBox());
      await events.close();
    },
  );
}
