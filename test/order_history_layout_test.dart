import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/screens/customer/order_history_screen.dart';
import 'support/closure_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets(
    'narrow order cards retain readable details and payment actions open confirmed state',
    (t) async {
      await t.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final now = DateTime.now().toUtc().toIso8601String();
      transport.respond = (r) async {
        if (r.url.path.endsWith('/fr25_order_history')) {
          return UiTransport.jsonResponse([
            {
              'id': 2610,
              'amount': 130,
              'created_at': now,
              'delivered_at': now,
              'order_status': 'delivered',
              'rider_id': 20,
            },
          ]);
        }
        if (r.url.path.endsWith('/final2_order_payment')) {
          return UiTransport.jsonResponse({
            'code': 'OK',
            'order_id': 2610,
            'order_status': 'delivered',
            'method': 'COD',
            'state': 'CASH_RECORDED',
            'amount': 130,
            'refunded_amount': 0,
            'refunds': [],
            'events': [
              {
                'id': 1,
                'event_kind': 'COLLECTED',
                'actor_role': 'rider',
                'amount': 130,
                'reference': null,
                'created_at': now,
              },
            ],
          });
        }
        return UiTransport.jsonResponse([]);
      };
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode(unitSession().toJson()),
      );
      await t.pumpWidget(const MaterialApp(home: OrderHistoryScreen()));
      await t.pumpAndSettle();
      final title = find.text('Order #2610');
      final details = find
          .ancestor(of: title, matching: find.byType(Column))
          .first;
      expect(t.getSize(details).width, greaterThan(180));
      expect(
        t.getRect(find.text('Payment / refunds')).top,
        greaterThan(t.getRect(title).bottom),
      );
      await t.ensureVisible(find.text('Payment / refunds'));
      await t.tap(find.text('Payment / refunds'));
      await t.pumpAndSettle();
      expect(find.text('COD · Cash collection recorded'), findsOneWidget);
      expect(find.text('Order amount: PKR 130.00'), findsOneWidget);
      expect(find.text('Record cash already received'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
