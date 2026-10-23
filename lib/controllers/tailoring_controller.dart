import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TailoringController extends GetxController {
  final _supabase = Supabase.instance.client;
  var isSubmitting = false.obs;

  Future<bool> submitRequest({
    required String instructions,
    required Map<String, dynamic> measurements,
  }) async {
    if (isSubmitting.value) return false;
    isSubmitting.value = true;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final userRecord = await _supabase.from('users').select('id').eq('auth_user_id', user.id).maybeSingle();
      if (userRecord == null) throw Exception('User ID not found');

      await _supabase.from('tailoring_requests').insert({
        'customer_id': userRecord['id'],
        'instructions': instructions,
        'measurements': measurements,
        'status': 'pickup_requested',
      }).select('id').single();
      
      Get.snackbar('Request saved', 'Rider assignment has not been confirmed.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return true;
    } catch (e) {
      Get.snackbar('Not saved', 'The tailoring request was not confirmed. Please retry.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }
}
