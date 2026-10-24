import '../services/feedback_service.dart';
import '../services/rating_watch.dart';
import 'dart:async';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/rider_assignment_service.dart';
import '../services/order_timeout_service.dart';
import '../services/vendor_report_service.dart';

class VendorController extends GetxController {
  final _supabase = Supabase.instance.client;

  RxList<Map<String, dynamic>> activeOrders = <Map<String, dynamic>>[].obs;
  RxList<Map<String, dynamic>> orderHistory = <Map<String, dynamic>>[].obs;
  RxList<Map<String, dynamic>> tailoringJobs = <Map<String, dynamic>>[].obs;
  RxBool isLoadingOrders = true.obs;

  RxString totalEarnings = '—'.obs;
  RxString averageRating = '—'.obs;
  final statsError = RxnString();
  final statsLoading = false.obs;
  final _reports = VendorReportService(pageSize: 1);
  bool _statsRefreshPending = false;

  final ordersError = RxnString();
  final hasMoreOrders = false.obs;
  final ordersRefreshing = false.obs;
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  RatingWatch? _ratingWatch;
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
    if (isClosed) return;
    if (statsLoading.value) {
      _statsRefreshPending = true;
      return;
    }
    final identity = _supabase.auth.currentUser?.id;
    if (identity == null) return;
    statsLoading.value = true;
    try {
      final report = await _reports.load();
      final rating = await FeedbackService().summary(report.vendorId);
      if (isClosed || identity != _supabase.auth.currentUser?.id) return;
      if (_vendorId != null && report.vendorId != _vendorId) {
        throw StateError('Vendor identity changed');
      }
      totalEarnings.value =
          'PKR ${(report.summary['delivered_sales'] as num).toStringAsFixed(2)}';
      averageRating.value = rating['average'] == null
          ? '—'
          : '${rating['average']} ★';
      statsError.value = null;
    } catch (_) {
      if (!isClosed && identity == _supabase.auth.currentUser?.id) {
        statsError.value = 'Sales and rating could not be refreshed.';
      }
    } finally {
      statsLoading.value = false;
      if (_statsRefreshPending) {
        _statsRefreshPending = false;
        if (!isClosed && identity == _supabase.auth.currentUser?.id) {
          unawaited(loadStats());
        }
      }
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
      _ratingWatch?.dispose();
      _ratingWatch = RatingWatch(loadStats, targetId: id as int);
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
            if (status == RealtimeSubscribeStatus.subscribed) {
              ordersError.value = null;
              _queueRefresh();
            } else if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              if (!isClosed) {
                ordersError.value = 'Live updates disconnected. Reconnecting…';
              }
            }
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
              'orders!vendor_orders_order_id_fkey(id,user_id,rider_id,delivery_address,delivery_lat,delivery_lng,delivery_speed), '
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
      final orderIds = rows
          .map((row) => row['order_id'])
          .whereType<num>()
          .toSet()
          .toList();
      if (orderIds.isNotEmpty) {
        final contacts = await _supabase
            .rpc('fr21_order_contacts', params: {'p_order_ids': orderIds})
            .timeout(const Duration(seconds: 8));
        final byOrder = {
          for (final contact in contacts as List)
            contact['order_id']: {
              'name': contact['name'],
              'phone': contact['phone'],
            },
        };
        for (final row in rows) {
          final order = row['orders'];
          if (order is Map<String, dynamic>) {
            order['users'] = byOrder[row['order_id']];
          }
        }
      }
      if (isClosed) return;
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
      if (!loadMore) await loadStats();
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
    _ratingWatch?.dispose();
    _refreshTimer?.cancel();
    if (_channel != null) unawaited(_supabase.removeChannel(_channel!));
    super.onClose();
  }

  final orderTransitions = OrderTransitionFlow(
    SupabaseOrderTransitionBackend(),
  );
  Future<void> updateOrderStatus(dynamic orderId, String newStatus) async {
    final id = int.tryParse(orderId.toString());
    if (id == null) return;
    final message = await orderTransitions.change(id, newStatus);
    await refreshOrders();
    if (!isClosed) {
      Get.snackbar(
        'Order update',
        message,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  final assignment = RiderAssignmentFlow(SupabaseRiderAssignmentBackend());
  RxSet<String> get assigningOrders => assignment.busy;

  Future<String> markReadyAndAssignRider(
    Map<String, dynamic> vendorOrder,
  ) async {
    final rawId = vendorOrder['id'];
    if (rawId is! int) return 'A saved vendor order is required.';
    final message = await assignment.assign(rawId);
    await refreshOrders();
    return message;
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
