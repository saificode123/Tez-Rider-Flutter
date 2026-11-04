// Offline presentation fixtures only; no hosted backend or device sensors.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/controllers/admin_controller.dart';
import 'package:flutter_application_1/controllers/cart_controller.dart';
import 'package:flutter_application_1/controllers/product_controller.dart';
import 'package:flutter_application_1/controllers/notification_controller.dart';
import 'package:flutter_application_1/controllers/vendor_info_controller.dart';
import 'package:flutter_application_1/controllers/rider_controller.dart';
import 'package:flutter_application_1/controllers/vendor_controller.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/screens/login_screen.dart';
import 'package:flutter_application_1/screens/signup_screen.dart';
import 'package:flutter_application_1/screens/customer_dashboard.dart';
import 'package:flutter_application_1/screens/customer/cart_screen.dart';
import 'package:flutter_application_1/screens/customer/notifications_screen.dart';
import 'package:flutter_application_1/screens/customer/order_history_screen.dart';
import 'package:flutter_application_1/screens/admin_dashboard.dart';
import 'package:flutter_application_1/screens/rider_dashboard.dart';
import 'package:flutter_application_1/screens/vendor_dashboard.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/models/product_model.dart';
import 'package:flutter_application_1/screens/product_detail_screen.dart';
import 'package:flutter_application_1/screens/customer/enhanced_checkout_screen.dart';
import 'package:flutter_application_1/screens/admin_broadcasts_screen.dart';
import 'package:flutter_application_1/controllers/admin_broadcast_controller.dart';
import 'package:flutter_application_1/services/admin_broadcast_service.dart';
import 'package:flutter_application_1/services/rating_watch.dart';
import 'support/closure_harness.dart';

// Clearly labelled test-only catalogue data, never shipped as application data.
const _fixtureProduct = <String, dynamic>{
  'id': 1,
  'product_id': 1,
  'vendor_id': 10,
  'category': 'Food',
  'name': 'UI fixture meal',
  'description': 'Offline presentation fixture',
  'price': 250,
  'qty': 1,
  'image_url': '',
  'stock_qty': 3,
  'stock_confirmed': true,
  'stock_version': 1,
  'is_available': true,
};

class _Rating implements RatingSubscription {
  @override
  bool isClosed = false;
  @override
  void dispose() {
    isClosed = true;
  }
}

class _Broadcasts implements AdminBroadcastBackend {
  @override
  Future<int> estimate(String audience) async => 0;
  @override
  Future<List<Map<String, dynamic>>> history(
    Map<String, dynamic>? before,
  ) async => [];
  @override
  Future<Map<String, dynamic>> send(Map<String, dynamic> request) async =>
      throw StateError('Visual fixtures must never send broadcasts.');
}

class _Admin extends AdminController {
  @override
  // ignore: must_call_super
  void onInit() {
    isLoading.value = false;
  }
}

class _Rider extends RiderController {
  @override
  // ignore: must_call_super
  void onInit() {
    presenceBusy.value = false;
    presenceReady.value = true;
  }

  @override
  void onReady() {}
  @override
  // No initialized native presence service in this rendering double.
  // ignore: must_call_super
  void onClose() {}
}

class _Vendor extends VendorController {
  @override
  // ignore: must_call_super
  void onInit() {
    isLoadingOrders.value = false;
  }

  @override
  void onReady() {}
}

class _Products extends ProductController {
  @override
  // ignore: must_call_super
  void onInit() {
    isLoading.value = false;
    products.assignAll([ProductModel.fromJson(_fixtureProduct)]);
  }

  @override
  void onReady() {}
}

class _Notifications extends NotificationController {
  @override
  // ignore: must_call_super
  void onInit() {
    isLoading.value = false;
  }

  @override
  void onReady() {}
  @override
  // ignore: must_call_super
  void onClose() {}
}

class _Vendors extends VendorInfoController {
  @override
  Future<void> loadCustomerLocation() async {}
  @override
  Future<void> loadVendorInfo(Iterable<String> vendorIds) async {}
}

