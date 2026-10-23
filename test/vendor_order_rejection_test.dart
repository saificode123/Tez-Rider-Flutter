import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/widgets/vendor_order_rejection.dart';

void main() {
  for (final confirm in [false, true]) {
    testWidgets(
      'vendor destructive rejection requires explicit confirmation: $confirm',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      confirmVendorOrderRejection(context, () async {
                        calls++;
                      }),
                  child: const Text('Reject'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Reject'));
        await tester.pumpAndSettle();
        expect(find.textContaining('entire customer order'), findsOneWidget);
        expect(calls, 0);
        await tester.tap(find.text(confirm ? 'Reject order' : 'Keep order'));
        await tester.pumpAndSettle();
        expect(calls, confirm ? 1 : 0);
      },
    );
  }
}
