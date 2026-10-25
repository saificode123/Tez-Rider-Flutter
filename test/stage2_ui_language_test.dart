import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'package:flutter_application_1/core/stage2_ui_translations.dart';
import 'package:flutter_application_1/services/cash_ledger_service.dart';
import 'package:flutter_application_1/widgets/order_payment_panel.dart';
import 'package:flutter_application_1/widgets/order_timeline.dart';
import 'package:flutter_application_1/widgets/rider_identity_card.dart';
import 'package:flutter_application_1/widgets/stock_indicator.dart';
import 'package:flutter_application_1/controllers/tez_order_controller.dart';

Widget app(Widget child) => GetMaterialApp(
  locale: const Locale('en', 'US'),
  fallbackLocale: const Locale('en', 'US'),
  translations: AppTranslations(),
  supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  tearDown(Get.reset);
  test('every display template retains all dynamic tokens', () {
    final token = RegExp(r'@slot\d+end');
    for (final entry in stage2UiUrdu.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      expect(
        token.allMatches(entry.value).map((v) => v[0]).toList()..sort(),
        token.allMatches(entry.key).map((v) => v[0]).toList()..sort(),
        reason: entry.key,
      );
    }
  });
  testWidgets('stock labels translate while the confirmed count stays exact', (
    t,
  ) async {
    await t.pumpWidget(
      app(
        const StockIndicator(
          product: {
            'stock_qty': 12,
            'stock_confirmed': true,
            'is_available': true,
            'low_stock_threshold': 5,
          },
          vendor: true,
        ),
      ),
    );
    expect(find.text('In stock · 12 units · Low stock at 5'), findsOneWidget);
    final changed = Get.updateLocale(const Locale('ur', 'PK'));
    await t.pump();
    await changed;
    await t.pumpAndSettle();
    expect(
      find.text('ذخیرہ موجود ہے · 12 عدد · 5 پر ذخیرہ کم سمجھا جائے گا'),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('unconfigured booking reports no assigned Rider in Urdu', (
    t,
  ) async {
    await t.pumpWidget(app(const SizedBox()));
    final changed = Get.updateLocale(const Locale('ur', 'PK'));
    await t.pump();
    await changed;
    await t.pumpAndSettle();
    final flow = TezOrderController();
    await flow.placeOrder(lat: 1, lng: 2, fare: 3);
    await t.pump();
    expect(flow.isSearching.value, false);
    expect(flow.status.value, 'Instant rider booking is unavailable.');
    expect(
      find.text(
        stage2UiUrdu['Please use product checkout. No rider has been assigned.']!,
      ),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
  });
  test('English interpolation keeps user strings and unknown keys exact', () {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    expect(
      'Vendor: @slot0end (#@slot1end)'.uiTr({
        'slot0end': r'@slot1end $name <b>Store</b>',
        'slot1end': '12',
      }),
      r'Vendor: @slot1end $name <b>Store</b> (#12)',
    );
    expect('Unknown message'.uiTr({}), 'Unknown message');
  });
  test('Urdu substitution never expands a token supplied inside user data', () {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('ur', 'PK');
    expect(
      'Vendor: @slot0end (#@slot1end)'.uiTr({
        'slot0end': '@slot1end',
        'slot1end': '12',
      }),
      'وینڈر: @slot1end (#12)',
    );
    expect('Reference: @slot0end'.uiTr({}), 'حوالہ: @slot0end');
  });
  testWidgets(
    'retained timeline translates its constant labels on an open route',
    (t) async {
      await t.pumpWidget(app(const OrderTimeline(currentStep: 4)));
      expect(find.text('Delivered'), findsOneWidget);
      final changed = Get.updateLocale(const Locale('ur', 'PK'));
      await t.pump();
      await changed;
      await t.pump();
      expect(find.text(stage2UiUrdu['Delivered']!), findsOneWidget);
      expect(find.text('Delivered'), findsNothing);
      expect(
        Directionality.of(t.element(find.text(stage2UiUrdu['Delivered']!))),
        TextDirection.rtl,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Rider state translates without translating a stored name or changing milestones',
    (t) async {
      await t.pumpWidget(
        app(
          RiderIdentityCard(
            orderId: 7,
            identity: () => 'customer',
            read: (_) async => {
              'code': 'OK',
              'order_id': 7,
              'order_status': 'delivered',
              'rider': {
                'name': 'Ready',
                'photo': null,
                'rating': null,
                'rating_count': 0,
                'cnic_masked': null,
              },
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      final changed = Get.updateLocale(const Locale('ur', 'PK'));
      await t.pump();
      await changed;
      await t.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget); // The actual account name.
      expect(find.text('تیار'), findsOneWidget); // Display-only milestone.
      expect(find.text('CNIC unavailable in this record.'), findsNothing);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'payment retry uses original order after locale change and shows no false cash success',
    (t) async {
      final calls = <int>[];
      final pending = Completer<dynamic>();
      final service = CashLedgerService(
        reader: (id) async {
          calls.add(id);
          if (calls.length == 1) throw TimeoutException('controlled fault');
          return pending.future;
        },
        writer: (_) async => throw StateError('No mutation authorized'),
      );
      await t.pumpWidget(app(OrderPaymentPanel(orderId: 7, service: service)));
      await t.pumpAndSettle();
      final changed = Get.updateLocale(const Locale('ur', 'PK'));
      await t.pump();
      await changed;
      await t.pumpAndSettle();
      expect(
        find.text(
          stage2UiUrdu['Payment status could not be verified. Retry or ask an administrator.']!,
        ),
        findsOneWidget,
      );
      await t.tap(find.text(stage2UiUrdu['Retry payment status']!));
      await t.pump();
      expect(calls, [7, 7]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete({
        'code': 'OK',
        'order_id': 7,
        'order_status': 'delivered',
        'method': 'cod',
        'state': 'UNPAID',
        'amount': 12.5,
        'refunded_amount': 0,
        'refunds': [],
        'events': [],
      });
      await t.pumpAndSettle();
      expect(
        find.text('cod · ${stage2UiUrdu['No cash collection is recorded']}'),
        findsOneWidget,
      );
      expect(find.textContaining('12.50'), findsOneWidget);
      expect(find.text('Cash collection recorded'), findsNothing);
      expect(calls, [7, 7]);
      await t.pumpWidget(const SizedBox());
    },
  );
}
