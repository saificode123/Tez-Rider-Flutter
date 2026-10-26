import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/rider_earnings_service.dart';
import 'package:flutter_application_1/widgets/rider_earnings_panel.dart';

Map<String, dynamic> quote() => {
  'code': 'OK',
  'rider_id': 12,
  'order_id': 42,
  'currency': 'PKR',
  'frozen': false,
  'distance_method': 'straight_line',
  'distance_km': 3.2,
  'base_amount': 60,
  'per_km_rate': 20,
  'minimum_amount': 80,
  'expected_amount': 124,
  'earnings_only': true,
};
Map<String, dynamic> entry(int id) => {
  'id': id,
  'order_id': 42,
  'earned_at': '2026-10-25T10:00:00Z',
  'distance_km': 3.2,
  'distance_method': 'straight_line',
  'base_amount': 60,
  'per_km_rate': 20,
  'distance_amount': 64,
  'amount': 124,
  'kind': 'delivery',
  'admin_review_required': true,
};
Map<String, dynamic> history({int id = 2, int? next}) => {
  'code': 'OK',
  'rider_id': 12,
  'total_amount': 248,
  'record_count': 2,
  'entries': [entry(id)],
  'next_before': next,
  'earnings_only': true,
};

void main() {
  test(
    'quote displays trusted settings rather than recalculating policy in Flutter',
    () async {
      final server = {...quote(), 'base_amount': 100, 'expected_amount': 164};
      final service = RiderEarningsService(
        identity: () => 'a',
        read: (name, args) async {
          expect(name, 'final_delivery_rider_quote');
          expect(args, {'p_order_id': 42});
          return server;
        },
      );
      expect((await service.quote(42))['expected_amount'], 164);
    },
  );
  test(
    'unconfirmed, wrong-order and invalid numeric responses are rejected',
    () async {
      for (final value in [
        {...quote(), 'order_id': 43},
        {...quote(), 'expected_amount': double.nan},
        {...quote(), 'earnings_only': false},
        {...quote(), 'distance_method': 'fabricated'},
        {...quote(), 'code': 'FORBIDDEN'},
      ]) {
        await expectLater(
          RiderEarningsService(
            identity: () => 'a',
            read: (_, __) async => value,
          ).quote(42),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'history rejects duplicate rows, invalid dates and payout claims',
    () async {
      for (final value in [
        {
          ...history(),
          'entries': [entry(2), entry(2)],
        },
        {
          ...history(),
          'entries': [
            {...entry(2), 'earned_at': 'invalid'},
          ],
        },
        {
          ...history(),
          'entries': [
            {...entry(2), 'kind': 'paid_out'},
          ],
        },
      ]) {
        await expectLater(
          RiderEarningsService(
            identity: () => 'a',
            read: (_, __) async => value,
          ).history(),
          throwsFormatException,
        );
      }
    },
  );
  test('in-flight account switch cannot expose prior earnings', () async {
    var account = 'a';
    final pending = Completer<dynamic>();
    final result = RiderEarningsService(
      identity: () => account,
      read: (_, __) => pending.future,
    ).history();
    final denied = expectLater(result, throwsStateError);
    account = 'b';
    pending.complete(history());
    await denied;
  });
  testWidgets(
    'history retries failures, pages and explicitly disclaims payout',
    (tester) async {
      var calls = 0;
      final service = RiderEarningsService(
        identity: () => 'a',
        read: (_, args) async {
          if (++calls == 1) throw TimeoutException('offline');
          return history(
            id: args['p_before'] == null ? 2 : 1,
            next: args['p_before'] == null ? 2 : null,
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RiderEarningsPanel(service: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Total: PKR 248'), findsOneWidget);
      expect(find.textContaining('not a payout confirmation'), findsOneWidget);
      await tester.ensureVisible(find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Order #42 · PKR 124'), findsNWidgets(2));
      expect(find.text('Load more'), findsNothing);
      expect(find.textContaining('no automatic deduction'), findsNWidgets(2));
    },
  );
  testWidgets(
    'quote shows distance source, frozen state and expected amount before acceptance',
    (tester) async {
      final service = RiderEarningsService(
        identity: () => 'a',
        read: (_, __) async => quote(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RiderEarningsPanel(service: service, orderId: 42),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PKR 124'), findsOneWidget);
      expect(find.textContaining('Straight-line estimate'), findsOneWidget);
      expect(
        find.textContaining('frozen when delivery starts'),
        findsOneWidget,
      );
    },
  );
  testWidgets('account change immediately clears rendered ledger', (
    tester,
  ) async {
    String? account = 'a';
    final changes = StreamController<void>.broadcast(sync: true);
    final service = RiderEarningsService(
      identity: () => account,
      accountChanges: changes.stream,
      read: (_, __) async => history(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RiderEarningsPanel(service: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Total: PKR 248'), findsOneWidget);
    account = null;
    changes.add(null);
    await tester.pump();
    expect(find.text('Total: PKR 248'), findsNothing);
    expect(find.textContaining('Account changed.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await changes.close();
  });
}
