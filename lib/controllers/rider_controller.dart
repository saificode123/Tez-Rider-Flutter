import 'dart:math';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/rider_presence.dart';

class RiderController extends GetxController with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;

  RxList<Map<String, dynamic>> availableOrders = <Map<String, dynamic>>[].obs;
  RxList<Map<String, dynamic>> availableTailoring =
      <Map<String, dynamic>>[].obs;
  Rx<Map<String, dynamic>?> currentOrder = Rx<Map<String, dynamic>?>(null);
  RxBool isOnline = false.obs;
  final presenceBusy = true.obs;
  final presenceReady = false.obs;
  final presenceError = RxnString();
  late final RiderPresence _presence;
  RealtimeChannel? _dashboardChannel;
  Object? _riderId;
  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _refreshPending = false;
  int _requestsPage = 0;
  final hasMoreRequests = false.obs;
  final requestsLoading = false.obs;

  RxString todayEarnings = 'PKR 0'.obs;
  RxString weeklyEarnings = 'PKR 0'.obs;
  RxString monthlyEarnings = 'PKR 0'.obs;
  RxInt tripsToday = 0.obs;
  RxInt totalDeliveries = 0.obs;

  @override
  void onInit() {
    super.onInit();
    _presence = RiderPresence(
      (name, parameters) async {
        final response = await _supabase.rpc(name, params: parameters);
        return Map<String, dynamic>.from(response as Map);
      },
      () {
        isOnline.value = _presence.online;
        presenceBusy.value = _presence.busy;
        presenceReady.value = _presence.ready;
        presenceError.value = _presence.error;
      },
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_presence.restore());
    unawaited(_listenToDashboard());
    checkCurrentOrder();
    loadEarnings();
  }

  Future<void> loadEarnings() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final userRecord = await _supabase
        .from('users')
        .select('id')
        .eq('email', user.email!)
        .maybeSingle();
    if (userRecord == null) return;
    final riderId = userRecord['id'];

    try {
      final now = DateTime.now();
      final todayStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).toUtc().toIso8601String();
      final weekStart = now
          .subtract(const Duration(days: 7))
          .toUtc()
          .toIso8601String();
      final monthStart = now
          .subtract(const Duration(days: 30))
          .toUtc()
          .toIso8601String();

      final delivered =
          await _supabase
                  .from('orders')
                  .select('amount, created_at')
                  .eq('rider_id', riderId)
                  .eq('order_status', 'delivered')
              as List;

      double todayTotal = 0, weekTotal = 0, monthTotal = 0;
      int todayTrips = 0;

      for (final o in delivered) {
        final createdAt = o['created_at'] as String?;
        if (createdAt == null) continue;
        final date = DateTime.tryParse(createdAt);
        if (date == null) continue;
        final amount = (o['amount'] as num?)?.toDouble() ?? 0.0;

        if (date.isAfter(DateTime.parse(monthStart))) {
          monthTotal += amount;
          if (date.isAfter(DateTime.parse(weekStart))) {
            weekTotal += amount;
            if (date.isAfter(DateTime.parse(todayStart))) {
              todayTotal += amount;
              todayTrips++;
            }
          }
        }
      }

      todayEarnings.value = 'PKR ${todayTotal.toStringAsFixed(0)}';
      weeklyEarnings.value = 'PKR ${weekTotal.toStringAsFixed(0)}';
      monthlyEarnings.value = 'PKR ${monthTotal.toStringAsFixed(0)}';
      tripsToday.value = todayTrips;
      totalDeliveries.value = delivered.length;
    } catch (_) {}
  }

  Future<void> _listenToDashboard() async {
    try {
      final id = await _supabase
          .rpc('fr21_actor')
          .timeout(const Duration(seconds: 8));
      if (id == null || isClosed) return;
      _riderId = id;
      _dashboardChannel = _supabase
          .channel('rider-dashboard-$id')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.inFilter,
              column: 'order_status',
              value: ['placed', 'accepted'],
            ),
            callback: (_) => _queueRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'rider_id',
              value: id,
            ),
            callback: (_) => _queueRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tailoring_requests',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.inFilter,
              column: 'status',
              value: ['pickup_requested', 'ready_for_customer'],
            ),
            callback: (_) => _queueRefresh(),
          )
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed) _queueRefresh();
          });
      await _refreshRequests();
    } catch (_) {
      if (!isClosed) presenceError.value = 'Could not load delivery requests.';
    }
  }

  void _queueRefresh() {
    if (isClosed || _refreshTimer?.isActive == true) return;
    _refreshTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_refreshRequests()),
    );
  }

  Future<void> loadMoreRequests() => _refreshRequests(loadMore: true);

  Future<void> _refreshRequests({bool loadMore = false}) async {
    if (isClosed) return;
    if (_refreshing) {
      if (!loadMore) {
        _refreshPending = true;
      }
      return;
    }
    _refreshing = true;
    requestsLoading.value = true;
    final page = loadMore ? _requestsPage + 1 : 0;
    try {
      final responses = await Future.wait([
        _supabase
            .from('orders')
            .select(
              'id,rider_id,order_status,created_at,amount,delivery_address,delivery_lat,delivery_lng',
            )
            .inFilter('order_status', ['placed', 'accepted'])
            .or('rider_id.is.null,rider_id.eq.$_riderId')
            .order('created_at', ascending: false)
            .range(page * 100, page * 100 + 99)
            .timeout(const Duration(seconds: 8)),
        _supabase
            .from('tailoring_requests')
            .select('id,status,rider_id,created_at')
            .inFilter('status', ['pickup_requested', 'ready_for_customer'])
            .order('created_at', ascending: false)
            .range(page * 100, page * 100 + 99)
            .timeout(const Duration(seconds: 8)),
      ]);
      if (!isClosed) {
        if (loadMore) {
          final orderIds = availableOrders.map((o) => o['id']).toSet();
          final tailoringIds = availableTailoring.map((o) => o['id']).toSet();
          availableOrders.addAll(
            responses[0].where((o) => !orderIds.contains(o['id'])),
          );
          availableTailoring.addAll(
            responses[1].where((o) => !tailoringIds.contains(o['id'])),
          );
        } else {
          availableOrders.assignAll(responses[0]);
          availableTailoring.assignAll(responses[1]);
        }
        _requestsPage = page;
        hasMoreRequests.value = responses.any((rows) => rows.length == 100);
      }
      await checkCurrentOrder();
    } catch (_) {
      if (!isClosed) {
        presenceError.value = 'Could not refresh delivery requests.';
      }
    } finally {
      _refreshing = false;
      if (!isClosed) {
        requestsLoading.value = false;
      }
      if (_refreshPending) {
        _refreshPending = false;
        _queueRefresh();
      }
    }
  }

  Future<void> checkCurrentOrder() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final userRecord = await _supabase
        .from('users')
        .select('id')
        .eq('email', user.email!)
        .maybeSingle();
    if (userRecord == null) return;
    final riderId = userRecord['id'];

    final orderData = await _supabase
        .from('orders')
        .select()
        .eq('rider_id', riderId)
        .eq('order_status', 'on_the_way')
        .maybeSingle();

    if (orderData != null) {
      currentOrder.value = {...orderData, 'type': 'order'};
      return;
    }

    _supabase
        .from('users')
        .select('id')
        .eq('email', user.email!)
        .maybeSingle()
        .then((rec) async {
          if (rec != null) {
            final tailorData = await _supabase
                .from('tailoring_requests')
                .select()
                .eq('rider_id', rec['id'])
                .inFilter('status', [
                  'picked_up_from_customer',
                  'picked_up_from_tailor',
                ])
                .maybeSingle();

            if (tailorData != null) {
              currentOrder.value = {...tailorData, 'type': 'tailoring'};
            }
          }
        });
  }

  Future<void> acceptOrder(Map<String, dynamic> order) async {
    if (currentOrder.value != null) {
      Get.snackbar(
        'Ongoing Delivery',
        'Please complete your current order first.',
        backgroundColor: Get.theme.colorScheme.error,
        colorText: Get.theme.colorScheme.onError,
      );
      return;
    }
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final userRecord = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .maybeSingle();
      if (userRecord == null) return;
      final otp = (100000 + Random().nextInt(900000)).toString();
      await _supabase
          .from('orders')
          .update({
            'rider_id': userRecord['id'],
            'order_status': 'on_the_way',
            'delivery_otp': otp,
          })
          .eq('id', order['id']);

      currentOrder.value = {...order, 'type': 'order', 'delivery_otp': otp};
      Get.snackbar(
        'Order Accepted',
        'Navigate to the customer now.',
        backgroundColor: Get.theme.colorScheme.primary,
        colorText: Get.theme.colorScheme.onPrimary,
      );
    } catch (e) {
      Get.snackbar('Error', 'Could not accept order.');
    }
  }

  Future<bool> verifyOtpAndDeliver(String enteredOtp) async {
    final current = currentOrder.value;
    if (current == null) return false;
    try {
      final row = await _supabase
          .from('orders')
          .select('delivery_otp')
          .eq('id', current['id'])
          .maybeSingle();

      final correct = row?['delivery_otp']?.toString() ?? '';
      if (enteredOtp != correct) {
        HapticFeedback.heavyImpact();
        return false;
      }

      await _supabase
          .from('orders')
          .update({'order_status': 'delivered'})
          .eq('id', current['id']);

      try {
        await _supabase.from('delivery_proof').insert({
          'proofid': 'proof_${DateTime.now().millisecondsSinceEpoch}',
          'orderid': current['id'].toString(),
          'riderid': _supabase.auth.currentUser?.id ?? '',
          'photourl': '',
          'location': '',
          'otpconfirmed': true,
          'otp': enteredOtp,
          'is_verified': true,
          'verified_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {}

      HapticFeedback.mediumImpact();
      currentOrder.value = null;
      return true;
    } catch (e) {
      Get.snackbar('Error', 'Could not verify OTP.');
      return false;
    }
  }

  Future<void> acceptTailoring(Map<String, dynamic> request) async {
    if (currentOrder.value != null) {
      Get.snackbar(
        'Ongoing Delivery',
        'Please complete your current order first.',
      );
      return;
    }
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final userRecord = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .maybeSingle();
      if (userRecord == null) return;

      String nextStatus = request['status'] == 'pickup_requested'
          ? 'picked_up_from_customer'
          : 'picked_up_from_tailor';

      await _supabase
          .from('tailoring_requests')
          .update({'rider_id': userRecord['id'], 'status': nextStatus})
          .eq('id', request['id']);

      currentOrder.value = {
        ...request,
        'status': nextStatus,
        'type': 'tailoring',
      };
      Get.snackbar('Accepted', 'Please proceed with the pickup.');
    } catch (e) {
      Get.snackbar('Error', 'Could not accept tailoring request.');
    }
  }

  Future<void> markDelivered() async {
    final current = currentOrder.value;
    if (current == null) return;

    try {
      if (current['type'] == 'order') {
        await _supabase
            .from('orders')
            .update({'order_status': 'delivered'})
            .eq('id', current['id']);
        Get.snackbar('Success', 'Order marked as delivered!');
      } else if (current['type'] == 'tailoring') {
        String nextStatus = current['status'] == 'picked_up_from_customer'
            ? 'delivered_to_tailor'
            : 'completed';
        await _supabase
            .from('tailoring_requests')
            .update({'status': nextStatus})
            .eq('id', current['id']);
        Get.snackbar('Success', 'Tailoring delivery complete!');
      }
      currentOrder.value = null;
    } catch (e) {
      Get.snackbar('Error', 'Could not complete delivery.');
    }
  }

  Future<void> setOnlineStatus(bool status) => _presence.setOnline(status);

  Future<void> restoreOnlineStatus() => _presence.restore();

  Future<void> goOffline() => _presence.offline();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(goOffline());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(restoreOnlineStatus());
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(goOffline());
    _presence.dispose();
    _refreshTimer?.cancel();
    if (_dashboardChannel != null) {
      unawaited(_supabase.removeChannel(_dashboardChannel!));
    }
    super.onClose();
  }
}
