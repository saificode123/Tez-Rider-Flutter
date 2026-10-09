import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TailoringController extends GetxController {
  final _supabase = Supabase.instance.client;
  var isSubmitting = false.obs;

  Future<bool> submitRequest({
    required String instructions,
    required Map<String, dynamic> measurements,
  }) async {
    isSubmitting.value = true;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final userRecord = await _supabase.from('users').select('id').eq('email', user.email!).maybeSingle();
      if (userRecord == null) throw Exception('User ID not found');

      await _supabase.from('tailoring_requests').insert({
        'customer_id': userRecord['id'],
        'instructions': instructions,
        'measurements': measurements,
        'status': 'pickup_requested',
      });
      
      Get.snackbar('Success 🎉', 'A rider will be assigned to pick up your cloth soon!',
        snackPosition: SnackPosition.BOTTOM,
      );
      return true;
    } catch (e) {
      Get.snackbar('Error', 'Failed to request tailoring: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }
}