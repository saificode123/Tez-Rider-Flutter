import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/screens/splash_screen.dart';

class _TestPkceStorage extends GotrueAsyncStorage {
  const _TestPkceStorage();

  @override
  Future<String?> getItem({required String key}) async => null;

  @override
  Future<void> setItem({required String key, required String value}) async {}

  @override
  Future<void> removeItem({required String key}) async {}
}

void main() {
  setUpAll(() async {
    // No session and no network request: exercise the unauthenticated startup.
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'widget-test-public-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        pkceAsyncStorage: _TestPkceStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  tearDown(Get.reset);

  testWidgets('Splash shows current branding and navigates to login', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: const SplashScreen(showCyclist: false),
        getPages: [
          GetPage(
            name: '/login',
            page: () => const Scaffold(body: Text('Login destination')),
          ),
        ],
      ),
    );
    expect(find.text('TEZRIDER'), findsOneWidget);
    expect(find.text('Delivering Excellence, Every Time'), findsOneWidget);
    expect(find.byIcon(Icons.delivery_dining_rounded), findsOneWidget);
    for (final delay in [200, 500, 500, 2000, 500]) {
      await tester.pump(Duration(milliseconds: delay));
    }
    expect(find.text('Login destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Splash cancels animation work when disposed early', (
    tester,
  ) async {
    await tester.pumpWidget(
      const GetMaterialApp(home: SplashScreen(showCyclist: false)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
