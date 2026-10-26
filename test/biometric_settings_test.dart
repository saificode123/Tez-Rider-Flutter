import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/widgets/biometric_settings_tile.dart';

class SettingsAuth extends AuthController {
  int changes = 0;
  bool fail = false;
  bool cancel = false;
  @override
  // Native/account setup is excluded only from this UI harness.
  // ignore: must_call_super
  void onInit() {}
  @override
  // ignore: must_call_super
  void onClose() {}
  @override
  Future<void> setBioPreference(bool enabled) async {
    changes++;
    if (fail) throw StateError('injected storage failure');
    if (!cancel) isBioEnabled.value = enabled;
  }
}

void main() {
  late SettingsAuth auth;
  setUp(() {
    Get.testMode = true;
    auth = SettingsAuth()..isBioSupported.value = true;
    Get.put<AuthController>(auth);
  });
  tearDown(Get.reset);

  Future<void> show(WidgetTester tester, {bool urdu = false}) async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: Locale(urdu ? 'ur' : 'en', urdu ? 'PK' : 'US'),
        home: const Scaffold(
          body: SingleChildScrollView(child: BiometricSettingsTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opt-in and opt-out reflect confirmed preference', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(auth.isBioEnabled.value, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(auth.isBioEnabled.value, isFalse);
    expect(auth.changes, 2);
  });
  testWidgets('canceled native verification leaves enrollment disabled', (
    tester,
  ) async {
    auth.cancel = true;
    await show(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(auth.isBioEnabled.value, isFalse);
    expect(
      find.text(
        'Biometric verification was not completed. Retry or use your password.',
      ),
      findsOneWidget,
    );
  });
  testWidgets(
    'secure storage failure displays retry without false enrollment',
    (tester) async {
      auth.fail = true;
      await show(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(auth.isBioEnabled.value, isFalse);
      expect(
        find.text('Biometric preference could not be saved. Retry.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'unsupported sensor is disabled and Urdu text scales without overflow',
    (tester) async {
      auth.isBioSupported.value = false;
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await show(tester, urdu: true);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(find.text('بایومیٹرک سائن اِن'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
