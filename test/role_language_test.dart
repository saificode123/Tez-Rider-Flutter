import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/language_controller.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/controllers/vendor_controller.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/screens/vendor_dashboard.dart';
import 'support/closure_harness.dart';
import 'vendor_dashboard_stats_test.dart' show QuietVendor;

class RolePreference implements LanguagePreferenceStore {
  String value = 'en';
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  tearDown(Get.reset);
  testWidgets(
    'actual Vendor route rebuilds translated labels and keeps profile selected after Urdu menu selection',
    (t) async {
      await t.binding.setSurfaceSize(const Size(420, 920));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode(unitSession().toJson()),
      );
      transport.respond = (r) async => UiTransport.jsonResponse(
        r.url.path.endsWith('/rpc/final2_store_settings')
            ? {
                'store_id': 10,
                'store_name': 'Unit store',
                'address': 'Unit address',
                'latitude': null,
                'longitude': null,
                'is_active': true,
                'version': 0,
              }
            : r.url.path.endsWith('/users')
            ? [
                {'id': 10},
              ]
            : r.url.path.endsWith('/vendors')
            ? [
                {'store_name': 'Unit store'},
              ]
            : [],
      );
      Get.put<AuthController>(QuietAuth());
      Get.put<VendorController>(QuietVendor());
      final store = RolePreference();
      final language = Get.put(
        LanguageController(store: store, appReady: () => false),
      );
      await language.restore();
      await t.pumpWidget(
        GetMaterialApp(
          locale: language.locale,
          translations: AppTranslations(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
          home: const VendorDashboard(),
        ),
      );
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.person_outline_rounded));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Language / زبان'));
      await t.tap(find.text('Language / زبان'));
      await t.pumpAndSettle();
      await t.tap(find.text('اردو').last);
      await t.pumpAndSettle();
      expect(store.value, 'ur');
      expect(find.text('پروفائل'), findsOneWidget);
      expect(find.text('Profile'), findsNothing);
      expect(find.text('Unit store'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
