import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'controllers/auth_controller.dart';
import 'controllers/language_controller.dart';
import 'routes/app_routes.dart';
import 'core/app_translations.dart';
import 'services/backend_config.dart';
import 'services/account_session_service.dart';
import 'services/android_broadcast_push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  final config = BackendConfig(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://igeisilhtmglgnqvllrx.supabase.co',
    ),
    key: const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: ''),
    isolatedTest: const bool.fromEnvironment(
      'FR21_ISOLATED_TEST',
      defaultValue: true,
    ),
  );
  await Supabase.initialize(
    url: config.url,
    publishableKey: config.key,
    httpClient: AccountHttpClient((code) {
      if (Get.isRegistered<AuthController>()) {
        Get.find<AuthController>().handleAccountFailure(code);
      }
    }, gatewayBase: Uri.parse(config.url)),
  );

  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    if (event == AuthChangeEvent.tokenRefreshed) {
      print("🔥 Token refreshed successfully");
    }
    if (event == AuthChangeEvent.signedOut) {
      print("🔥 User signed out (session invalid)");
    }
  });

  final language = Get.put(LanguageController(), permanent: true);
  await language.restore();
  Get.put(AuthController(), permanent: true);
  if (androidTestPushEnabled) {
    final push = Get.put(AndroidBroadcastPushService(), permanent: true);
    await push.initialize();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title:
          const bool.fromEnvironment('FR21_ISOLATED_TEST', defaultValue: true)
          ? 'TezRider TEST'
          : 'TezRider',
      debugShowCheckedModeBanner: false,
      translations: AppTranslations(),
      locale: Get.isRegistered<LanguageController>()
          ? LanguageController.to.locale
          : const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
      supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      initialRoute: AppRoutes.splash,
      routingCallback: (_) {
        if (Get.isRegistered<AndroidBroadcastPushService>()) {
          Get.find<AndroidBroadcastPushService>().openPendingIfReady();
        }
      },
      getPages: AppRoutes.pages,
      // Cap system text scaling so large accessibility settings can't overflow layouts.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(
            context,
          ).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15),
        ),
        child:
            const bool.fromEnvironment('FR21_ISOLATED_TEST', defaultValue: true)
            ? Banner(
                message: 'TEST',
                location: BannerLocation.topEnd,
                color: Colors.orange,
                child: child!,
              )
            : child!,
      ),
    );
  }
}
