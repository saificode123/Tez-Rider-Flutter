import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

class TezOrderController extends GetxController {
  final supabase = Supabase.instance.client;
  RxBool isSearching = false.obs;
  RxString status = ''.obs;

  Future<void> placeOrder({
    required double lat,
    required double lng,
    required double fare,
  }) async {
    isSearching.value = true;
    status.value = 'Finding nearest rider...';
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        Get.snackbar('Error', 'Not logged in');
        return;
      }
      await supabase.from('orders').insert({
        'user_id': user.id,
        'pickup_lat': lat,
        'pickup_lng': lng,
        'fare': fare,
        'order_status': 'searching',
        'payment_method': 'COD',
        'payment_status': 'pending',
      });
      status.value = 'Rider found!';
      Get.snackbar('Success', 'Rider is on the way!',
          backgroundColor: const Color(0xFF1B5E20),
          colorText: const Color(0xFFFFFFFF));
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isSearching.value = false;
    }
  }
}