Future<ByteData> _materialIconsForTest() async {
  try {
    return await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  } on FlutterError {
    // The widget runner can omit SDK icon assets while disabling asset fonts.
    // Load the same SDK font explicitly; application assets remain unmodified.
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final bytes = await File(
      '${artifacts.path}/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeClosureClient(transport);
    final cacheDirectory = await Directory.systemTemp.createTemp(
      'tez-ui-image-cache-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => cacheDirectory.path,
        );
    final icons = FontLoader('MaterialIcons')..addFont(_materialIconsForTest());
    await icons.load();
    final urdu = FontLoader('NotoNaskhArabic_regular')
      ..addFont(rootBundle.load('assets/images/NotoNaskhArabic-Regular.ttf'));
    await urdu.load();
    // Flutter's widget runner disables asset fonts. Load existing font bytes
    // explicitly for reproducible presentation evidence, including fallback text.
    for (final family in ['Roboto', 'Ahem', 'Poppins']) {
      final loader = FontLoader(family);
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
        'Black',
      ]) {
        loader.addFont(rootBundle.load('assets/images/Poppins-$weight.ttf'));
      }
      await loader.load();
    }
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    Get.testMode = true;
    VaultDouble().install();
    transport.requests.clear();
    transport.respond = (request) async {
      final path = request.url.path;
      if (path.endsWith('/final2_catalog')) {
        return UiTransport.jsonResponse({
          'items': [_fixtureProduct],
          'has_more': false,
          'next_cursor': null,
        });
      }
      if (path.endsWith('/final2_catalog_categories')) {
        return UiTransport.jsonResponse([
          {'name': 'Food'},
          {'name': 'Grocery'},
        ]);
      }
      if (path.endsWith('/products')) {
        return UiTransport.jsonResponse([_fixtureProduct]);
      }

      if (path.endsWith('/users')) {
        return UiTransport.jsonResponse([
          {'id': 1, 'name': 'UI fixture', 'phone': '', 'role': 'customer'},
        ]);
      }
      if (path.endsWith('/final2_store_settings')) {
        return UiTransport.jsonResponse({
          'store_id': 10,
          'store_name': 'UI fixture store',
          'address': '',
          'is_active': true,
          'version': 0,
        });
      }
      if (path.endsWith('/final2_saved_addresses')) {
        return UiTransport.jsonResponse({
          'items': [],
          'has_more': false,
          'cursor': null,
        });
      }
      return UiTransport.jsonResponse([]);
    };
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession().toJson()),
    );
    Get.put<AuthController>(QuietAuth());
    final cart = Get.put<CartController>(
      CartController(inventoryReader: (_) async => [_fixtureProduct]),
    );
    cart.cartItems.add({..._fixtureProduct});
    Get.put<ProductController>(_Products());
    Get.put<NotificationController>(_Notifications());
    Get.put<VendorInfoController>(_Vendors());
    Get.put<AdminController>(_Admin());
    Get.put<RiderController>(_Rider());
    Get.put<VendorController>(_Vendor());
  });
  tearDown(Get.reset);

  final pages = <String, Widget Function()>{
    'login': () => const LoginScreen(),
    'signup': () => const SignupScreen(),
    'customer': () => const CustomerDashboard(),
    'cart': () => const CartScreen(),
    'notifications': () => NotificationsScreen(),
    'orders': () => const OrderHistoryScreen(),
    'rider': () => const RiderDashboard(),
    'vendor': () => const VendorDashboard(),
    'admin': () => const AdminDashboard(),
    'product': () => ProductDetailScreen(
      product: {..._fixtureProduct},
      watchRatings: (_, {targetId}) => _Rating(),
    ),
    'checkout': () => EnhancedCheckoutScreen(
      cart: Get.find<CartController>(),
      customerId: unitSession().user.id,
    ),
    'broadcasts': () => AdminBroadcastsScreen(
      controller: AdminBroadcastController(backend: _Broadcasts()),
    ),
  };
  for (final page in pages.entries) {
    testWidgets('offline ${page.key} presentation renders without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = Size(
        (const int.fromEnvironment(
          'VISUAL_WIDTH',
          defaultValue: 390,
        )).toDouble(),
        (const int.fromEnvironment(
          'VISUAL_HEIGHT',
          defaultValue: 844,
        )).toDouble(),
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          locale: const bool.fromEnvironment('VISUAL_RTL')
              ? const Locale('ur', 'PK')
              : const Locale('en', 'US'),
          translations: AppTranslations(),
          supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(
                double.parse(
                  const String.fromEnvironment(
                    'VISUAL_TEXT_SCALE',
                    defaultValue: '1',
                  ),
                ),
              ),
            ),
            child: RepaintBoundary(key: captureKey, child: child!),
          ),
          home: page.value(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        await GoogleFonts.pendingFonts();
      });
      await tester.pump(const Duration(milliseconds: 200));
      const output = String.fromEnvironment('VISUAL_OUTPUT');
      if (output.isNotEmpty) {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/${page.key}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });
  }
}
