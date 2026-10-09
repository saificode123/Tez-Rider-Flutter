import 'package:flutter/foundation.dart';
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

  @override
  void onInit() {
    super.onInit();
    _listenToUsers();
    _listenToOrders();
    _listenToDisputes();
  }

  void _listenToUsers() {
    _supabase.from('users').stream(primaryKey: ['id']).listen((data) {
      final List<UserModel> allUsers = data.map((e) => UserModel.fromJson(e)).toList();

      riders.value = allUsers.where((u) => u.role == 'rider').toList();
      vendors.value = allUsers.where((u) => u.role == 'vendor').toList();

      isLoading.value = false;
    }, onError: (error) {
      debugPrint('Error listening to users: $error');
      isLoading.value = false;
    });
  }

  void _listenToOrders() {
    _supabase.from('orders').stream(primaryKey: ['id']).listen((data) {
      orders.value = data.map((e) => OrderModel.fromJson(e)).toList();
    }, onError: (error) {
      debugPrint('Error listening to orders: $error');
    });
  }

  void _listenToDisputes() {
    _supabase.from('disputes').stream(primaryKey: ['id']).listen((data) {
      disputes.value = List<Map<String, dynamic>>.from(data);
    }, onError: (error) {
      debugPrint('Error listening to disputes, maybe table doesn\'t exist yet: $error');
      disputes.value = [
        {'id': '#D-041', 'type': 'Late Delivery', 'by': 'Customer', 'status': 'Open', 'date': 'Today'},
        {'id': '#D-040', 'type': 'Wrong Item', 'by': 'Customer', 'status': 'Resolved', 'date': 'Yesterday'},
      ];
    });
  }

  Future<void> updateStatus(String table, String id, String newStatus) async {
    try {
      if (table == 'users') {
        await _supabase.from(table).update({'verification_status': newStatus}).eq('id', id);

        // Update the local list immediately — don't wait for a Realtime
        // event, which may be delayed or never arrive if the table isn't
        // in the Supabase Realtime publication.
        riders.value = riders.map((u) => u.id == id ? u.copyWith(verificationStatus: newStatus) : u).toList();
        vendors.value = vendors.map((u) => u.id == id ? u.copyWith(verificationStatus: newStatus) : u).toList();
      } else {
        await _supabase.from(table).update({'status': newStatus}).eq('id', id);
      }
      Get.snackbar('Success', 'Status updated to $newStatus');
    } catch (e) {
      Get.snackbar('Error', 'Failed to update status');
    }
  }
}