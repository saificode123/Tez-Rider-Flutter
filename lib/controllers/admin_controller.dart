import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/order_model.dart';

class AdminController extends GetxController {
  final _supabase = Supabase.instance.client;

  var riders = <UserModel>[].obs;
  var vendors = <UserModel>[].obs;
  var orders = <OrderModel>[].obs;
  var disputes = <Map<String, dynamic>>[].obs;

  var isLoading = true.obs;
  final pendingRiders = <UserModel>[].obs;
  final hasMoreRiders = false.obs;
  final hasMorePending = false.obs;
  final hasMoreVendors = false.obs;
  final activeRiderCount = RxnInt();
  final approvalError = RxnString();
  final reviewing = RxnString();
  bool _approvalLoading = false;
  StreamSubscription<dynamic>? _ordersSubscription;
  StreamSubscription<dynamic>? _disputesSubscription;

  @override
  void onInit() {
    super.onInit();
    _listenToUsers();
    _listenToOrders();
    _listenToDisputes();
  }

  void _listenToUsers() {
    unawaited(refreshApprovals());
  }

  Future<void> refreshApprovals() async {
    if (_approvalLoading || isClosed) return;
    _approvalLoading = true;
    isLoading.value = true;
    try {
      await Future.wait([
        _fetchRiders(),
        _fetchRiders(pending: true),
        _fetchVendors(),
        _fetchActiveRiderCount(),
      ]);
      if (!isClosed) approvalError.value = null;
    } catch (_) {
      if (!isClosed) {
        approvalError.value = 'Could not load approvals. Tap Retry.';
      }
    } finally {
      _approvalLoading = false;
      if (!isClosed) isLoading.value = false;
    }
  }

  Future<void> _fetchActiveRiderCount() async {
    try {
      final count = await _supabase
          .from('users')
          .count()
          .eq('role', 'rider')
          .eq('verification_status', 'approved')
          .timeout(const Duration(seconds: 10));
      if (!isClosed) activeRiderCount.value = count;
    } catch (_) {
      if (!isClosed) activeRiderCount.value = null;
    }
  }

  Future<void> _fetchRiders({bool pending = false, bool append = false}) async {
    final list = pending ? pendingRiders : riders;
    final result = await _supabase
        .rpc(
          'fr04_admin_riders',
          params: {
            'p_limit': 30,
            'p_status': pending ? 'pending' : null,
            'p_before': append && list.isNotEmpty
                ? int.parse(list.last.id)
                : null,
          },
        )
        .timeout(const Duration(seconds: 10));
    if (isClosed) return;
    final values = (result as List)
        .map((r) => UserModel.fromJson(Map<String, dynamic>.from(r)))
        .toList();
    if (append) {
      final ids = list.map((u) => u.id).toSet();
      list.addAll(values.where((u) => !ids.contains(u.id)));
    } else {
      list.assignAll(values);
    }
    (pending ? hasMorePending : hasMoreRiders).value = values.length == 30;
  }

  Future<void> _fetchVendors({bool append = false}) async {
    var query = _supabase
        .from('users')
        .select(
          'id,name,email,role,verification_status,phone,profile_image,rejection_reason',
        )
        .eq('role', 'vendor');
    if (append && vendors.isNotEmpty) {
      query = query.lt('id', int.parse(vendors.last.id));
    }
    final result = await query
        .order('id', ascending: false)
        .limit(30)
        .timeout(const Duration(seconds: 10));
    if (isClosed) return;
    final values = result.map(UserModel.fromJson).toList();
    if (append) {
      vendors.addAll(values);
    } else {
      vendors.assignAll(values);
    }
    hasMoreVendors.value = values.length == 30;
  }

  Future<void> loadMore({bool pending = false, bool vendor = false}) async {
    if (_approvalLoading || isClosed) return;
    _approvalLoading = true;
    isLoading.value = true;
    try {
      if (vendor) {
        await _fetchVendors(append: true);
      } else {
        await _fetchRiders(pending: pending, append: true);
      }
    } catch (_) {
      if (!isClosed) {
        approvalError.value = 'Could not load more approvals. Retry.';
      }
    } finally {
      _approvalLoading = false;
      if (!isClosed) isLoading.value = false;
    }
  }

  void _listenToOrders() {
    _ordersSubscription = _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .listen(
          (data) {
            orders.value = data.map((e) => OrderModel.fromJson(e)).toList();
          },
          onError: (error) {
            debugPrint('Error listening to orders: $error');
          },
        );
  }

  void _listenToDisputes() {
    _disputesSubscription = _supabase
        .from('disputes')
        .stream(primaryKey: ['id'])
        .listen(
          (data) {
            disputes.value = List<Map<String, dynamic>>.from(data);
          },
          onError: (error) {
            debugPrint(
              'Error listening to disputes, maybe table doesn\'t exist yet: $error',
            );
            disputes.value = [
              {
                'id': '#D-041',
                'type': 'Late Delivery',
                'by': 'Customer',
                'status': 'Open',
                'date': 'Today',
              },
              {
                'id': '#D-040',
                'type': 'Wrong Item',
                'by': 'Customer',
                'status': 'Resolved',
                'date': 'Yesterday',
              },
            ];
          },
        );
  }

  Future<void> updateStatus(String table, String id, String newStatus) async {
    if (reviewing.value != null) return;
    reviewing.value = id;
    try {
      if (table == 'users') {
        if (riders.any((u) => u.id == id) ||
            pendingRiders.any((u) => u.id == id)) {
          final result = await _supabase
              .rpc(
                'fr04_review_rider',
                params: {'p_user_id': int.parse(id), 'p_status': newStatus},
              )
              .timeout(const Duration(seconds: 10));
          if (result['verification_status'] != newStatus) {
            throw StateError('Review not confirmed');
          }
        } else {
          final changed = await _supabase
              .from(table)
              .update({'verification_status': newStatus})
              .eq('id', id)
              .select('id,verification_status')
              .single()
              .timeout(const Duration(seconds: 10));
          if (changed['verification_status'] != newStatus) {
            throw StateError('Review not confirmed');
          }
        }

        // Update the local list immediately — don't wait for a Realtime
        // event, which may be delayed or never arrive if the table isn't
        // in the Supabase Realtime publication.
        riders.value = riders
            .map(
              (u) => u.id == id ? u.copyWith(verificationStatus: newStatus) : u,
            )
            .toList();
        vendors.value = vendors
            .map(
              (u) => u.id == id ? u.copyWith(verificationStatus: newStatus) : u,
            )
            .toList();
        pendingRiders.removeWhere((u) => u.id == id);
        unawaited(_fetchActiveRiderCount());
      } else {
        await _supabase.from(table).update({'status': newStatus}).eq('id', id);
      }
      Get.snackbar('Success', 'Status updated to $newStatus');
    } catch (e) {
      Get.snackbar('Error', 'Failed to update status');
    } finally {
      if (!isClosed) reviewing.value = null;
    }
  }

  @override
  void onClose() {
    unawaited(_ordersSubscription?.cancel());
    unawaited(_disputesSubscription?.cancel());
    super.onClose();
  }
}
