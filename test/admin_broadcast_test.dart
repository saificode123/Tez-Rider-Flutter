import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/controllers/admin_broadcast_controller.dart';
import 'package:flutter_application_1/screens/admin_broadcasts_screen.dart';
import 'package:flutter_application_1/services/admin_broadcast_service.dart';

class FakeBroadcastBackend implements AdminBroadcastBackend {
  int calls = 0, pages = 0;
  bool fail = false;
  String code = 'SENT';
  Completer<Map<String, dynamic>>? completer;
  Completer<List<Map<String, dynamic>>>? historyWait;
  final requests = <Map<String, dynamic>>[];
  final audiences = <String>[];
  Map<String, dynamic>? cursor;
  List<Map<String, dynamic>> rows = [];
  @override
  Future<int> estimate(String audience) async {
    audiences.add(audience);
    return 7;
  }

  @override
  Future<List<Map<String, dynamic>>> history(
    Map<String, dynamic>? before,
  ) async {
    pages++;
    cursor = before;
    final pending = historyWait;
    historyWait = null;
    if (pending != null) return pending.future;
    return rows;
  }

  @override
  Future<Map<String, dynamic>> send(Map<String, dynamic> request) async {
    calls++;
    requests.add(request);
    if (fail) throw TimeoutException('offline');
    return completer?.future ??
        Future.value({
          'code': code,
          'recipient_count': 7,
          'retry_after_seconds': 45,
        });
  }
}

void main() {
  test('invalid input never reaches server', () async {
    final backend = FakeBroadcastBackend();
    final c = AdminBroadcastController(backend: backend);
    expect(await c.send(' ', 'a'), false);
    expect(await c.send('a' * 101, 'a'), false);
    expect(await c.send('a', 'b' * 1001), false);
    expect(backend.calls, 0);
  });
  test(
    'busy request blocks duplicate submission and clears after authoritative success',
    () async {
      final backend = FakeBroadcastBackend()..completer = Completer();
      final c = AdminBroadcastController(backend: backend);
      final first = c.send('title', 'body');
      expect(c.sending.value, true);
      expect(await c.send('title', 'body'), false);
      expect(backend.calls, 1);
      backend.completer!.complete({'code': 'SENT', 'recipient_count': 7});
      expect(await first, true);
      expect(c.sending.value, false);
      expect(c.feedback.value, contains('7 recipients'));
      expect(backend.pages, 1);
    },
  );
  test(
    'timeout retry retains exact UUID, audience and original trimmed payload',
    () async {
      final backend = FakeBroadcastBackend()..fail = true;
      final c = AdminBroadcastController(backend: backend);
      c.audience.value = 'CUSTOMERS';
      expect(await c.send(' title ', ' body '), false);
      expect(c.uncertain.value, true);
      backend.fail = false;
      backend.code = 'ALREADY_SENT';
      expect(await c.send('changed', 'changed'), true);
      expect(backend.requests[0], backend.requests[1]);
      expect(backend.requests[0]['p_title'], 'title');
      expect(c.uncertain.value, false);
    },
  );
  for (final code in [
    'FORBIDDEN',
    'COOLDOWN',
    'DAILY_LIMIT',
    'IDEMPOTENCY_CONFLICT',
    'INVALID_INPUT',
  ]) {
    test('$code is reported without success', () async {
      final backend = FakeBroadcastBackend()..code = code;
      final c = AdminBroadcastController(backend: backend);
      expect(await c.send('title', 'body'), false);
      expect(c.feedback.value, isNot(contains('Accepted for')));
      expect(c.uncertain.value, false);
      expect(backend.pages, 0);
    });
  }
  test('send during history load refreshes after the older response', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    final backend = FakeBroadcastBackend()..historyWait = pending;
    final c = AdminBroadcastController(backend: backend);
    final initial = c.loadHistory();
    expect(await c.send('title', 'body'), true);
    backend.rows = [
      {'id': 'accepted-broadcast'},
    ];
    pending.complete([]);
    await initial;
    expect(c.history.single['id'], 'accepted-broadcast');
    expect(backend.pages, 2);
  });
  test('history uses last stable cursor and deduplicates pages', () async {
    final backend = FakeBroadcastBackend()
      ..rows = List.generate(25, (i) => {'id': '$i'});
    final c = AdminBroadcastController(backend: backend);
    await c.loadHistory();
    expect(c.hasMore.value, true);
    backend.rows = [
      {'id': '24'},
      {'id': '25'},
    ];
    await c.loadHistory(append: true);
    expect(backend.cursor, {'id': '24'});
    expect(c.history.length, 26);
    expect(c.hasMore.value, false);
  });
  testWidgets(
    'validation, audience, estimate, confirmation cancellation and actual send',
    (tester) async {
      final backend = FakeBroadcastBackend();
      final c = AdminBroadcastController(backend: backend);
      await tester.pumpWidget(
        MaterialApp(home: AdminBroadcastsScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Estimated recipients: 7 (informational)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Review broadcast'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a title'), findsOneWidget);
      expect(backend.calls, 0);
      await tester.enterText(find.byType(TextFormField).at(0), 'A notice');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '<b>Literal message</b>',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customers').last);
      await tester.pumpAndSettle();
      expect(backend.audiences.last, 'CUSTOMERS');
      await tester.ensureVisible(find.text('Review broadcast'));
      await tester.tap(find.text('Review broadcast'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Audience: Customers'), findsOneWidget);
      expect(find.textContaining('Estimated recipients: 7\n'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.calls, 0);
      await tester.tap(find.text('Review broadcast'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm send'));
      await tester.pumpAndSettle();
      expect(backend.calls, 1);
      expect(find.textContaining('Accepted for 7 recipients'), findsOneWidget);
      expect(backend.requests.single['p_message'], '<b>Literal message</b>');
    },
  );
}
