import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/inventory_service.dart';
import 'package:flutter_application_1/widgets/stock_adjustment_dialog.dart';

Future<void> open(WidgetTester tester, InventoryWriter writer) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => StockAdjustmentDialog(
                product: {
                  'id': 1,
                  'name': 'Physical stock',
                  'stock_qty': 12,
                  'stock_confirmed': true,
                  'stock_version': 1,
                },
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

void main() {
  testWidgets(
    'successful save closes through animation without disposed controllers',
    (tester) async {
      Map<String, dynamic>? sent;
      await open(tester, (_, params) async {
        sent = params;
        return {'code': 'UPDATED'};
      });
      await tester.enterText(find.byType(TextField).first, '14');
      await tester.tap(find.text('Save stock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(sent?['p_quantity'], 14);
      expect(find.byType(StockAdjustmentDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cancel disposes text fields only when route is removed', (
    tester,
  ) async {
    await open(tester, (_, _) async => throw StateError('No save expected'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(StockAdjustmentDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'stale count stays open for explicit review and uses new version',
    (tester) async {
      var calls = 0;
      await open(tester, (_, params) async {
        if (++calls == 1)
          return {'code': 'STOCK_CHANGED', 'stock_qty': 10, 'stock_version': 2};
        expect(params['p_expected_version'], 2);
        expect(params['p_quantity'], 10);
        return {'code': 'UPDATED'};
      });
      await tester.tap(find.text('Save stock'));
      await tester.pumpAndSettle();
      expect(
        find.text('Stock changed. Review this count and save again.'),
        findsOneWidget,
      );
      expect(find.byType(StockAdjustmentDialog), findsOneWidget);
      await tester.tap(find.text('Save stock'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
