import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/post_pickup_cancellation.dart';
import 'package:flutter_application_1/widgets/post_pickup_cancellation_card.dart';

void main() {
  test('uncertain retry retains exact UUID, confirmation and reason', () async {
    final requests = <Map<String, dynamic>>[];
    final flow = PostPickupCancellation(
      identity: () => 'owner',
      submit: (args) async {
        requests.add(args);
        if (requests.length == 1) throw TimeoutException('offline');
        return {'code': 'CANCELLED', 'order_id': 42};
      },
    );
    await expectLater(
      flow.cancel(42, 'Cannot receive delivery'),
      throwsA(isA<TimeoutException>()),
    );
    expect(flow.pending, isTrue);
    await expectLater(flow.cancel(42, 'Changed reason'), throwsStateError);
    expect(await flow.cancel(42, 'Cannot receive delivery'), 'CANCELLED');
    expect(requests[0], requests[1]);
    expect(requests[0]['p_confirmed'], isTrue);
    expect(flow.pending, isFalse);
  });
  test('wrong-owner late response never confirms cancellation', () async {
    var account = 'a';
    final pending = Completer<dynamic>();
    final flow = PostPickupCancellation(
      identity: () => account,
      submit: (_) => pending.future,
    );
    final result = expectLater(
      flow.cancel(42, 'Cannot receive delivery'),
      throwsStateError,
    );
    account = 'b';
    pending.complete({'code': 'CANCELLED', 'order_id': 42});
    await result;
  });
  test('validation and payment review cannot fabricate success', () async {
    var calls = 0;
    final flow = PostPickupCancellation(
      identity: () => 'a',
      submit: (_) async {
        calls++;
        return {'code': 'PAYMENT_REVIEW_REQUIRED', 'order_id': 42};
      },
    );
    await expectLater(flow.cancel(42, 'x'), throwsFormatException);
    expect(calls, 0);
    expect(
      await flow.cancel(42, 'Cannot receive delivery'),
      'PAYMENT_REVIEW_REQUIRED',
    );
    expect(flow.pending, isFalse);
  });
  test(
    'duplicate submission is refused while server result is pending',
    () async {
      final pending = Completer<dynamic>();
      final flow = PostPickupCancellation(
        identity: () => 'a',
        submit: (_) => pending.future,
      );
      final first = flow.cancel(42, 'Cannot receive delivery');
      await expectLater(
        flow.cancel(42, 'Cannot receive delivery'),
        throwsStateError,
      );
      pending.complete({'code': 'CANCELLED', 'order_id': 42});
      expect(await first, 'CANCELLED');
    },
  );
  testWidgets(
    'Keep order produces no write; Confirm shows only verified result',
    (tester) async {
      var writes = 0, refreshes = 0;
      final flow = PostPickupCancellation(
        identity: () => 'a',
        submit: (_) async {
          writes++;
          return {'code': 'CANCELLED', 'order_id': 42};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostPickupCancellationCard(
              orderId: 42,
              service: flow,
              onChanged: () => refreshes++,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Cannot receive delivery');
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep order'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm cancellation'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(refreshes, 1);
      expect(find.text('Order cancellation confirmed.'), findsOneWidget);
    },
  );
  testWidgets(
    'payment review leaves order unchanged and never refreshes as success',
    (tester) async {
      var refreshes = 0;
      final flow = PostPickupCancellation(
        identity: () => 'a',
        submit: (_) async => {
          'code': 'PAYMENT_REVIEW_REQUIRED',
          'order_id': 42,
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostPickupCancellationCard(
              orderId: 42,
              service: flow,
              onChanged: () => refreshes++,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Cannot receive delivery');
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm cancellation'));
      await tester.pumpAndSettle();
      expect(refreshes, 0);
      expect(
        find.textContaining('require Admin review before cancellation'),
        findsOneWidget,
      );
    },
  );
}
