import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/controllers/language_controller.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/screens/login_screen.dart';
import 'package:flutter_application_1/screens/signup_screen.dart';
import 'package:flutter_application_1/theme/app_motion.dart';
import 'package:flutter_application_1/widgets/app_language_selector.dart';
import 'package:flutter_application_1/widgets/app_stat_card.dart';
import 'package:flutter_application_1/widgets/password_reset_dialog.dart';
import 'package:flutter_application_1/screens/customer/payment_methods_screen.dart';
import 'package:flutter_application_1/screens/admin_dashboard.dart';
import 'package:flutter_application_1/controllers/admin_controller.dart';
import 'package:flutter_application_1/widgets/order_timeline.dart';
import 'support/closure_harness.dart';

class _Preference implements LanguagePreferenceStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String language) async {
    value = language;
  }
}

class _QuietAdmin extends AdminController {
  @override
  // The test supplies rendering state, without opening hosted subscriptions.
  // ignore: must_call_super
  void onInit() {
    isLoading.value = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  late _Preference store;
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    Get.testMode = true;
    Get.put<AuthController>(QuietAuth());
    store = _Preference();
    transport.requests.clear();
  });
  tearDown(Get.reset);

  Future<void> open(
    WidgetTester t, {
    Size size = const Size(390, 844),
    double scale = 1,
    bool reduced = false,
    Widget? child,
  }) async {
    final language = Get.put(LanguageController(store: store), permanent: true);
    await language.restore();
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      GetMaterialApp(
        locale: const Locale('en', 'US'),
        translations: AppTranslations(),
        supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: child ?? const LoginScreen(),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('login changes locale before authentication and persists it', (
    t,
  ) async {
    await open(t);
    await t.enterText(find.byType(TextField).first, 'unit@example.test');
    await t.ensureVisible(find.byType(AppLanguageSelector));
    await t.pumpAndSettle();
    expect(
      t
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      {'en'},
    );
    await t.tap(
      find.descendant(
        of: find.byType(AppLanguageSelector),
        matching: find.text('اردو'),
      ),
    );
    await t.pumpAndSettle();
    expect(store.value, 'ur');
    expect(
      Directionality.of(t.element(find.byType(LoginScreen))),
      TextDirection.rtl,
    );
    expect(
      t.widget<TextField>(find.byType(TextField).first).decoration!.labelText,
      'Email Address'.tr,
    );
    expect('Email Address'.tr, isNot('Email Address'));
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      'unit@example.test',
    );
    expect(transport.requests, isEmpty);
    final restarted = LanguageController(store: store, appReady: () => false);
    await restarted.restore();
    expect(restarted.locale.languageCode, 'ur');
    await t.tap(find.text('English'));
    await t.pumpAndSettle();
    expect(store.value, 'en');
    expect(
      Directionality.of(t.element(find.byType(LoginScreen))),
      TextDirection.ltr,
    );
  });

  testWidgets('language carries into signup and password reset', (t) async {
    await open(t);
    await t.tap(find.text('اردو'));
    await t.pumpAndSettle();
    final signup = find.widgetWithText(OutlinedButton, 'اکاؤنٹ بنائیں');
    await t.ensureVisible(signup);
    await t.tap(signup);
    await t.pumpAndSettle();
    expect(find.byType(SignupScreen), findsOneWidget);
    expect(
      Directionality.of(t.element(find.byType(SignupScreen))),
      TextDirection.rtl,
    );
    Get.back();
    await t.pumpAndSettle();
    final forgot = find.text('Forgot password?'.tr);
    await t.ensureVisible(forgot);
    await t.tap(forgot);
    await t.pumpAndSettle();
    expect(find.text('Reset Password'.tr), findsOneWidget);
    await t.tap(find.text('Send Link'.tr));
    await t.pumpAndSettle();
    expect(find.text('Enter a valid email address'.tr), findsOneWidget);
    expect(transport.requests, isEmpty);
    await t.tap(find.text('Cancel'.tr));
    await t.pumpAndSettle();
  });

  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('login fits $size at 200% text and reduced motion', (t) async {
      await open(t, size: size, scale: 2, reduced: true);
      expect(t.takeException(), isNull);
      await t.tap(find.text('اردو'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final submit = find.byType(ElevatedButton).first;
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Please fill in all fields'.tr), findsOneWidget);
      expect(transport.requests, isEmpty);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
    });
  }

  testWidgets('password toggle is labelled and preserves typed password', (
    t,
  ) async {
    await open(t);
    await t.enterText(find.byType(TextField).last, 'typed-password');
    final toggle = find.byTooltip('Show password');
    await t.ensureVisible(toggle);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byType(TextField).last).obscureText, false);
    expect(find.byTooltip('Hide password'), findsOneWidget);
    expect(
      t.widget<TextField>(find.byType(TextField).last).controller!.text,
      'typed-password',
    );
  });

  testWidgets(
    'reset retains failure and prevents duplicate requests while busy',
    (t) async {
      final pending = Completer<void>();
      transport.respond = (_) async {
        await pending.future;
        return UiTransport.jsonResponse({'msg': 'private-provider-error'}, 400);
      };
      await open(
        t,
        child: const Scaffold(
          body: PasswordResetDialog(email: 'unit@example.test'),
        ),
      );
      await t.tap(find.text('Send Link'));
      await t.pump();
      await t.tap(find.byType(ElevatedButton));
      await t.pump();
      expect(transport.requests.length, 1);
      expect(
        t.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      pending.complete();
      await t.pumpAndSettle();
      expect(
        find.text('Could not send reset email. Check the address.'),
        findsOneWidget,
      );
      expect(find.textContaining('private-provider-error'), findsNothing);
      expect(find.byType(PasswordResetDialog), findsOneWidget);
    },
  );

  testWidgets('shared metric card wraps at 200% text', (t) async {
    await open(
      t,
      size: const Size(320, 568),
      scale: 2,
      child: const Scaffold(
        body: SizedBox(
          width: 150,
          child: AppStatCard(
            label: 'Delivered sales',
            value: 'PKR 123456',
            icon: Icons.receipt,
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('route motion follows OS preference', (t) async {
    await open(
      t,
      reduced: true,
      child: Builder(
        builder: (context) {
          expect(AppMotion.duration(context), Duration.zero);
          return const Scaffold();
        },
      ),
    );
  });
  testWidgets('payment choices explain unsupported providers in Urdu', (
    t,
  ) async {
    await open(t, child: const PaymentMethodsScreen());
    await LanguageController.to.setUrdu();
    await t.pumpAndSettle();
    expect(find.text('Cash on Delivery'.tr), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(4));
    for (final tile in t.widgetList<ListTile>(find.byType(ListTile))) {
      expect(tile.enabled, false);
      expect(tile.onTap, isNull);
    }
    expect(
      find.text('Unavailable: no payment provider is configured.'.tr),
      findsNWidgets(4),
    );
    expect(transport.requests, isEmpty);
  });

  testWidgets('admin menu exposes all existing operational destinations', (
    t,
  ) async {
    Get.put<AdminController>(_QuietAdmin());
    await open(t, size: const Size(450, 1000), child: const AdminDashboard());
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    for (final label in [
      'Orders and monitoring',
      'Broadcast notifications',
      'Manage Users',
    ]) {
      final menu = find.widgetWithText(MenuItemButton, label);
      expect(menu, findsOneWidget);
      expect(t.widget<MenuItemButton>(menu).onPressed, isNotNull);
    }
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    expect(find.text('Orders and monitoring'), findsNothing);
  });

  testWidgets('timeline has no continuous ticker with reduced motion', (
    t,
  ) async {
    await open(
      t,
      reduced: true,
      child: const Scaffold(body: OrderTimeline(currentStep: 2)),
    );
    await t.pumpAndSettle();
    expect(t.binding.transientCallbackCount, 0);
  });
}
