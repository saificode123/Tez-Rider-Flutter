import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/cart_controller.dart';
import 'package:flutter_application_1/controllers/notification_controller.dart';
import 'package:flutter_application_1/screens/chat_rooms_screen.dart';
import 'package:flutter_application_1/screens/customer/order_history_screen.dart';
import 'package:flutter_application_1/screens/customer/saved_addresses_screen.dart';
import 'package:flutter_application_1/screens/customer/saved_stores_screen.dart';
import 'package:flutter_application_1/screens/customer/notifications_screen.dart';
import 'package:flutter_application_1/screens/customer/profile_screen.dart';
import 'package:flutter_application_1/screens/customer/help_center_screen.dart';
import 'package:flutter_application_1/screens/vendor/vendor_products_screen.dart';
import 'package:flutter_application_1/screens/vendor/product_form_screen.dart';
import 'package:flutter_application_1/screens/search_screen.dart';
import 'package:flutter_application_1/widgets/role_access_gate.dart';
import 'support/closure_harness.dart';

class QuietNotifications extends NotificationController {
  int retries = 0, pages = 0, reads = 0;
  @override
  // State is supplied explicitly by the rendering harness.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onClose() {}
  @override
  Future<void> retry() async {
    retries++;
    error.value = null;
    isLoading.value = false;
  }

  @override
  Future<void> load({bool append = false}) async {
    if (append) pages++;
  }

  @override
  Future<void> markAsRead(String id) async {
    reads++;
  }
}

