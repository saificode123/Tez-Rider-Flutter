import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/cart_controller.dart';
import 'package:flutter_application_1/controllers/product_controller.dart';
import 'package:flutter_application_1/screens/customer/cart_screen.dart';
import 'package:flutter_application_1/screens/customer/enhanced_checkout_screen.dart';
import 'package:flutter_application_1/screens/vendor/vendor_analytics_screen.dart';
import 'package:flutter_application_1/screens/ai_assistant_screen.dart';
import 'package:flutter_application_1/screens/product_detail_screen.dart';
import 'package:flutter_application_1/widgets/app_drawer.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/screens/customer/order_history_screen.dart';
import 'package:flutter_application_1/screens/customer/tailoring_screen.dart';
import 'package:flutter_application_1/screens/chat_screen.dart';
import 'package:flutter_application_1/controllers/chat_controller.dart';
import 'package:flutter_application_1/services/ai_service.dart';
import 'support/closure_harness.dart';
import 'package:flutter_application_1/services/rating_watch.dart';

class QuietRatingSubscription implements RatingSubscription {
  @override
  bool isClosed = false;
  @override
  void dispose() {
    isClosed = true;
  }
}

class QuietProducts extends ProductController {
  @override
  // Product state is explicit; no unrelated product-list subscription.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onReady() {}
}

