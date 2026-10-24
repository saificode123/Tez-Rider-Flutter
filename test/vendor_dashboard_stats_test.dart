import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/vendor_controller.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/controllers/rider_controller.dart';
import 'package:flutter_application_1/screens/vendor_dashboard.dart';
import 'support/closure_harness.dart';

class QuietVendor extends VendorController {
  @override
  // The navigation test supplies state and tests HTTP report effects separately.
  // ignore: must_call_super
  void onInit() {
    isLoadingOrders.value = false;
  }

  @override
  void onReady() {}
}

Map<String, dynamic> statsReport() => {
  'code': 'OK',
  'vendor_id': 10,
  'currency': 'PKR',
  'summary': {
    'total_orders': 2,
    'delivered_orders': 1,
    'delivered_sales': 17.25,
    'amounts_requiring_review': 0,
    'status_counts': {'delivered': 1, 'cancelled': 1},
  },
  'top_products': [],
  'items': [
    {
      'order_id': 2,
      'vendor_order_id': 0,
      'subtotal': 17.25,
      'delivered': true,
      'items': [],
      'payment': {'code': 'REVIEW_REQUIRED'},
    },
  ],
  'has_more': true,
  'next_cursor': {'order_id': 2, 'vendor_order_id': 0},
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  late VendorController controller;
  setUp(() async {
    transport.requests.clear();
    transport.respond = (r) async => UiTransport.jsonResponse(
      r.url.path.endsWith('/final2_vendor_report')
          ? statsReport()
          : {
              'code': 'OK',
              'target_id': 10,
              'role': 'vendor',
              'count': 0,
              'average': null,
              'recent': [],
            },
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession().toJson()),
    );
    controller = VendorController();
  });
  tearDown(() {
    controller.onClose();
    Get.reset();
  });
  test(
    'dashboard uses delivered-report cents instead of older unqualified totals',
    () async {
      expect(controller.totalEarnings.value, '—');
      await controller.loadStats();
      expect(controller.totalEarnings.value, 'PKR 17.25');
      expect(controller.statsError.value, isNull);
      final request = transport.requests.singleWhere(
        (r) => r.url.path.endsWith('/final2_vendor_report'),
      );
      expect(jsonDecode(request.body)['p_limit'], 1);
    },
  );
  test(
    'Vendor dashboard displays canonical feedback average instead of older mixed ratings',
    () async {
      transport.respond = (r) async => UiTransport.jsonResponse(
        r.url.path.endsWith('/final2_vendor_report')
            ? statsReport()
            : {
                'code': 'OK',
                'target_id': 10,
                'role': 'vendor',
                'count': 2,
                'average': 4.5,
                'recent': [],
              },
      );
      await controller.loadStats();
      expect(controller.averageRating.value, '4.5 ★');
      expect(
        transport.requests.any(
          (r) => r.url.path.endsWith('/fr21_dashboard_stats'),
        ),
        false,
      );
    },
  );
  test(
    'unapproved Rider fees never reuse delivered order totals as wages',
    () async {
      transport.respond = (_) async => UiTransport.jsonResponse({
        'today': 9999,
        'week': 19999,
        'month': 29999,
        'trips_today': 2,
        'total_deliveries': 5,
      });
      final rider = RiderController();
      await rider.loadEarnings();
      expect(rider.todayEarnings.value, '—');
      expect(rider.weeklyEarnings.value, '—');
      expect(rider.monthlyEarnings.value, '—');
      expect(rider.tripsToday.value, 2);
      expect(rider.totalDeliveries.value, 5);
    },
  );
  test(
    'failed report keeps an unknown amount and retry confirms actual data',
    () async {
      var fail = true;
      transport.respond = (r) async =>
          r.url.path.endsWith('/final2_vendor_report')
          ? UiTransport.jsonResponse(
              fail ? {'code': 'unavailable'} : statsReport(),
              fail ? 503 : 200,
            )
          : UiTransport.jsonResponse({
              'code': 'OK',
              'target_id': 10,
              'role': 'vendor',
              'count': 0,
              'average': null,
              'recent': [],
            });
      await controller.loadStats();
      expect(controller.totalEarnings.value, '—');
      expect(controller.statsError.value, isNotNull);
      fail = false;
      await controller.loadStats();
      expect(controller.totalEarnings.value, 'PKR 17.25');
      expect(controller.statsError.value, isNull);
    },
  );
  test(
    'old account aggregate arriving after account switching is discarded',
    () async {
      final pending = Completer<http.Response>();
      transport.respond = (r) => r.url.path.endsWith('/final2_vendor_report')
          ? pending.future
          : Future.value(
              UiTransport.jsonResponse({
                'code': 'OK',
                'target_id': 10,
                'role': 'vendor',
                'count': 0,
                'average': null,
                'recent': [],
              }),
            );
      final loading = controller.loadStats();
      await Future<void>.delayed(Duration.zero);
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode(
          unitSession('00000000-0000-0000-0000-000000000002').toJson(),
        ),
      );
      pending.complete(UiTransport.jsonResponse(statsReport()));
      await loading;
      expect(controller.totalEarnings.value, '—');
      expect(controller.statsError.value, isNull);
    },
  );
  testWidgets(
    'profile payment entry opens the actual authorized report instead of a placeholder',
    (t) async {
      Get.testMode = true;
      await t.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
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
          return UiTransport.jsonResponse(statsReport());
        }
        if (r.url.path.endsWith('/users')) {
          return UiTransport.jsonResponse([
            {'id': 10},
          ]);
        }
        if (r.url.path.endsWith('/vendors')) {
          return UiTransport.jsonResponse([
            {'store_name': 'Unit store'},
          ]);
        }
        return UiTransport.jsonResponse([]);
      };
      Get.put<AuthController>(QuietAuth());
      Get.put<VendorController>(QuietVendor());
      await t.pumpWidget(const GetMaterialApp(home: VendorDashboard()));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.person_outline_rounded));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Payment & Earnings'));
      await t.tap(find.text('Payment & Earnings'));
      await t.pumpAndSettle();
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('PKR 17.25'), findsOneWidget);
      expect(find.text('Coming Soon'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