class _Page {
  const _Page(
    this.name,
    this.build,
    this.path,
    this.empty,
    this.retry,
    this.error,
  );
  final String name, path, empty, retry, error;
  final Widget Function() build;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    Get.testMode = true;
    transport.requests.clear();
    transport.respond = (request) async => UiTransport.jsonResponse(
      request.url.path.endsWith('/users')
          ? [
              {
                'id': 1,
                'name': 'Unit owner',
                'phone': '',
                'email': 'unit@example.test',
                'role': 'customer',
              },
            ]
          : [],
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession().toJson()),
    );
    Get.put(CartController(inventoryReader: (_) async => []));
  });
  tearDown(Get.reset);

  Future<void> show(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      GetMaterialApp(
        home: page,
        getPages: [
          GetPage(
            name: '/login',
            page: () => const Scaffold(body: Text('UNIT SIGN IN')),
          ),
        ],
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets(
    'address save validates, prevents duplicate pending requests and retains the form after a denied write',
    (tester) async {
      final fallback = transport.respond!;
      final pending = Completer<http.Response>();
      transport.respond = (request) async {
        if (request.url.path.endsWith('/addresses') &&
            request.method == 'POST') {
          return pending.future;
        }
        return fallback(request);
      };
      await show(tester, const SavedAddressesScreen());
      await settle(tester);
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await settle(tester);
      await tester.tap(find.byType(ElevatedButton).last);
      await settle(tester);
      expect(find.text('Enter a label'), findsOneWidget);
      expect(
        transport.requests.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/addresses'),
        ),
        isEmpty,
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Unit home');
      await tester.enterText(find.byType(TextFormField).at(1), 'Unit address');
      await tester.tap(find.byType(ElevatedButton).last);
      await settle(tester);
      await tester.tap(find.byType(ElevatedButton).last);
      await settle(tester);
      expect(
        transport.requests.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/addresses'),
        ),
        hasLength(1),
      );
      pending.complete(
        UiTransport.jsonResponse({'code': '42501', 'message': 'Denied'}, 403),
      );
      await settle(tester);
      expect(find.text('Add New Address'), findsOneWidget);
      expect(
        find.text('Address changes were not confirmed. Please retry.'),
        findsOneWidget,
      );
      expect(find.text('Unit address'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
    },
  );

  for (final confirmed in [false, true]) {
    testWidgets(
      'favourite removal requires a confirmed returned row: $confirmed',
      (tester) async {
        final fallback = transport.respond!;
        var removed = false;
        transport.respond = (request) async {
          if (request.url.path.endsWith('/favourite')) {
            if (request.method == 'DELETE') {
              if (!confirmed) {
                return UiTransport.jsonResponse({
                  'code': '42501',
                  'message': 'Denied',
                }, 403);
              }
              removed = true;
              return UiTransport.jsonResponse({'id': 8});
            }
            return UiTransport.jsonResponse(
              removed
                  ? []
                  : [
                      {
                        'id': 8,
                        'product_id': 1,
                        'products': {
                          'id': 1,
                          'name': 'Unit saved item',
                          'price': 25,
                          'category': '',
                          'image_url': '',
                          'stock_qty': 0,
                          'stock_confirmed': true,
                          'is_available': true,
                        },
                      },
                    ],
            );
          }
          return fallback(request);
        };
        await show(tester, const SavedStoresScreen());
        await settle(tester);
        expect(find.text('Unit saved item'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.favorite_rounded));
        await settle(tester);
        final request = transport.requests.singleWhere(
          (r) => r.method == 'DELETE',
        );
        expect(request.url.queryParameters['id'], 'eq.8');
        expect(request.url.queryParameters['select'], 'id');
        expect(
          find.text(confirmed ? 'Removed' : 'Not removed'),
          findsOneWidget,
        );
        expect(
          find.text('No favourites yet'),
          confirmed ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Unit saved item'),
          confirmed ? findsNothing : findsOneWidget,
        );
        final closing = Get.closeCurrentSnackbar();
        await tester.pumpAndSettle();
        await closing;
      },
    );
  }

  testWidgets(
    'confirmed address insert closes the form only after the returned row and reloads it',
    (tester) async {
      final fallback = transport.respond!;
      var saved = false;
      transport.respond = (request) async {
        if (request.url.path.endsWith('/addresses')) {
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map;
            expect(body['user_id'], 1);
            expect(body['label'], 'Unit home');
            expect(body['address'], 'Unit address');
            saved = true;
            return UiTransport.jsonResponse({'id': 'unit-address'});
          }
          return UiTransport.jsonResponse(
            saved
                ? [
                    {
                      'id': 'unit-address',
                      'label': 'Unit home',
                      'address': 'Unit address',
                    },
                  ]
                : [],
          );
        }
        return fallback(request);
      };
      await show(tester, const SavedAddressesScreen());
      await settle(tester);
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'Unit home');
      await tester.enterText(find.byType(TextFormField).at(1), 'Unit address');
      await tester.tap(find.byType(ElevatedButton).last);
      await settle(tester);
      expect(saved, isTrue);
      expect(find.text('Add New Address'), findsNothing);
      expect(find.text('Unit home'), findsOneWidget);
      expect(find.text('Unit address'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
    },
  );

  final pages = [
    _Page(
      'customer order history',
      () => const OrderHistoryScreen(),
      '/rpc/fr25_order_history',
      'No orders yet',
      'Retry',
      'Orders could not be loaded. Retry.',
    ),
    _Page(
      'customer saved addresses',
      () => const SavedAddressesScreen(),
      '/addresses',
      'No saved addresses',
      'Retry addresses',
      'Saved addresses could not be loaded. Retry.',
    ),
    _Page(
      'customer favourites',
      () => const SavedStoresScreen(),
      '/favourite',
      'No favourites yet',
      'Retry favourites',
      'Favourites could not be loaded. Retry.',
    ),
    _Page(
      'shared chat list',
      () => const ChatRoomsScreen(),
      '/rpc/fr25_chat_list',
      'No active chats.',
      'Retry',
      'Chats could not be loaded. Retry.',
    ),
    _Page(
      'vendor inventory',
      () => const VendorProductsScreen(),
      '/products',
      'No products yet',
      'Retry',
      'Inventory could not be loaded. Retry when connected.',
    ),
  ];
  for (final page in pages) {
    testWidgets('${page.name}: loading resolves to a genuine empty response', (
      tester,
    ) async {
      final pending = Completer<http.Response>();
      final fallback = transport.respond!;
      transport.respond = (request) => request.url.path.endsWith(page.path)
          ? pending.future
          : fallback(request);
      await show(tester, page.build());
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text(page.empty), findsNothing);
      pending.complete(UiTransport.jsonResponse([]));
      await settle(tester);
      expect(find.text(page.empty), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      '${page.name}: authorization failure is visible and Retry issues a new read',
      (tester) async {
        var failing = true;
        final fallback = transport.respond!;
        transport.respond = (request) async =>
            request.url.path.endsWith(page.path)
            ? UiTransport.jsonResponse(
                failing ? {'code': '42501', 'message': 'Unit denied'} : [],
                failing ? 403 : 200,
              )
            : fallback(request);
        await show(tester, page.build());
        await settle(tester);
        expect(find.text(page.error), findsOneWidget);
        // Chat retains its empty composition beneath an explicit error banner.
        if (page.name != 'shared chat list') {
          expect(find.text(page.empty), findsNothing);
        }
        final before = transport.requests
            .where((r) => r.url.path.endsWith(page.path))
            .length;
        failing = false;
        await tester.tap(find.text(page.retry));
        await settle(tester);
        expect(
          transport.requests
              .where((r) => r.url.path.endsWith(page.path))
              .length,
          before + 1,
        );
        expect(find.text(page.error), findsNothing);
        expect(find.text(page.empty), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final role in ['customer', 'vendor', 'rider', 'admin']) {
    testWidgets(
      '$role dashboard: only canonical approved role renders the guarded destination',
      (tester) async {
        transport.respond = (_) async => UiTransport.jsonResponse({
          'code': 'OK',
          'role': role,
          'verification_status': 'approved',
        });
        await show(
          tester,
          RoleAccessGate(
            role: role,
            builder: (_) => Text('UNIT $role PRIVATE'),
          ),
        );
        await settle(tester);
        expect(find.text('UNIT $role PRIVATE'), findsOneWidget);
      },
    );
  }
  for (final status in [
    {'code': 'OK', 'role': 'vendor', 'verification_status': 'approved'},
    {'code': 'OK', 'role': 'admin', 'verification_status': 'pending'},
    {'code': 'FR28_ACCOUNT_BLOCKED', 'role': 'admin'},
    {'code': 'FR28_SESSION_REVOKED', 'role': 'admin'},
  ]) {
    testWidgets(
      'guard denied ${status.toString()}: Retry cannot expose dashboard and sign-in navigation works',
      (tester) async {
        transport.respond = (_) async => UiTransport.jsonResponse(status);
        await show(
          tester,
          RoleAccessGate(
            role: 'admin',
            builder: (_) => const Text('UNIT PRIVATE'),
          ),
        );
        await settle(tester);
        expect(find.text('UNIT PRIVATE'), findsNothing);
        final before = transport.requests.length;
        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(transport.requests.length, before + 1);
        expect(find.text('UNIT PRIVATE'), findsNothing);
        await tester.tap(find.text('Return to sign in'));
        await settle(tester);
        expect(find.text('UNIT SIGN IN'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'notifications: loading, empty, error Retry, populated read and pagination handlers',
    (tester) async {
      final controller =
          Get.put<NotificationController>(QuietNotifications())
              as QuietNotifications;
      await show(tester, NotificationsScreen());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      controller.isLoading.value = false;
      await settle(tester);
      expect(find.text('No notifications yet'), findsOneWidget);
      controller.error.value = 'Unit temporary failure';
      await settle(tester);
      await tester.tap(find.text('Retry notifications'));
      await settle(tester);
      expect(controller.retries, 1);
      controller.notifications.assignAll([
        {
          'id': 1,
          'title': 'Unit private notice',
          'message': 'Unit body',
          'type': 'broadcast',
          'is_read': false,
          'created_at': '2026-10-23T00:00:00Z',
        },
      ]);
      controller.hasMore.value = true;
      await settle(tester);
      expect(find.text('Admin broadcast'), findsOneWidget);
      await tester.tap(find.text('Unit private notice'));
      await settle(tester);
      expect(controller.reads, 1);
      await tester.ensureVisible(find.text('Load more notifications'));
      await tester.tap(find.text('Load more notifications'));
      expect(controller.pages, 1);
    },
  );

  testWidgets(
    'search: error Retry, literal request, stale results and clear do not expose previous query',
    (tester) async {
      final old = Completer<http.Response>();
      var failing = true;
      transport.respond = (request) async {
        final query = (jsonDecode(request.body) as Map)['p_query'];
        if (query == 'old') return old.future;
        return UiTransport.jsonResponse(
          failing ? {'code': '22023', 'message': 'Unit rejected'} : [],
          failing ? 400 : 200,
        );
      };
      await show(tester, const SearchScreen());
      await tester.enterText(find.byType(TextField), 'old');
      await tester.enterText(find.byType(TextField), 'literal,*()');
      await settle(tester);
      expect(
        find.textContaining('Search could not be completed.'),
        findsOneWidget,
      );
      failing = false;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(transport.requests.last.body, contains('literal,*()'));
      old.complete(
        UiTransport.jsonResponse([
          {'id': 99, 'name': 'STALE UNIT PRODUCT'},
        ]),
      );
      await settle(tester);
      expect(find.text('STALE UNIT PRODUCT'), findsNothing);
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await settle(tester);
      expect(
        find.textContaining('Search could not be completed.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'product form: invalid data never mutates; trusted save failure never reports success',
    (tester) async {
      transport.respond = (request) async => request.url.path.contains('/rpc/')
          ? UiTransport.jsonResponse({
              'code': '42501',
              'message': 'Unit denied',
            }, 403)
          : UiTransport.jsonResponse([]);
      await show(tester, const ProductFormScreen(vendorId: 1));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Review product'), findsOneWidget);
      expect(
        transport.requests.any(
          (r) => r.url.path.endsWith('/fr17_save_product'),
        ),
        isFalse,
      );
      Get.closeAllSnackbars();
      await tester.pump(const Duration(seconds: 1));
      final fields = find.byType(TextField);
      // Labels select the actual field controllers rather than relying on layout.
      for (final element in fields.evaluate()) {
        final field = element.widget as TextField;
        final label = field.decoration?.labelText ?? '';
        if (label.toLowerCase().contains('name')) {
          field.controller!.text = 'Unit product';
        }
        if (label.toLowerCase().contains('price')) {
          field.controller!.text = '25';
        }
        if (label.toLowerCase().contains('stock')) field.controller!.text = '4';
      }
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        transport.requests.any(
          (r) => r.url.path.endsWith('/fr17_save_product'),
        ),
        isTrue,
      );
      expect(find.text('Save not confirmed'), findsOneWidget);
      expect(find.textContaining('Product added'), findsNothing);
      Get.closeAllSnackbars();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'profile failure renders Retry rather than private/default account data',
    (tester) async {
      transport.respond = (_) async => UiTransport.jsonResponse({
        'code': '42501',
        'message': 'Unit denied',
      }, 403);
      await show(tester, const ProfileScreen());
      await settle(tester);
      expect(
        find.text('Profile could not be loaded. Please retry.'),
        findsOneWidget,
      );
      expect(find.text('Unit owner'), findsNothing);
      final before = transport.requests.length;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(transport.requests.length, before + 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Help FAQ filter and expansion use actual visible handler state',
    (tester) async {
      await show(tester, const HelpCenterScreen());
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'payment');
      await settle(tester);
      expect(find.text('What payment methods are accepted?'), findsOneWidget);
      expect(find.text('How do I track my order?'), findsNothing);
      await tester.tap(find.text('What payment methods are accepted?'));
      await settle(tester);
      expect(find.textContaining('Only Cash on Delivery'), findsOneWidget);
    },
  );
}
