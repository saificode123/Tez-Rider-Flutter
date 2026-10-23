import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/cash_ledger_service.dart';
import 'package:flutter_application_1/widgets/order_payment_panel.dart';

Map<String, dynamic> snapshot({
  String state = 'UNPAID',
  List<Map<String, dynamic>> refunds = const [],
}) => {
  'code': 'OK',
  'order_id': 1,
  'order_status': 'delivered',
  'method': 'COD',
  'state': state,
  'amount': 25.75,
  'refunded_amount': 0,
  'refunds': refunds,
  'events': [],
};
Map<String, dynamic> parameters() => {
  'p_order_id': 1,
  'p_event_kind': 'COLLECTED',
  'p_amount': 25.75,
  'p_confirmed': true,
  'p_reference': 'FINAL2-RECEIPT',
  'p_refund_kind': null,
  'p_refund_id': null,
};
Map<String, dynamic> recorded() => {
  'code': 'RECORDED',
  'event_id': 1,
  'event_kind': 'COLLECTED',
  'amount': 25.75,
};
void main() {
  test(
    'snapshot keeps pending collection and refund distinct from confirmed money',
    () {
      final value = PaymentSnapshot.parse(
        snapshot(
          refunds: [
            {'id': 1, 'kind': 'DISPUTE', 'state': 'PENDING', 'amount': 25.75},
          ],
        ),
      );
      expect(value.state, 'UNPAID');
      expect(value.refunded, 0);
      expect(value.refunds.single['state'], 'PENDING');
    },
  );
  test(
    'wrong identity and malformed status never become confirmed payment',
    () async {
      await expectLater(
        CashLedgerService(reader: (_) async => snapshot()).load(2),
        throwsFormatException,
      );
      for (final invalid in [
        null,
        {},
        {...snapshot(), 'state': 'SUCCESS'},
        {...snapshot(), 'code': 'REVIEW_REQUIRED'},
      ]) {
        expect(() => PaymentSnapshot.parse(invalid), throwsFormatException);
      }
    },
  );
  test(
    'receipt timeout retries same UUID/payload; changing an uncertain acknowledgement is refused',
    () async {
      final requests = <Map<String, dynamic>>[];
      final flow = CashWriteFlow((p) async {
        requests.add(p);
        if (requests.length == 1) throw TimeoutException('unit network');
        return recorded();
      });
      await expectLater(
        flow.record(parameters()),
        throwsA(isA<TimeoutException>()),
      );
      expect(flow.uncertain, true);
      await expectLater(
        flow.record({...parameters(), 'p_reference': 'CHANGED-RECEIPT'}),
        throwsStateError,
      );
      expect(requests.length, 1);
      expect((await flow.record(parameters()))['code'], 'RECORDED');
      expect(requests[0], requests[1]);
      expect(flow.uncertain, false);
    },
  );
  test(
    'definitive server validation allows corrected values without simulated success',
    () async {
      var calls = 0;
      final flow = CashWriteFlow((_) async {
        if (++calls == 1) {
          throw const PostgrestException(
            message: 'Unit validation',
            code: '22023',
          );
        }
        return recorded();
      });
      await expectLater(
        flow.record(parameters()),
        throwsA(isA<PostgrestException>()),
      );
      expect(flow.uncertain, false);
      await flow.record({...parameters(), 'p_reference': 'CORRECTED-RECEIPT'});
      expect(calls, 2);
    },
  );
  for (final invalid in [
    null,
    {},
    {...recorded(), 'amount': 1},
    {...recorded(), 'event_id': null},
    {...recorded(), 'event_kind': 'REFUND_CONFIRMED'},
  ]) {
    test(
      'malformed acknowledgement cannot produce financial success: $invalid',
      () async {
        final flow = CashWriteFlow((_) async => invalid);
        await expectLater(flow.record(parameters()), throwsFormatException);
        expect(flow.uncertain, true);
      },
    );
  }
  test(
    'missing acknowledgement, bad cents and malformed refund fail before network',
    () async {
      var calls = 0;
      final flow = CashWriteFlow((_) async {
        calls++;
        return recorded();
      });
      for (final invalid in [
        {...parameters(), 'p_confirmed': false},
        {...parameters(), 'p_amount': 25.751},
        {...parameters(), 'p_reference': 'bad\nreference'},
        {...parameters(), 'p_event_kind': 'REFUND_CONFIRMED'},
      ]) {
        await expectLater(flow.record(invalid), throwsFormatException);
      }
      expect(calls, 0);
    },
  );
  test('concurrent record attempts cannot send a second mutation', () async {
    final pending = Completer<dynamic>();
    var calls = 0;
    final flow = CashWriteFlow((_) {
      calls++;
      return pending.future;
    });
    final first = flow.record(parameters());
    await expectLater(flow.record(parameters()), throwsStateError);
    expect(calls, 1);
    pending.complete(recorded());
    await first;
  });
  testWidgets(
    'customer read model has no cash mutation controls and pending is truthful',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderPaymentPanel(
              orderId: 1,
              service: CashLedgerService(
                reader: (_) async => snapshot(
                  refunds: [
                    {
                      'id': 1,
                      'kind': 'DISPUTE',
                      'state': 'PENDING',
                      'amount': 25.75,
                    },
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Record cash already received'), findsNothing);
      expect(find.text('Record cash already returned'), findsNothing);
      expect(
        find.text('Refund pending; money return is not confirmed'),
        findsOneWidget,
      );
    },
  );
  testWidgets('payment failure Retry loads the actual service response', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderPaymentPanel(
            orderId: 1,
            service: CashLedgerService(
              reader: (_) async {
                if (++calls == 1) throw StateError('offline');
                return snapshot();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Payment status could not be verified'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry payment status'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.textContaining('No cash collection is recorded'),
      findsOneWidget,
    );
  });
  Future<void> open(WidgetTester tester, CashWriter writer) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => CashAcknowledgementDialog(
                  orderId: 1,
                  kind: 'COLLECTED',
                  amount: 25.75,
                  writer: writer,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'cash dialog Cancel never writes; explicit acknowledgement is required',
    (tester) async {
      var calls = 0;
      await open(tester, (_) async {
        calls++;
        return recorded();
      });
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'FINAL2-RECEIPT');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    },
  );
  testWidgets(
    'uncertain acknowledgement locks evidence and Retry sends the identical record',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      await open(tester, (p) async {
        requests.add(p);
        if (requests.length == 1) throw TimeoutException('unit');
        return recorded();
      });
      await tester.enterText(find.byType(TextField), 'FINAL2-RECEIPT');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Record acknowledgement'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Do not repeat the cash transfer'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      await tester.tap(find.text('Retry unchanged record'));
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(requests[0], requests[1]);
      expect(find.byType(CashAcknowledgementDialog), findsNothing);
    },
  );
}
