import 'package:get/get.dart';
import '../services/tailoring_service.dart';

class TailoringController extends GetxController {
  TailoringController({TailoringService? service})
    : _service = service ?? TailoringService();
  final TailoringService _service;
  final isSubmitting = false.obs;
  Future<bool> submitRequest({
    required String instructions,
    required Map<String, dynamic> measurements,
    String? reference,
  }) async {
    if (isSubmitting.value) return false;
    isSubmitting.value = true;
    try {
      await _service.submit(
        instructions: instructions,
        measurements: measurements,
        reference: reference,
      );
      Get.snackbar(
        'Request saved'.tr,
        'Rider assignment has not been confirmed.'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return true;
    } catch (_) {
      Get.snackbar(
        'Not saved'.tr,
        'The tailoring request was not confirmed. Please retry.'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    } finally {
      if (!isClosed) isSubmitting.value = false;
    }
  }
}
