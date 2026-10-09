import 'dart:math';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RiderController extends GetxController {
  final _supabase = Supabase.instance.client;

  RxList<Map<String, dynamic>> availableOrders = <Map<String, dynamic>>[].obs;
  RxList<Map<String, dynamic>> availableTailoring = <Map<String, dynamic>>[].obs;
  Rx<Map<String, dynamic>?> currentOrder = Rx<Map<String, dynamic>?>(null);
  RxBool isOnline = true.obs;

  RxString todayEarnings   = 'PKR 0'.obs;
  RxString weeklyEarnings  = 'PKR 0'.obs;
  RxString monthlyEarnings = 'PKR 0'.obs;
  RxInt tripsToday       = 0.obs;
  RxInt totalDeliveries  = 0.obs;

  @override
  void onInit() {
    super.onInit();
    listenToOrders();
    listenToTailoringRequests();
    checkCurrentOrder();
    loadEarnings();
  }

  Future<void> loadEarnings() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final userRecord = await _supabase.from('users').select('id').eq('email', user.email!).maybeSingle();
    if (userRecord == null) return;
    final riderId = userRecord['id'];

    try {
      final now = DateTime.now();
      final todayStart  = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
      final weekStart   = now.subtract(const Duration(days: 7)).toUtc().toIso8601String();
      final monthStart  = now.subtract(const Duration(days: 30)).toUtc().toIso8601String();

      final delivered = await _supabase
          .from('orders')
          .select('amount, created_at')
          .eq('rider_id', riderId)
          .eq('order_status', 'delivered') as List;

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

      todayEarnings.value   = 'PKR ${todayTotal.toStringAsFixed(0)}';
      weeklyEarnings.value  = 'PKR ${weekTotal.toStringAsFixed(0)}';
      monthlyEarnings.value = 'PKR ${monthTotal.toStringAsFixed(0)}';
      tripsToday.value      = todayTrips;
      totalDeliveries.value = delivered.length;
    } catch (_) {}
  }

  void listenToOrders() {
    // Stream all orders and filter client-side:
    // Show 'placed' (vendor not yet accepted) and 'accepted' (vendor accepted, ready for pickup)
    // where no rider has been assigned yet.
    _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .listen((data) {
      availableOrders.value = data
          .where((o) =>
              (o['order_status'] == 'placed' || o['order_status'] == 'accepted') &&
              o['rider_id'] == null)
          .toList();
      availableOrders.sort((a, b) =>
          (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
    });
  }

  void listenToTailoringRequests() {
    _supabase
        .from('tailoring_requests')
        .stream(primaryKey: ['id'])
        .listen((data) {
      availableTailoring.value = data
          .where((o) => o['status'] == 'pickup_requested' || o['status'] == 'ready_for_customer')
          .toList();
      availableTailoring.sort((a, b) =>
          (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
    });
  }

  Future<void> checkCurrentOrder() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final userRecord = await _supabase.from('users').select('id').eq('email', user.email!).maybeSingle();
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

    _supabase.from('users').select('id').eq('email', user.email!).maybeSingle().then((rec) async {
      if (rec != null) {
        final tailorData = await _supabase
            .from('tailoring_requests')
            .select()
            .eq('rider_id', rec['id'])
            .inFilter('status', ['picked_up_from_customer', 'picked_up_from_tailor'])
            .maybeSingle();

        if (tailorData != null) {
          currentOrder.value = {...tailorData, 'type': 'tailoring'};
        }
      }
    });
  }

  Future<void> acceptOrder(Map<String, dynamic> order) async {
    if (currentOrder.value != null) {
      Get.snackbar('Ongoing Delivery', 'Please complete your current order first.',
          backgroundColor: Get.theme.colorScheme.error, colorText: Get.theme.colorScheme.onError);
      return;
    }
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final userRecord = await _supabase.from('users').select('id').eq('email', user.email!).maybeSingle();
      if (userRecord == null) return;
      final otp = (100000 + Random().nextInt(900000)).toString();
      await _supabase.from('orders').update({
        'rider_id': userRecord['id'],
        'order_status': 'on_the_way',
        'delivery_otp': otp,
      }).eq('id', order['id']);

      currentOrder.value = {...order, 'type': 'order', 'delivery_otp': otp};
      Get.snackbar('Order Accepted', 'Navigate to the customer now.',
          backgroundColor: Get.theme.colorScheme.primary, colorText: Get.theme.colorScheme.onPrimary);
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

      await _supabase.from('orders').update({
        'order_status': 'delivered',
      }).eq('id', current['id']);

      try {
        await _supabase.from('delivery_proof').insert({
          'proofid':      'proof_${DateTime.now().millisecondsSinceEpoch}',
          'orderid':      current['id'].toString(),
          'riderid':      _supabase.auth.currentUser?.id ?? '',
          'photourl':     '',
          'location':     '',
          'otpconfirmed': true,
          'otp':          enteredOtp,
          'is_verified':  true,
          'verified_at':  DateTime.now().toUtc().toIso8601String(),
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
      Get.snackbar('Ongoing Delivery', 'Please complete your current order first.');
      return;
    }
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final userRecord = await _supabase.from('users').select('id').eq('email', user.email!).maybeSingle();
      if (userRecord == null) return;

      String nextStatus = request['status'] == 'pickup_requested'
          ? 'picked_up_from_customer'
          : 'picked_up_from_tailor';

      await _supabase.from('tailoring_requests').update({
        'rider_id': userRecord['id'],
        'status': nextStatus
      }).eq('id', request['id']);

      currentOrder.value = {...request, 'status': nextStatus, 'type': 'tailoring'};
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
        await _supabase.from('orders').update({
          'order_status': 'delivered'
        }).eq('id', current['id']);
        Get.snackbar('Success', 'Order marked as delivered!');
      } else if (current['type'] == 'tailoring') {
        String nextStatus = current['status'] == 'picked_up_from_customer'
            ? 'delivered_to_tailor'
            : 'completed';
        await _supabase.from('tailoring_requests').update({
          'status': nextStatus
        }).eq('id', current['id']);
        Get.snackbar('Success', 'Tailoring delivery complete!');
      }
      currentOrder.value = null;
    } catch (e) {
      Get.snackbar('Error', 'Could not complete delivery.');
    }
  }

  void setOnlineStatus(bool status) {
    isOnline.value = status;
  }
}
