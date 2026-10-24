import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/feedback_service.dart';
import 'package:flutter_application_1/screens/customer/rating_screen.dart';

Map<String, dynamic> result(
  Map<String, dynamic> p, [
  String code = 'SUBMITTED',
]) => {
  'code': code,
  'id': p['p_request_id'],
  'order_id': p['p_order_id'],
  'target_id': p['p_target_id'],
  'rating': p['p_rating'],
  'comment': p['p_comment'],
};
Map<String, dynamic> context() => {
  'code': 'OK',
  'order_id': 4,
  'targets': [
    {'target_id': 7, 'role': 'vendor', 'name': 'Test store', 'review': null},
    {
      'target_id': 8,
      'role': 'rider',
      'name': 'Test Rider',
      'review': {'rating': 3, 'comment': 'Saved Rider comment'},
    },
  ],
};
void main() {
  test(
    'canonical context separates Vendor and Rider, preserves saved review',
    () async {
      final s = FeedbackService(
        identity: () => 'A',
        rpc: (n, p) async => context(),
      );
      final targets = await s.context(4);
      expect(targets.map((t) => t['target_id']), [7, 8]);
      expect(targets.last['review']['rating'], 3);
    },
  );
  test('rejects malformed/duplicate targets and wrong order', () async {
    for (final value in [
      {'code': 'OK', 'order_id': 5, 'targets': []},
      {
        'code': 'OK',
        'order_id': 4,
        'targets': [
          {'target_id': '7', 'role': 'vendor', 'name': 'Bad'},
        ],
      },
      {
        'code': 'OK',
        'order_id': 4,
        'targets': [context()['targets'][0], context()['targets'][0]],
      },
    ]) {
      await expectLater(
        FeedbackService(
          identity: () => 'A',
          rpc: (n, p) async => value,
        ).context(4),
        throwsFormatException,
      );
    }
  });
  test('late account response is discarded', () async {
    var identity = 'A';
    final response = Completer<dynamic>();
    final s = FeedbackService(
      identity: () => identity,
      rpc: (n, p) => response.future,
    );
    final pending = s.context(4);
    identity = 'B';
    response.complete(context());
    await expectLater(pending, throwsStateError);
  });
  test(
    'uncertain retry sends identical UUID and payload despite changed arguments',
    () async {
      final calls = <Map<String, dynamic>>[];
      final s = FeedbackService(
        identity: () => 'A',
        rpc: (n, p) async {
          calls.add(Map.of(p));
          if (calls.length == 1) throw TimeoutException('offline');
          return result(p, 'ALREADY_APPLIED');
        },
      );
      final write = FeedbackSubmission(s, 4, 7);
      await expectLater(
        write.submit(4, ' original '),
        throwsA(isA<TimeoutException>()),
      );
      expect(write.uncertain, true);
      final value = await write.submit(1, 'changed');
      expect(calls[1], calls[0]);
      expect(value['rating'], 4);
      expect(write.uncertain, false);
    },
  );
  test('duplicate busy submission cannot issue another request', () async {
    final response = Completer<dynamic>();
    var calls = 0;
    late Map<String, dynamic> params;
    final s = FeedbackService(
      identity: () => 'A',
      rpc: (n, p) {
        calls++;
        params = p;
        return response.future;
      },
    );
    final write = FeedbackSubmission(s, 4, 7);
    final first = write.submit(5, '');
    await expectLater(write.submit(4, ''), throwsStateError);
    expect(calls, 1);
    response.complete(result(params));
    await first;
    expect(write.busy, false);
  });
  test(
    'validation is explicit and a server rejection permits corrected input',
    () async {
      var calls = 0;
      final s = FeedbackService(
        identity: () => 'A',
        rpc: (n, p) async {
          calls++;
          if (calls == 1) {
            throw const PostgrestException(message: 'invalid', code: '22023');
          }
          return result(p);
        },
      );
      final write = FeedbackSubmission(s, 4, 7);
      await expectLater(write.submit(0, ''), throwsFormatException);
      expect(calls, 0);
      await expectLater(
        write.submit(3, ''),
        throwsA(isA<PostgrestException>()),
      );
      expect(write.uncertain, false);
      expect((await write.submit(4, 'fixed'))['rating'], 4);
    },
  );
  test('malformed success stays uncertain and cannot cross accounts', () async {
    var identity = 'A';
    var calls = 0;
    final write = FeedbackSubmission(
      FeedbackService(
        identity: () => identity,
        rpc: (n, p) async {
          calls++;
          return {'code': 'SUBMITTED'};
        },
      ),
      4,
      7,
    );
    await expectLater(write.submit(4, ''), throwsFormatException);
    expect(write.uncertain, true);
    identity = 'B';
    await expectLater(write.submit(4, ''), throwsStateError);
    expect(calls, 1);
  });
  test(
    'already reviewed returns original saved stars instead of claimed new feedback',
    () async {
      final write = FeedbackSubmission(
        FeedbackService(
          identity: () => 'A',
          rpc: (n, p) async => {
            ...result(p, 'ALREADY_REVIEWED'),
            'rating': 2,
            'comment': 'Original',
          },
        ),
        4,
        7,
      );
      final saved = await write.submit(5, 'Different');
      expect(saved['rating'], 2);
      expect(saved['comment'], 'Original');
    },
  );
  test(
    'summary accepts no ratings without fabricated average, rejects invalid count/average',
    () async {
      final empty = {
        'code': 'OK',
        'target_id': 7,
        'role': 'vendor',
        'count': 0,
        'average': null,
        'recent': [],
      };
      expect(
        (await FeedbackService(
          identity: () => 'A',
          rpc: (n, p) async => empty,
        ).summary(7))['average'],
        null,
      );
      for (final wrong in [
        {...empty, 'average': 5},
        {...empty, 'count': 1},
        {...empty, 'target_id': 9},
      ]) {
        await expectLater(
          FeedbackService(
            identity: () => 'A',
            rpc: (n, p) async => wrong,
          ).summary(7),
          throwsFormatException,
        );
      }
    },
  );
  testWidgets(
    'actual submit handler uses selected Vendor, starts disabled, shows stored result',
    (t) async {
      Map<String, dynamic>? sent;
      final service = FeedbackService(
        identity: () => 'A',
        rpc: (name, p) async {
          if (name == 'final2_feedback_context') return context();
          sent = p;
          return result(p);
        },
      );
      await t.pumpWidget(
        MaterialApp(home: RatingScreen(orderId: 4, service: service)),
      );
      await t.pumpAndSettle();
      expect(find.text('Vendor: Test store'), findsOneWidget);
      expect(find.text('Saved rating: 3/5'), findsOneWidget);
      expect(
        t.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      await t.tap(find.byTooltip('4 stars'));
      await t.pump();
      await t.tap(find.text('Submit feedback'));
      await t.pumpAndSettle();
      expect(sent!['p_target_id'], 7);
      expect(sent!['p_rating'], 4);
      expect(find.text('Saved rating: 4/5'), findsOneWidget);
    },
  );
  testWidgets('load failure exposes Retry and actual reload recovers', (
    t,
  ) async {
    var calls = 0;
    final service = FeedbackService(
      identity: () => 'A',
      rpc: (n, p) async {
        if (++calls == 1) throw TimeoutException('offline');
        return context();
      },
    );
    await t.pumpWidget(
      MaterialApp(home: RatingScreen(orderId: 4, service: service)),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Vendor: Test store'), findsOneWidget);
  });
  testWidgets(
    'network uncertainty locks fields and retry restores confirmed original rating',
    (t) async {
      var writes = 0;
      final service = FeedbackService(
        identity: () => 'A',
        rpc: (n, p) async {
          if (n == 'final2_feedback_context') return context();
          if (++writes == 1) throw TimeoutException('offline');
          return result(p, 'ALREADY_APPLIED');
        },
      );
      await t.pumpWidget(
        MaterialApp(home: RatingScreen(orderId: 4, service: service)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('2 stars'));
      await t.pump();
      await t.tap(find.text('Submit feedback'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).enabled, false);
      await t.tap(find.text('Retry same feedback'));
      await t.pumpAndSettle();
      expect(writes, 2);
      expect(find.text('Saved rating: 2/5'), findsOneWidget);
    },
  );
  testWidgets(
    'account switch immediately clears previous order feedback and saved comment',
    (t) async {
      var account = 'A';
      final changes = StreamController<void>.broadcast(sync: true);
      final service = FeedbackService(
        identity: () => account,
        accountChanges: changes.stream,
        rpc: (n, p) async {
          if (account != 'A') {
            throw const PostgrestException(message: 'denied', code: '42501');
          }
          return context();
        },
      );
      await t.pumpWidget(
        MaterialApp(home: RatingScreen(orderId: 4, service: service)),
      );
      await t.pumpAndSettle();
      expect(find.text('Saved Rider comment'), findsOneWidget);
      account = 'B';
      changes.add(null);
      await t.pumpAndSettle();
      expect(find.text('Saved Rider comment'), findsNothing);
      expect(find.text('Vendor: Test store'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await changes.close();
    },
  );
}
