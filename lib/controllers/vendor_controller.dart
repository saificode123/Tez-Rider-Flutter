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

  // True once mock orders have been seeded so we don't re-seed on every stream event.
  bool _mockOrdersSeeded = false;

  @override
  void onInit() {
    super.onInit();
    listenToOrders();
    listenToTailoringJobs();
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

  void listenToOrders() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      // No auth — seed mock orders immediately.
      activeOrders.value = MockData.vendorOrders;
      isLoadingOrders.value = false;
      return;
    }

    _supabase
        .from('users')
        .select('id')
        .eq('email', user.email!)
        .maybeSingle()
        .then((userRecord) {
          if (userRecord == null) {
            activeOrders.value = MockData.vendorOrders;
            isLoadingOrders.value = false;
            return;
          }
          final vendorId = userRecord['id'];
          // Stream just tells us *something changed* — we re-fetch the
          // enriched (joined) data below so item names / customer info
          // stay up to date in real time too.
          _supabase
              .from('vendor_orders')
              .stream(primaryKey: ['id'])
              .eq('vendor_id', vendorId)
              .listen((_) => _refreshEnrichedOrders(vendorId));
          _refreshEnrichedOrders(vendorId);
        });
  }

  Future<void> _refreshEnrichedOrders(dynamic vendorId) async {
    try {
      final data = await _supabase
          .from('vendor_orders')
          .select(
            '*, orders!vendor_orders_order_id_fkey(id, user_id, delivery_address, delivery_lat, delivery_lng, delivery_speed, users!orders_user_id_fkey(name, phone)), '
            'order_items(quantity, price_at_time, products(name))',
          )
          .eq('vendor_id', vendorId)
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(data);
      final active = list
          .where(
            (o) => o['status'] != 'delivered' && o['status'] != 'cancelled',
          )
          .toList();
      final history = list
          .where(
            (o) => o['status'] == 'delivered' || o['status'] == 'cancelled',
          )
          .toList();

      // A real fetch succeeded — commit to real data from now on (even if
      // it's empty right now). Never fall back to mock again after this,
      // so mock and real orders can't end up mixed in the same list.
      _mockOrdersSeeded = true;
      activeOrders.value = active;
      orderHistory.value = history;
      isLoadingOrders.value = false;
    } catch (e) {
      // Only ever show mock data if we have NEVER managed a real fetch.
      // ignore: avoid_print
      print('Vendor orders fetch failed: $e');
      if (!_mockOrdersSeeded) {
        _mockOrdersSeeded = true;
        activeOrders.value = MockData.vendorOrders;
      }
      isLoadingOrders.value = false;
    }
  }

  void listenToTailoringJobs() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _supabase
        .from('users')
        .select('id')
        .eq('email', user.email!)
        .maybeSingle()
        .then((userRecord) {
          if (userRecord != null) {
            _supabase
                .from('tailoring_requests')
                .stream(primaryKey: ['id'])
                .eq('vendor_id', userRecord['id'])
                .listen((data) {
                  tailoringJobs.value = data
                      .where(
                        (o) =>
                            o['status'] != 'completed' &&
                            o['status'] != 'picked_up_from_tailor',
                      )
                      .toList();
                  tailoringJobs.sort(
                    (a, b) => (b['created_at'] ?? '').compareTo(
                      a['created_at'] ?? '',
                    ),
                  );
                });
          }
        });
  }

  Future<void> updateOrderStatus(dynamic orderId, String newStatus) async {
    // Mock order IDs start with 'mock_' — don't send to Supabase.
    if (orderId.toString().startsWith('mock_')) {
      activeOrders.value = activeOrders
          .map((o) => o['id'] == orderId ? {...o, 'status': newStatus} : o)
          .toList();
      // Remove from active list if delivered/cancelled.
      if (newStatus == 'delivered' || newStatus == 'cancelled') {
        activeOrders.removeWhere((o) => o['id'] == orderId);
      }
      Get.snackbar(
        'Updated',
        'Order status updated to $newStatus',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
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
        _refreshEnrichedOrders(vendorId);
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to update order: $e');
    }
  }

  final _assigningOrders = <String>{};

  Future<String> markReadyAndAssignRider(
    Map<String, dynamic> vendorOrder,
  ) async {
    final id = vendorOrder['id']?.toString();
    if (id == null || id.startsWith('mock_')) {
      return 'A saved vendor order is required.';
    }
    if (!_assigningOrders.add(id)) return 'Assignment is already in progress.';
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
                ? {...order, 'status': 'on_the_way'}
                : order,
          )
          .toList();
      return message;
    } catch (_) {
      return 'Ready/assignment was not confirmed. Retry safely to check the result.';
    } finally {
      _assigningOrders.remove(id);
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
