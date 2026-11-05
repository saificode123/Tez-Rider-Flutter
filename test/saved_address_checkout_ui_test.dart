// Offline UI regressions: no GPS, maps, tile requests or hosted backend calls.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/cart_controller.dart';
import 'package:flutter_application_1/controllers/product_controller.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/screens/customer/enhanced_checkout_screen.dart';
import 'package:flutter_application_1/services/saved_addresses_service.dart';

import 'support/closure_harness.dart';

class _Products extends ProductController {
  @override
  // ignore: must_call_super
  void onInit() {
    isLoading.value = false;
  }

  @override
  void onReady() {}
}

Map<String, dynamic> _row(int id, String label, {bool pin = false}) => {
  'id': id,
  'label': label,
  'address': 'Written house and street for $label',
  'revision': 0,
  if (pin) ...{
    'latitude': 33.5,
    'longitude': 73.5,
    'location_confirmed_at': '2026-11-05T10:00:00Z',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeClosureClient(transport);
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    Get.testMode = true;
    VaultDouble().install();
    transport.requests.clear();
    transport.respond = (_) async => UiTransport.jsonResponse([]);
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession().toJson()),
    );
    Get.put<ProductController>(_Products());
  });
  tearDown(Get.reset);

  Finder addressField() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'House, street, area and city',
  );

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = SavedAddressesService(
      identity: () => unitSession().user.id,
      rpc: (name, params) async {
        expect(name, 'final2_saved_addresses');
        return {
          'items': [
            _row(20, 'Confirmed home', pin: true),
            _row(10, 'Text only'),
          ],
          'has_more': false,
          'cursor': 10,
        };
      },
    );
    final cart = Get.put(CartController(inventoryReader: (_) async => []));
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('en', 'US'),
        home: EnhancedCheckoutScreen(
          cart: cart,
          customerId: unitSession().user.id,
          savedAddressesService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String label) async {
    final button = find.widgetWithText(OutlinedButton, 'Use saved address');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'saved confirmed pin requires fresh explicit checkout confirmation',
    (tester) async {
      await open(tester);
      await select(tester, 'Confirmed home');
      expect(find.text('Confirm delivery destination'), findsOneWidget);
      expect(find.text('Delivery pin confirmed'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delivery pin confirmed'), findsNothing);
      expect(
        find.text('Choose and confirm a delivery pin before checkout.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(addressField()).controller!.text,
        'Written house and street for Confirmed home',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved written address survives explicit pin confirmation', (
    tester,
  ) async {
    await open(tester);
    await select(tester, 'Confirmed home');
    final written = tester.widget<TextField>(addressField()).controller!.text;
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm destination'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery pin confirmed'), findsOneWidget);
    expect(tester.widget<TextField>(addressField()).controller!.text, written);
    expect(written, 'Written house and street for Confirmed home');
    expect(
      transport.requests.any(
        (request) => request.url.path.endsWith('/fr10_checkout'),
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'text-only saved address clears a previously confirmed destination',
    (tester) async {
      await open(tester);
      await select(tester, 'Confirmed home');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirm destination'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delivery pin confirmed'), findsOneWidget);
      await select(tester, 'Text only');
      expect(find.text('Confirm delivery destination'), findsNothing);
      expect(find.text('Delivery pin confirmed'), findsNothing);
      expect(
        find.text('Choose and confirm a delivery pin before checkout.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(addressField()).controller!.text,
        'Written house and street for Text only',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
