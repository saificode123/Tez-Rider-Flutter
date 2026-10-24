import 'dart:convert';
import 'dart:async';
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
  setUp(() async {
    transport.requests.clear();
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession().toJson()),
    );
  });
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
  Map<String, dynamic> order(int id) => {
    'id': id,
    'amount': 1,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'order_status': 'pending',
    'rider_id': null,
  };
  testWidgets(
    'old account history response cannot replace the newly signed-in Customer list',
    (t) async {
      final pending = Completer<dynamic>();
      var calls = 0;
      transport.respond = (r) async {
        if (r.url.path.endsWith('/fr25_order_history')) {
          if (++calls == 1) return await pending.future;
          return UiTransport.jsonResponse([order(50000)]);
        }
        return UiTransport.jsonResponse([]);
      };
      await t.pumpWidget(const MaterialApp(home: OrderHistoryScreen()));
      await t.pump();
      expect(calls, 1);
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode(
          unitSession('00000000-0000-0000-0000-000000000002').toJson(),
        ),
      );
      await t.pumpAndSettle();
      pending.complete(UiTransport.jsonResponse([order(90)]));
      await t.pumpAndSettle();
      expect(find.text('Order #50000'), findsOneWidget);
      expect(find.text('Order #90'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'Load more uses the retained cursor and discards an in-flight older account page',
    (t) async {
      final pending = Completer<dynamic>();
      var calls = 0;
      dynamic cursor;
      transport.respond = (r) async {
        if (r.url.path.endsWith('/fr25_order_history')) {
          calls++;
          if (calls == 1) {
            return UiTransport.jsonResponse([
              for (var id = 90; id >= 61; id--) order(id),
            ]);
          }
          if (calls == 2) {
            cursor = jsonDecode(r.body)['p_before'];
            return await pending.future;
          }
          return UiTransport.jsonResponse([order(50000)]);
        }
        return UiTransport.jsonResponse([]);
      };
      await t.pumpWidget(const MaterialApp(home: OrderHistoryScreen()));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Load more orders'),
        600,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 50,
      );
      await t.tap(find.text('Load more orders'));
      await t.pump();
      expect(cursor, 61);
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode(
          unitSession('00000000-0000-0000-0000-000000000002').toJson(),
        ),
      );
      await t.pumpAndSettle();
      pending.complete(UiTransport.jsonResponse([order(60)]));
      await t.pumpAndSettle();
      expect(find.text('Order #50000'), findsOneWidget);
      expect(find.text('Order #60'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