class QuietChat extends ChatController {
  @override
  // Attachment rendering has no need for a live transport; races are separately tested.
  // ignore: must_call_super
  void onInit() {}
  @override
  Future<void> joinRoom(int roomId) async {
    currentRoomId = roomId;
    isLoading.value = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  final stock = <String, dynamic>{
    'id': 1,
    'product_id': 1,
    'vendor_id': 10,
    'name': 'Unit item',
    'price': 25,
    'qty': 2,
    'stock_qty': 2,
    'stock_confirmed': true,
    'is_available': true,
    'stock_version': 1,
  };
  late CartController cart;
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    Get.testMode = true;
    transport.requests.clear();
    transport.respond = (r) async => UiTransport.jsonResponse(
      r.url.path.endsWith('/users')
          ? [
              {'id': 1, 'name': 'Unit owner', 'phone': ''},
            ]
          : [],
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession().toJson()),
    );
    cart = Get.put(CartController(inventoryReader: (_) async => [stock]));
    Get.put<ProductController>(QuietProducts());
  });
  tearDown(Get.reset);
  Future<void> tick(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> show(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(GetMaterialApp(home: page));
    await tick(t);
  }

  testWidgets(
    'chat attachment control reports the deferred workflow and cannot fabricate an upload',
    (t) async {
      Get.put<ChatController>(QuietChat(), tag: 'chat-1');
      await show(t, const ChatScreen(roomId: 1, title: 'Unit private chat'));
      await t.tap(find.byIcon(Icons.attach_file_rounded));
      await tick(t);
      expect(
        find.text(
          'Secure attachments are not configured. No file was attached.',
        ),
        findsOneWidget,
      );
      expect(transport.requests.where((r) => r.method == 'POST'), isEmpty);
      await t.pump(const Duration(seconds: 5));
      await tick(t);
    },
  );
  testWidgets(
    'tailoring reference picker failure cannot fabricate an attachment',
    (t) async {
      await show(
        t,
        TailoringScreen(
          pickReference: (_) async =>
              throw StateError('injected picker failure'),
        ),
      );
      await t.ensureVisible(find.text('Choose reference image'));
      await t.tap(find.text('Choose reference image'));
      await tick(t);
      expect(find.text('Photo was not confirmed. Retry.'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(transport.requests.where((r) => r.method == 'POST'), isEmpty);
      await t.pump(const Duration(seconds: 5));
      await tick(t);
    },
  );
  testWidgets(
    'trusted tailoring write denial preserves the form and never claims rider assignment',
    (t) async {
      final fallback = transport.respond!;
      final pending = Completer<http.Response>();
      transport.respond = (r) async =>
          r.url.path.endsWith('/rpc/optional_submit_tailoring') &&
              r.method == 'POST'
          ? pending.future
          : fallback(r);
      await show(t, const TailoringScreen());
      await t.enterText(
        find.byType(TextField).first,
        'Unit stitching instructions',
      );
      await t.ensureVisible(find.text('Request Pickup'));
      await t.tap(find.text('Request Pickup'));
      await tick(t);
      final request = transport.requests.singleWhere(
        (r) =>
            r.method == 'POST' &&
            r.url.path.endsWith('/rpc/optional_submit_tailoring'),
      );
      final payload = jsonDecode(request.body) as Map;
      expect(payload['p_instructions'], 'Unit stitching instructions');
      expect(payload['p_request_id'], isA<String>());
      expect(payload.containsKey('customer_id'), isFalse);
      expect(
        t.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      pending.complete(
        UiTransport.jsonResponse({
          'code': '42501',
          'message': 'private backend detail',
        }, 403),
      );
      await tick(t);
      expect(find.text('Not saved'), findsOneWidget);
      expect(find.text('Unit stitching instructions'), findsOneWidget);
      expect(find.textContaining('private backend detail'), findsNothing);
      expect(find.text('Request saved'), findsNothing);
      final closing = Get.closeCurrentSnackbar();
      await t.pumpAndSettle();
      await closing;
    },
  );
  testWidgets(
    'canonical customer drawer rejects forged Admin metadata and opens its actual order route',
    (t) async {
      final saved = unitSession().toJson();
      (saved['user'] as Map)['user_metadata'] = {'role': 'admin'};
      await Supabase.instance.client.auth.recoverSession(jsonEncode(saved));
      Get.put<AuthController>(QuietAuth());
      final key = GlobalKey<ScaffoldState>();
      await show(
        t,
        Scaffold(
          key: key,
          drawer: const AppDrawer(role: 'customer'),
          body: const Text('Unit dashboard'),
        ),
      );
      key.currentState!.openDrawer();
      await tick(t);
      expect(find.text('Platform Settings'), findsNothing);
      expect(find.text('Reports'), findsNothing);
      await t.tap(find.text('my_orders'));
      await tick(t);
      expect(find.byType(OrderHistoryScreen), findsOneWidget);
    },
  );
  testWidgets(
    'canonical Admin drawer keeps customer-only actions hidden independently of metadata',
    (t) async {
      Get.put<AuthController>(QuietAuth());
      final key = GlobalKey<ScaffoldState>();
      await show(
        t,
        Scaffold(
          key: key,
          drawer: const AppDrawer(role: 'admin'),
          body: const Text('Unit dashboard'),
        ),
      );
      key.currentState!.openDrawer();
      await tick(t);
      expect(find.text('my_orders'), findsNothing);
      expect(find.text('saved_vendors'), findsNothing);
      expect(find.text('Platform Settings'), findsNothing);
      expect(find.text('Reports'), findsOneWidget);
    },
  );
  testWidgets(
    'vendor analytics error Retry replaces failed data with confirmed aggregate states',
    (t) async {
      var failed = true, populated = true;
      transport.respond = (r) async {
        if (r.url.path.endsWith('/fr28_account_status')) {
          return UiTransport.jsonResponse({
            'code': 'OK',
            'id': 10,
            'role': 'vendor',
            'verification_status': 'approved',
            'is_blocked': false,
          });
        }
        if (r.url.path.endsWith('/final2_vendor_report')) {
          return failed
              ? UiTransport.jsonResponse({
                  'code': '42501',
                  'message': 'denied',
                }, 403)
              : UiTransport.jsonResponse({
                  'code': 'OK',
                  'vendor_id': 10,
                  'currency': 'PKR',
                  'summary': {
                    'total_orders': populated ? 1 : 0,
                    'delivered_orders': populated ? 1 : 0,
                    'delivered_sales': populated ? 42 : 0,
                    'amounts_requiring_review': 0,
                    'status_counts': populated ? {'delivered': 1} : {},
                  },
                  'top_products': [],
                  'items': [],
                  'has_more': false,
                  'next_cursor': null,
                });
        }
        return UiTransport.jsonResponse([]);
      };
      await show(t, const VendorAnalyticsScreen());
      expect(
        find.text('Analytics could not be loaded. Retry when connected.'),
        findsOneWidget,
      );
      expect(find.text('Delivered sales'), findsNothing);
      failed = false;
      await t.tap(find.text('Retry'));
      await tick(t);
      expect(find.text('PKR 42.00'), findsOneWidget);
      expect(find.text('Fulfillment Rate'), findsOneWidget);
      populated = false;
      await t.tap(find.byIcon(Icons.refresh_rounded));
      await tick(t);
      expect(find.text('PKR 0.00'), findsOneWidget);
      expect(find.text('Fulfillment Rate'), findsNothing);
    },
  );
  testWidgets(
    'cart quantity controls obey stock and remove the final item through the real handler',
    (t) async {
      cart.cartItems.add({...stock});
      await show(t, const CartScreen());
      final plus = find.widgetWithIcon(IconButton, Icons.add_circle_outline);
      expect(t.widget<IconButton>(plus).onPressed, isNull);
      await t.tap(find.byIcon(Icons.remove_circle_outline));
      await tick(t);
      expect(cart.cartItems.single['qty'], 1);
      expect(t.widget<IconButton>(plus).onPressed, isNotNull);
      await t.tap(plus);
      await tick(t);
      expect(cart.cartItems.single['qty'], 2);
      await t.tap(find.byIcon(Icons.remove_circle_outline));
      await tick(t);
      await t.tap(find.byIcon(Icons.remove_circle_outline));
      await tick(t);
      expect(cart.cartItems, isEmpty);
      expect(find.text('Proceed to Checkout'), findsNothing);
    },
  );
  testWidgets(
    'cart checkout navigation renders the real COD form and validation cannot submit an unconfirmed destination',
    (t) async {
      cart.cartItems.add({...stock});
      await show(t, const CartScreen());
      await t.ensureVisible(find.byType(SwitchListTile));
      await t.tap(find.byType(SwitchListTile));
      await tick(t);
      expect(find.byType(TextField), findsNWidgets(3));
      await t.ensureVisible(find.text('Proceed to Checkout'));
      await t.tap(find.text('Proceed to Checkout'));
      await tick(t);
      expect(
        find.text(
          'Gift delivery is not configured. No gift order was submitted.',
        ),
        findsOneWidget,
      );
      expect(find.byType(EnhancedCheckoutScreen), findsNothing);
      ScaffoldMessenger.of(
        t.element(find.byType(CartScreen)),
      ).hideCurrentSnackBar();
      await t.pumpAndSettle();
      await t.ensureVisible(find.byType(SwitchListTile));
      await t.tap(find.byType(SwitchListTile));
      await tick(t);
      await t.ensureVisible(find.text('Proceed to Checkout'));
      await t.tap(find.text('Proceed to Checkout'));
      await tick(t);
      expect(find.byType(EnhancedCheckoutScreen), findsOneWidget);
      final place = find.text('Place Order (Cash on Delivery)');
      await t.ensureVisible(place);
      await t.tap(place);
      await tick(t);
      expect(
        transport.requests.where((r) => r.url.path.endsWith('/fr10_checkout')),
        isEmpty,
      );
      expect(find.byType(EnhancedCheckoutScreen), findsOneWidget);
      final closing = Get.closeCurrentSnackbar();
      await t.pumpAndSettle();
      await closing;
    },
  );
  testWidgets(
    'product detail disables purchase after a failed stock read and Retry enables the confirmed cart handler',
    (t) async {
      var failed = true;
      transport.respond = (r) async {
        if (r.url.path.endsWith('/final2_rating_summary')) {
          return UiTransport.jsonResponse({
            'code': 'OK',
            'target_id': stock['vendor_id'],
            'role': 'vendor',
            'count': 0,
            'average': null,
            'recent': [],
          });
        }
        if (r.url.path.endsWith('/products')) {
          return failed
              ? UiTransport.jsonResponse({
                  'code': '42501',
                  'message': 'denied',
                }, 403)
              : UiTransport.jsonResponse([stock]);
        }
        if (r.url.path.endsWith('/users')) {
          return UiTransport.jsonResponse([
            {'id': 1, 'name': 'Unit owner', 'phone': ''},
          ]);
        }
        return UiTransport.jsonResponse([]);
      };
      await show(
        t,
        ProductDetailScreen(
          product: stock,
          watchRatings: (_, {targetId}) => QuietRatingSubscription(),
        ),
      );
      final add = find.widgetWithText(ElevatedButton, 'Add to Cart');
      expect(t.widget<ElevatedButton>(add).onPressed, isNull);
      final retry = find.text(
        'Availability could not be refreshed. Retry when connected.',
      );
      await t.ensureVisible(retry);
      await t.pumpAndSettle();
      failed = false;
      await t.tap(retry);
      await tick(t);
      expect(t.widget<ElevatedButton>(add).onPressed, isNotNull);
      await t.ensureVisible(add);
      await t.tap(add);
      await tick(t);
      expect(cart.cartItems.single['product_id'], 1);
      expect(find.text('Add Another'), findsOneWidget);
      final closing = Get.closeCurrentSnackbar();
      await t.pumpAndSettle();
      await closing;
    },
  );
  testWidgets(
    'assistant chip uses a single pending request and displays server rate denial without fabricated content',
    (t) async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      Get.put(
        AIService(
          request: (_) {
            calls++;
            return pending.future;
          },
        ),
      );
      await show(t, const AIAssistantScreen());
      await t.tap(find.text('Find available products'));
      await tick(t);
      await t.tap(find.text('Find available products').first);
      await tick(t);
      expect(calls, 1);
      pending.complete({
        'code': 'RATE_LIMITED',
        'text': 'untrusted fabricated success',
      });
      await tick(t);
      expect(
        find.text('Too many requests. Please try again in a minute.'),
        findsOneWidget,
      );
      expect(find.text('untrusted fabricated success'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await tick(t);
    },
  );
}
