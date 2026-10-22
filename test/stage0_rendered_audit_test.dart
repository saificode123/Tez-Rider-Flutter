import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/screens/customer/about_tezrider_screen.dart';
import 'package:flutter_application_1/screens/customer/payment_methods_screen.dart';
import 'package:flutter_application_1/screens/login_screen.dart';
import 'package:flutter_application_1/screens/signup_screen.dart';
import 'package:flutter_application_1/widgets/role_access_gate.dart';

class _Pkce extends GotrueAsyncStorage {
  const _Pkce();
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {}
}

class _LocalAuth extends AuthController {
  @override
  // This rendering double intentionally excludes AuthController sensor wiring.
  // ignore: must_call_super
  void onInit() {} // No native sensor/session wiring in this rendering test.
  @override
  void onClose() {}
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'widget-test-public-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        pkceAsyncStorage: _Pkce(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets(
    'About renders unsupported claims as an identified Stage4 audit finding',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: AboutTezRiderScreen()));
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('4.8'), findsOneWidget);
      expect(find.text('500+'), findsOneWidget);
      // Their presence is the finding; it is not evidence these claims are true.
    },
  );

  testWidgets(
    'Payment methods empty state and unavailable add never save an instrument',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: PaymentMethodsScreen()));
      expect(
        find.text('No online payment method is configured.'),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credit / Debit Card'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No payment method was saved.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('Login required-field error is rendered before authentication', (
    tester,
  ) async {
    Get.put<AuthController>(_LocalAuth());
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GetMaterialApp(home: LoginScreen()));
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Sign in as Customer'));
    await tester.tap(find.text('Sign in as Customer'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Please fill in all fields'), findsOneWidget);
    expect(Supabase.instance.client.auth.currentSession, isNull);
    Get.closeAllSnackbars();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Signup required-field error is rendered without creating an account',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const GetMaterialApp(home: SignupScreen()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create Account').last);
      await tester.tap(find.text('Create Account').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Please fill all required fields'), findsOneWidget);
      expect(Supabase.instance.client.auth.currentSession, isNull);
      Get.closeAllSnackbars();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Unauthenticated dashboard gate denies and Retry cannot render dashboard',
    (tester) async {
      await tester.pumpWidget(
        GetMaterialApp(
          home: RoleAccessGate(
            role: 'admin',
            builder: (_) => const Text('PRIVATE DASHBOARD'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE DASHBOARD'), findsNothing);
      expect(
        find.text('Account access could not be confirmed for this screen.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE DASHBOARD'), findsNothing);
      expect(find.text('Return to sign in'), findsOneWidget);
    },
  );
}
