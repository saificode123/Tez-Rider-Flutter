import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'controllers/auth_controller.dart';
import 'routes/app_routes.dart';
import 'core/app_translations.dart';
import 'services/backend_config.dart';

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
      defaultValue: 'https://arrqsvejrfdbacfwtpcc.supabase.co',
    ),
    key: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFycnFzdmVqcmZkYmFjZnd0cGNjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMTczODksImV4cCI6MjA5MjY5MzM4OX0.3_0AHeKg5pM8dA9HK6f3merIrfi7SknKRaQ8kByQe7U',
    ),
    isolatedTest: const bool.fromEnvironment('FR21_ISOLATED_TEST'),
  );
  await Supabase.initialize(url: config.url, publishableKey: config.key);

  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    if (event == AuthChangeEvent.tokenRefreshed) {
      print("🔥 Token refreshed successfully");
    }
    if (event == AuthChangeEvent.signedOut) {
      print("🔥 User signed out (session invalid)");
    }
  });

  Get.put(AuthController(), permanent: true);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'TezRider',
      debugShowCheckedModeBanner: false,
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      initialRoute: AppRoutes.splash,
      getPages: AppRoutes.pages,
      // Cap system text scaling so large accessibility settings can't overflow layouts.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(
            context,
          ).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15),
        ),
        child: child!,
      ),
    );
  }
}
