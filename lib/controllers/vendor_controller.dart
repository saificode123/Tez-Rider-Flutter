import 'dart:async';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/mock_data.dart';

class VendorController extends GetxController {
  final _supabase = Supabase.instance.client;

  RxList<Map<String, dynamic>> activeOrders = <Map<String, dynamic>>[].obs;
  RxList<Map<String, dynamic>> orderHistory = <Map<String, dynamic>>[].obs;
  RxList<Map<String, dynamic>> tailoringJobs = <Map<String, dynamic>>[].obs;
  RxBool isLoadingOrders = true.obs;

  RxString totalEarnings = 'PKR 0'.obs;
  RxString averageRating = '—'.obs;

  final ordersError = RxnString();
  final hasMoreOrders = false.obs;
  final ordersRefreshing = false.obs;
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  Object? _vendorId;
  int _orderPage = 0;
  bool _refreshing = false;
  bool _refreshPending = false;

  @override
  void onInit() {
    super.onInit();
    listenToOrders();
    loadStats();
  }

  Future<void> loadStats() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      // No authenticated user — show mock stats immediately.
      totalEarnings.value = MockData.mockVendorEarnings;
      averageRating.value = MockData.mockVendorRating;
      return;
    }

    final userRecord = await _supabase
        .from('users')
        .select('id')
        .eq('email', user.email!)
        .maybeSingle();
    if (userRecord == null) {
      totalEarnings.value = MockData.mockVendorEarnings;
      averageRating.value = MockData.mockVendorRating;
      return;
    }
    final vendorId = userRecord['id'];

    // ── Earnings ──
    try {
      final delivered =
          await _supabase
                  .from('vendor_orders')
                  .select('sub_total')
                  .eq('vendor_id', vendorId)
                  .eq('status', 'delivered')
              as List;

      double total = 0;
      for (final o in delivered) {
        final st = o['sub_total'];
        total += st is num
            ? st.toDouble()
            : double.tryParse(st?.toString() ?? '0') ?? 0.0;
      }
      totalEarnings.value = total > 0
          ? 'PKR ${total.toStringAsFixed(0)}'
          : MockData.mockVendorEarnings;
    } catch (_) {
      totalEarnings.value = MockData.mockVendorEarnings;
    }

    // ── Rating ──
    try {
      final reviews =
          await _supabase
                  .from('reviews')
                  .select('rating')
                  .eq('reviewee_id', vendorId.toString())
              as List;

      if (reviews.isNotEmpty) {
        double sum = 0;
        for (final r in reviews) {
          sum += (r['rating'] as num?)?.toDouble() ?? 0.0;
        }
        averageRating.value = '${(sum / reviews.length).toStringAsFixed(1)} ★';
      } else {
        averageRating.value = MockData.mockVendorRating;
      }
    } catch (_) {
      averageRating.value = MockData.mockVendorRating;
    }
  }

  Future<void> listenToOrders() async {
    try {
      final id = await _supabase
          .rpc('fr21_actor')
          .timeout(const Duration(seconds: 8));
      if (id == null) throw StateError('Sign in required');
      if (isClosed) return;
      _vendorId = id;
      _channel = _supabase
          .channel('vendor-dashboard-$id')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'vendor_orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'vendor_id',
              value: id,
            ),
            callback: (_) => _queueRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tailoring_requests',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'vendor_id',
              value: id,
            ),
            callback: (_) => _queueRefresh(),
          )
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed) _queueRefresh();
          });
      await refreshOrders();
    } catch (_) {
      if (!isClosed) {
        ordersError.value =
            'Could not load your orders. Retry after signing in.';
        isLoadingOrders.value = false;
      }
    }
  }

  void _queueRefresh() {
    if (isClosed || _refreshTimer?.isActive == true) return;
    _refreshTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(refreshOrders()),
    );
  }

  Future<void> refreshOrders({bool loadMore = false}) async {
    if (_vendorId == null) {
      await listenToOrders();
      return;
    }
    if (_refreshing) {
      _refreshPending = true;
      return;
    }
    _refreshing = true;
    ordersRefreshing.value = true;
    final page = loadMore ? _orderPage + 1 : 0;
    try {
      final results = await Future.wait([
        _supabase
            .from('vendor_orders')
            .select(
              'id,order_id,vendor_id,status,sub_total,created_at, '
              'orders!vendor_orders_order_id_fkey(id,user_id,rider_id,delivery_address,delivery_lat,delivery_lng,delivery_speed,users!orders_user_id_fkey(name,phone)), '
              'order_items(quantity,price_at_time,products(name))',
            )
            .eq('vendor_id', _vendorId!)
            .order('created_at', ascending: false)
            .range(page * 100, page * 100 + 99)
            .timeout(const Duration(seconds: 8)),
        _supabase
            .from('tailoring_requests')
            .select('id,status,created_at,instructions')
            .eq('vendor_id', _vendorId!)
            .not('status', 'in', '(completed,picked_up_from_tailor)')
            .order('created_at', ascending: false)
            .range(0, 99)
            .timeout(const Duration(seconds: 8)),
      ]);
      if (isClosed) return;
      final rows = List<Map<String, dynamic>>.from(results[0]);
      final merged = loadMore
          ? [...activeOrders, ...orderHistory, ...rows]
          : rows;
      final unique = <Object?, Map<String, dynamic>>{
        for (final row in merged) row['id']: row,
      };
      activeOrders.assignAll(
        unique.values.where(
          (o) => o['status'] != 'delivered' && o['status'] != 'cancelled',
        ),
      );
      orderHistory.assignAll(
        unique.values.where(
          (o) => o['status'] == 'delivered' || o['status'] == 'cancelled',
        ),
      );
      tailoringJobs.assignAll(results[1]);
      _orderPage = page;
      hasMoreOrders.value = rows.length == 100;
      ordersError.value = null;
    } catch (_) {
      if (!isClosed) {
        ordersError.value =
            'Could not refresh orders. Check your connection and retry.';
      }
    } finally {
      _refreshing = false;
      if (!isClosed) {
        isLoadingOrders.value = false;
        ordersRefreshing.value = false;
      }
      if (_refreshPending) {
        _refreshPending = false;
        _queueRefresh();
      }
    }
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    if (_channel != null) unawaited(_supabase.removeChannel(_channel!));
    super.onClose();
  }

  Future<void> updateOrderStatus(dynamic orderId, String newStatus) async {
    try {
      await _supabase
          .from('vendor_orders')
          .update({'status': newStatus})
          .eq('id', orderId);
      Get.snackbar(
        'Success',
        'Order status updated to $newStatus',
        snackPosition: SnackPosition.BOTTOM,
      );

      // Optimistic local update so the UI reflects the change immediately
      // even if Realtime isn't enabled on this table in Supabase.
      Map<String, dynamic>? match;
      for (final o in activeOrders) {
        if (o['id'] == orderId) {
          match = o;
          break;
        }
      }
      final vendorId = match?['vendor_id'];
      if (match != null) {
        if (newStatus == 'delivered' || newStatus == 'cancelled') {
          activeOrders.removeWhere((o) => o['id'] == orderId);
          orderHistory.insert(0, {...match, 'status': newStatus});
        } else {
          activeOrders.value = activeOrders
              .map((o) => o['id'] == orderId ? {...o, 'status': newStatus} : o)
              .toList();
        }
      }
      if (vendorId != null) {
        unawaited(refreshOrders());
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to update order: $e');
    }
  }

  final assigningOrders = <String>{}.obs;

  Future<String> markReadyAndAssignRider(
    Map<String, dynamic> vendorOrder,
  ) async {
    final id = vendorOrder['id']?.toString();
    if (id == null || id.startsWith('mock_')) {
      return 'A saved vendor order is required.';
    }
    if (!assigningOrders.add(id)) return 'Assignment is already in progress.';
    try {
      dynamic response;
      for (var attempt = 0; ; attempt++) {
        try {
          response = await _supabase
              .rpc(
                'fr21_ready_and_assign',
                params: {'p_vendor_order_id': vendorOrder['id']},
              )
              .timeout(const Duration(seconds: 8));
          break;
        } on PostgrestException {
          rethrow;
        } catch (_) {
          if (attempt == 2) rethrow;
          await Future<void>.delayed(
            Duration(milliseconds: 300 * (1 << attempt)),
          );
        }
      }
      final result = Map<String, dynamic>.from(response as Map);
      final message = result['message'] as String;
      activeOrders.value = activeOrders
          .map(
            (order) => order['id'] == vendorOrder['id']
                ? {
                    ...order,
                    'status': 'on_the_way',
                    'orders': {
                      ...?order['orders'] as Map<String, dynamic>?,
                      'rider_id': result['rider_id'],
                    },
                  }
                : order,
          )
          .toList();
      return message;
    } catch (_) {
      return 'Ready/assignment was not confirmed. Retry safely to check the result.';
    } finally {
      assigningOrders.remove(id);
    }
  }

  Future<void> updateTailoringStatus(String requestId, String newStatus) async {
    try {
      await _supabase
          .from('tailoring_requests')
          .update({'status': newStatus})
          .eq('id', requestId);
      Get.snackbar(
        'Success',
        'Tailoring job marked as $newStatus',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Error', 'Failed to update tailoring job: $e');
    }
  }
}
