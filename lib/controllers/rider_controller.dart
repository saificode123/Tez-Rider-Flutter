import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/rider_presence.dart';
import '../services/delivery_otp_service.dart';
import '../services/pre_delivery_checklist_service.dart';
import '../services/delivery_location.dart';
import '../services/delivery_location_platform.dart';

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
  StreamSubscription<AuthState>? _authSubscription;
  final deliveryBusy = false.obs;
  final deliveryOtp = DeliveryOtpFlow(SupabaseDeliveryOtpBackend());
  final checklist = PreDeliveryChecklistFlow(SupabaseChecklistBackend());
  final location = RiderLocationService(
    createRiderLocationSource(),
    SupabaseDeliveryLocationBackend(),
    onMetric: recordLocationMetric,
  );
  Worker? _locationWorker;
  bool _foreground = true;
  int _requestsPage = 0;
  final hasMoreRequests = false.obs;
  final requestsLoading = false.obs;
  final requestsError = RxnString();

  RxString todayEarnings = '—'.obs;
  RxString weeklyEarnings = '—'.obs;
  RxString monthlyEarnings = '—'.obs;
  RxInt tripsToday = 0.obs;
  RxInt totalDeliveries = 0.obs;

  @override
  void onInit() {
    super.onInit();
    _locationWorker = everAll([isOnline, currentOrder], (_) => _syncLocation());
    _presence = RiderPresence(
      (name, parameters) async {
        try {
          final response = await _supabase.rpc(name, params: parameters);
          return Map<String, dynamic>.from(response as Map);
        } on AuthException {
          throw const PresenceFailure('Session expired. Please sign in again.');
        } on PostgrestException catch (e) {
          throw PresenceFailure(
            e.code == 'PGRST202'
                ? 'Availability setup is pending on the server.'
                : e.code == '42501'
                ? 'An approved rider account is required.'
                : e.code == '40001' || e.code == 'PT409'
                ? 'This session changed. Tap Retry to restore availability.'
                : 'Availability could not be confirmed. Tap Retry.',
            retryable: e.code == '503' || e.code == '504',
          );
        }
      },
      () {
        isOnline.value = _presence.online;
        presenceBusy.value = _presence.busy;
        presenceReady.value = _presence.ready;
        presenceError.value = _presence.error;
      },
      allowTransportRecovery: () =>
          location.sharing.value &&
          currentOrder.value?['type'] == 'order' &&
          currentOrder.value?['order_status'] == 'on_the_way',
    );
    WidgetsBinding.instance.addObserver(this);
    final initialAccount = _supabase.auth.currentUser?.id;
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        unawaited(goOffline());
      } else if (data.session?.user.id != initialAccount) {
        unawaited(location.stop());
        _syncLocation();
      }
    });
    unawaited(_presence.restore());
    unawaited(_listenToDashboard());
    unawaited(_loadInitialData());
  }

  void _syncLocation() {
    if (isClosed) return;
    final order = currentOrder.value;
    unawaited(
      location.reconcile(
        online: isOnline.value,
        activeOrder:
            order?['type'] == 'order' && order?['order_status'] == 'on_the_way'
            ? order!['id'] as int?
            : null,
        foreground: _foreground,
        presenceInterrupted: _presence.transportInterrupted,
      ),
    );
  }

  Future<void> shareDeliveryLocation() async {
    final order = currentOrder.value;
    if (order?['type'] == 'order' &&
        order?['order_status'] == 'on_the_way' &&
        order?['id'] is int) {
      if (!isOnline.value) {
        location.message.value = 'Go online before sharing delivery location.';
        return;
      }
      await location.share(order!['id'] as int);
    }
  }

  Future<void> _loadInitialData() async {
    try {
      await Future.wait([checkCurrentOrder(), loadEarnings()]);
    } catch (_) {
      if (!isClosed) presenceError.value = 'Could not load rider deliveries.';
    }
  }

  Future<void> updateLocation(double latitude, double longitude) async {
    try {
      await _supabase
          .rpc(
            'fr21_update_location',
            params: {'p_lat': latitude, 'p_lng': longitude},
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      if (!isClosed) {
        Get.snackbar(
          "Location".tr,
          "Your location could not be saved. Delivery matching may be unavailable."
              .tr,
        );
      }
    }
  }

  Future<void> loadEarnings() async {
    final identity = _supabase.auth.currentUser?.id;
    if (identity == null) throw StateError('Sign in required');
    final response = await _supabase
        .rpc('fr21_dashboard_stats')
        .timeout(const Duration(seconds: 8));
    if (isClosed || identity != _supabase.auth.currentUser?.id) return;
    final stats = Map<String, dynamic>.from(response as Map);
    if (stats['trips_today'] is! int ||
        stats['trips_today'] < 0 ||
        stats['total_deliveries'] is! int ||
        stats['total_deliveries'] < 0) {
      throw const FormatException('Delivery counts were not confirmed.');
    }
    // Order totals are not earned Rider fees. No compensation rule is approved.
    // Keep these unknown until a trusted earned-fee ledger is configured.
    todayEarnings.value = '—';
    weeklyEarnings.value = '—';
    monthlyEarnings.value = '—';
    tripsToday.value = stats['trips_today'];
    totalDeliveries.value = stats['total_deliveries'];
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
              value: ['placed', 'accepted', 'ready', 'on_the_way'],
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
            if (status == RealtimeSubscribeStatus.subscribed) {
              requestsError.value = null;
              _queueRefresh();
            } else if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              if (!isClosed) {
                requestsError.value =
                    'Live updates disconnected. Reconnecting…';
              }
            }
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
            .inFilter('order_status', [
              'placed',
              'accepted',
              'ready',
              'on_the_way',
            ])
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
      if (!isClosed) requestsError.value = null;
    } catch (_) {
      if (!isClosed) {
        requestsError.value = 'Could not refresh delivery requests. Tap Retry.';
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
        .inFilter('order_status', [
          'pending',
          'accepted',
          'preparing',
          'ready',
          'on_the_way',
        ])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));

    if (orderData != null) {
      currentOrder.value = {...orderData, 'type': 'order'};
      await checklist.open(orderData['id'] as int);
      return;
    }

    await checklist.open(null);
    final tailorData = await _supabase
        .from('tailoring_requests')
        .select()
        .eq('rider_id', riderId)
        .inFilter('status', [
          'picked_up_from_customer',
          'picked_up_from_tailor',
        ])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    if (!isClosed) {
      currentOrder.value = tailorData == null
          ? null
          : {...tailorData, 'type': 'tailoring'};
    }
  }

  Future<void> acceptOrder(Map<String, dynamic> order) async {
    if (deliveryBusy.value) return;
    if (currentOrder.value != null &&
        (currentOrder.value?['type'] != 'order' ||
            currentOrder.value?['id'] != order['id'])) {
      Get.snackbar(
        "Ongoing Delivery".tr,
        "Please complete your current order first.".tr,
        backgroundColor: Get.theme.colorScheme.error,
        colorText: Get.theme.colorScheme.onError,
      );
      return;
    }
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    deliveryBusy.value = true;
    try {
      final userRecord = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .maybeSingle();
      if (userRecord == null) return;
      final result = Map<String, dynamic>.from(
        await _supabase
                .rpc('fr21_accept_order', params: {'p_order_id': order['id']})
                .timeout(const Duration(seconds: 8))
            as Map,
      );
      if (isClosed) return;
      currentOrder.value = {...order, ...result, 'type': 'order'};
      await checklist.open(order['id'] as int);
      Get.snackbar(
        "Order Accepted".tr,
        "Complete the pickup checklist before starting delivery.".tr,
        backgroundColor: Get.theme.colorScheme.primary,
        colorText: Get.theme.colorScheme.onPrimary,
      );
    } catch (e) {
      Get.snackbar("Error".tr, "Could not accept order.".tr);
    } finally {
      deliveryBusy.value = false;
    }
  }

  Future<void> requestDeliveryOtp() async {
    final order = currentOrder.value;
    if (order == null ||
        order['type'] != 'order' ||
        order['id'] is! int ||
        deliveryBusy.value) {
      return;
    }
    if (order['order_status'] != 'on_the_way') {
      Get.snackbar(
        "Pickup checklist".tr,
        checklistMessage('CHECKLIST_REQUIRED'),
      );
      return;
    }
    deliveryBusy.value = true;
    try {
      if (!deliveryOtp.begin(order['id'] as int)) {
        return;
      }
      await deliveryOtp.refresh();
      if (!deliveryOtp.active && !deliveryOtp.delivered) {
        await deliveryOtp.requestEmail();
      }
    } finally {
      if (!isClosed) deliveryBusy.value = false;
    }
  }

  Future<void> startDelivery() async {
    if (deliveryBusy.value) return;
    final orderId = currentOrder.value?['id'];
    deliveryBusy.value = true;
    try {
      if (await checklist.start() &&
          !isClosed &&
          currentOrder.value?['id'] == orderId) {
        // STARTED/on_the_way was validated from the server response. A later
        // refresh failure must not erase that confirmation or escape unhandled.
        currentOrder.value = {
          ...currentOrder.value!,
          'order_status': checklist.orderStatus.value,
        };
        unawaited(_refreshRequests());
      }
    } finally {
      if (!isClosed) deliveryBusy.value = false;
    }
  }

  Future<bool> verifyOtpAndDeliver(String enteredOtp) async {
    final order = currentOrder.value;
    if (order == null || order['id'] is! int || deliveryBusy.value) {
      return false;
    }
    if (!deliveryOtp.begin(order['id'] as int)) return false;
    final confirmed = await deliveryOtp.verify(enteredOtp);
    if (!confirmed || isClosed) return false;
    HapticFeedback.mediumImpact();
    if (currentOrder.value?['id'] == order['id']) {
      currentOrder.value = null;
    }
    unawaited(loadEarnings());
    return true;
  }

  Future<void> acceptTailoring(Map<String, dynamic> request) async {
    if (deliveryBusy.value) return;
    if (currentOrder.value != null) {
      Get.snackbar(
        "Ongoing Delivery".tr,
        "Please complete your current order first.".tr,
      );
      return;
    }
    final account = _supabase.auth.currentUser?.id;
    if (account == null) return;
    final nextStatus = request['status'] == 'pickup_requested'
        ? 'picked_up_from_customer'
        : 'picked_up_from_tailor';
    deliveryBusy.value = true;
    try {
      final row = await _supabase
          .rpc(
            'optional_tailoring_status',
            params: {'p_id': request['id'], 'p_status': nextStatus},
          )
          .timeout(const Duration(seconds: 20));
      if (isClosed || _supabase.auth.currentUser?.id != account) return;
      if (row is! Map ||
          row['id'] != request['id'] ||
          row['status'] != nextStatus ||
          row['rider_id'] is! int) {
        throw StateError('Pickup was not confirmed');
      }
      currentOrder.value = {
        ...Map<String, dynamic>.from(row),
        'type': 'tailoring',
      };
      Get.snackbar("Accepted".tr, "Please proceed with the pickup.".tr);
    } catch (_) {
      if (!isClosed)
        Get.snackbar("Error".tr, "Could not accept tailoring request.".tr);
    } finally {
      if (!isClosed) deliveryBusy.value = false;
    }
  }

  Future<void> markDelivered() async {
    final current = currentOrder.value;
    if (current == null || deliveryBusy.value) return;
    if (current['type'] == 'order') {
      Get.snackbar(
        "Delivery".tr,
        "Enter the customer OTP to complete delivery.".tr,
      );
      return;
    }
    if (current['type'] != 'tailoring') return;
    final account = _supabase.auth.currentUser?.id;
    if (account == null) return;
    deliveryBusy.value = true;
    try {
      final nextStatus = current['status'] == 'picked_up_from_customer'
          ? 'delivered_to_tailor'
          : 'completed';
      final row = await _supabase
          .rpc(
            'optional_tailoring_status',
            params: {'p_id': current['id'], 'p_status': nextStatus},
          )
          .timeout(const Duration(seconds: 20));
      if (isClosed || _supabase.auth.currentUser?.id != account) return;
      if (row is! Map ||
          row['id'] != current['id'] ||
          row['status'] != nextStatus) {
        throw StateError('Delivery was not confirmed');
      }
      if (currentOrder.value?['id'] == current['id']) currentOrder.value = null;
      Get.snackbar("Success".tr, "Tailoring delivery complete!".tr);
    } catch (_) {
      if (!isClosed)
        Get.snackbar("Error".tr, "Could not complete delivery.".tr);
    } finally {
      if (!isClosed) deliveryBusy.value = false;
    }
  }

  Future<void> setOnlineStatus(bool status) async {
    if (status) {
      await location.allowIdlePermission();
    } else {
      await location.stop();
    }
    await _presence.setOnline(status);
    _queueRefresh();
  }

  Future<void> restoreOnlineStatus() async {
    await _presence.restore();
    _queueRefresh();
  }

  Future<void> retryRequests() => _refreshRequests();

  Future<void> goOffline() async {
    await location.stop();
    await _presence.offline();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      return;
    }
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.detached ||
        (state == AppLifecycleState.paused && !location.sharing.value)) {
      unawaited(goOffline());
    } else if (state == AppLifecycleState.resumed) {
      if (location.sharing.value) {
        _queueRefresh();
      } else {
        unawaited(restoreOnlineStatus());
      }
    }
    _syncLocation();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(goOffline());
    _presence.dispose();
    _locationWorker?.dispose();
    location.onClose();
    deliveryOtp.dispose();
    checklist.dispose();
    _refreshTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    if (_dashboardChannel != null) {
      unawaited(_supabase.removeChannel(_dashboardChannel!));
    }
    super.onClose();
  }
}
