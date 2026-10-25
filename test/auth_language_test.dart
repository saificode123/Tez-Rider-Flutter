import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/screens/login_screen.dart';
import 'package:flutter_application_1/screens/signup_screen.dart';
import 'support/closure_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    Get.testMode = true;
    Get.put<AuthController>(QuietAuth());
    transport.requests.clear();
  });
  tearDown(Get.reset);
  Future<void> open(WidgetTester t, Widget screen) async {
    await t.binding.setSurfaceSize(const Size(450, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      GetMaterialApp(
        locale: const Locale('ur', 'PK'),
        translations: AppTranslations(),
        supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: screen,
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  }

  testWidgets(
    'Urdu login role selection retains the exact backend role and validates before requests',
    (t) async {
      await open(t, const LoginScreen());
      await t.tap(find.byType(DropdownButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('وینڈر').last);
      await t.pumpAndSettle();
      expect(
        t
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        'vendor',
      );
      final submit = find.text('وینڈر کے طور پر سائن ان کریں');
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('تمام خانے پُر کریں'), findsOneWidget);
      expect(transport.requests, isEmpty);
      await close(t);
    },
  );
  testWidgets(
    'unknown login provider error exposes only the localized retry message',
    (t) async {
      transport.respond = (_) async => UiTransport.jsonResponse({
        'code': 'unexpected_provider_failure',
        'msg': 'provider-internal-private-value',
      }, 400);
      await open(t, const LoginScreen());
      await t.enterText(find.byType(TextField).at(0), 'unit@example.test');
      await t.enterText(find.byType(TextField).at(1), 'unit-password');
      final submit = find.text('گاہک کے طور پر سائن ان کریں');
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(
        find.text('سائن ان کی تصدیق نہیں ہوئی۔ دوبارہ کوشش کریں۔'),
        findsOneWidget,
      );
      expect(
        find.textContaining('provider-internal-private-value'),
        findsNothing,
      );
      expect(
        transport.requests.where((r) => r.url.path.endsWith('/token')).length,
        1,
      );
      expect(find.byType(LoginScreen), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'Urdu Vendor registration preserves role ID, field values and validation',
    (t) async {
      await open(t, const SignupScreen(initialRole: 'vendor'));
      expect(find.text('دکان کا نام'), findsOneWidget);
      expect(find.text('دکان کا پتہ'), findsOneWidget);
      expect(
        t.widget<SignupScreen>(find.byType(SignupScreen)).initialRole,
        'vendor',
      );
      final submit = find.widgetWithText(ElevatedButton, 'اکاؤنٹ بنائیں');
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('تمام لازمی خانے پُر کریں'), findsOneWidget);
      expect(transport.requests, isEmpty);
      expect(find.byType(SignupScreen), findsOneWidget);
      await close(t);
    },
  );
}
