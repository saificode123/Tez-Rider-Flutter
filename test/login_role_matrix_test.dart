import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/screens/login_screen.dart';

import 'support/closure_harness.dart';

class MatrixAuth extends QuietAuth {
  bool biometric = false;
  @override
  Future<void> refreshBiometricState() async {
    isBioSupported.value = true;
    isBioEnabled.value = biometric;
  }

  @override
  Future<bool> authenticateWithBiometrics() async => biometric;
  @override
  Future<bool> enforceAccountAccess({bool passwordLogin = false}) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  final vault = VaultDouble();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    Get.testMode = true;
    vault.data.clear();
    vault.install();
    Get.put<AuthController>(MatrixAuth());
  });
  tearDown(() async {
    await Supabase.instance.client.auth.signOut();
    Get.reset();
  });
  const roles = ['customer', 'vendor', 'rider', 'admin'];
  for (final method in ['password', 'biometric']) {
    for (final selected in roles) {
      for (final actual in roles) {
        testWidgets('$method selected $selected with server $actual', (
          t,
        ) async {
          final auth = Get.find<AuthController>() as MatrixAuth;
          if (method == 'biometric') {
            auth.biometric = true;
            await auth.credentials.remember(unitSession(), actual);
            await auth.credentials.setBiometricEnabled(
              unitSession().user.id,
              true,
            );
          }
          transport.respond = (r) async {
            if (r.url.path.endsWith('/token')) {
              return UiTransport.jsonResponse(unitSession().toJson());
            }
            if (r.url.path.endsWith('/final2_complete_registration')) {
              return UiTransport.jsonResponse({
                'code': 'OK',
                'id': 1,
                'role': actual,
                'verification_status': 'approved',
                'store_id': 1,
              });
            }
            if (r.url.path.endsWith('/users')) {
              return UiTransport.jsonResponse({
                'id': 1,
                'role': actual,
                'verification_status': 'approved',
                'is_blocked': false,
              });
            }
            return UiTransport.jsonResponse({});
          };
          await t.binding.setSurfaceSize(const Size(450, 1100));
          addTearDown(() => t.binding.setSurfaceSize(null));
          await t.pumpWidget(
            GetMaterialApp(
              home: const LoginScreen(),
              getPages: [
                for (final role in roles)
                  GetPage(
                    name: '/${role}_home',
                    page: () => Scaffold(body: Text('protected-$role')),
                  ),
              ],
            ),
          );
          await t.pumpAndSettle();
          if (selected != 'customer') {
            await t.tap(find.byType(DropdownButton<String>));
            await t.pumpAndSettle();
            await t.tap(
              find.text(selected[0].toUpperCase() + selected.substring(1)).last,
            );
            await t.pumpAndSettle();
          }
          if (method == 'password') {
            await t.enterText(
              find.byType(TextField).at(0),
              'unit@example.test',
            );
            await t.enterText(find.byType(TextField).at(1), 'unit-password');
          }
          final button = find.text(
            method == 'biometric'
                ? 'Continue with Biometrics'
                : 'Sign in as ${selected[0].toUpperCase()}${selected.substring(1)}',
          );
          await t.ensureVisible(button);
          await t.tap(button);
          await t.pumpAndSettle();
          if (selected == actual) {
            expect(find.text('protected-$actual'), findsOneWidget);
            expect(vault.data['tr_role'], actual);
            expect(auth.localSessionEntered, isTrue);
            if (method == 'biometric') {
              expect(vault.data['bio_enabled'], 'true');
            }
          } else {
            expect(
              find.text('Sign in with the correct account role selected.'),
              findsOneWidget,
            );
            expect(Supabase.instance.client.auth.currentSession, isNull);
            expect(vault.data['tr_refresh'], isNull);
            for (final role in roles) {
              expect(find.text('protected-$role'), findsNothing);
            }
          }
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
        });
      }
    }
  }
}
