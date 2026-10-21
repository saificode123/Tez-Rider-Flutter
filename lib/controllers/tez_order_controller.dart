import 'package:get/get.dart';

class TezOrderController extends GetxController {
  RxBool isSearching = false.obs;
  RxString status = ''.obs;

  Future<void> placeOrder({
    required double lat,
    required double lng,
    required double fare,
  }) async {
    // Standalone booking has no trusted checkout/assignment contract yet.
    // Never create an incomplete order or infer assignment from an INSERT.
    status.value = 'Instant rider booking is unavailable.';
    Get.snackbar(
      'Booking unavailable',
      'Please use product checkout. No rider has been assigned.',
    );
  }
}
