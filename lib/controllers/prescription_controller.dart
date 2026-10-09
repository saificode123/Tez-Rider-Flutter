import 'package:get/get.dart';
import '../models/prescription_model.dart';
import '../services/prescription_service.dart';

class PrescriptionController extends GetxController {
  final prescriptionService = PrescriptionService();

  var prescriptions = <PrescriptionModel>[].obs;
  var currentPrescription = Rx<PrescriptionModel?>(null);
  var isLoading = false.obs;
  var isUploading = false.obs;
  var pendingPrescriptions = <Map<String, dynamic>>[].obs;

  /// Upload prescription
  Future<bool> uploadPrescription({
    required String vendorOrderId,
    required String customerId,
    required String prescriptionImageUrl,
  }) async {
    try {
      isUploading.value = true;
      final result = await prescriptionService.uploadPrescription(
        vendorOrderId: vendorOrderId,
        customerId: customerId,
        prescriptionImageUrl: prescriptionImageUrl,
      );

      if (result != null) {
        currentPrescription.value = result;
        return true;
      }
      return false;
    } catch (e) {
      print('PrescriptionController uploadPrescription error: $e');
      return false;
    } finally {
      isUploading.value = false;
    }
  }

  /// Fetch prescriptions for customer
  Future<void> fetchCustomerPrescriptions(String customerId) async {
    try {
      isLoading.value = true;
      final presc = await prescriptionService.getPrescriptionsByCustomer(customerId);
      prescriptions.value = presc;
    } catch (e) {
      print('PrescriptionController fetchCustomerPrescriptions error: $e');
      prescriptions.value = [];
    } finally {
      isLoading.value = false;
    }
  }

  /// Fetch pending prescriptions for vendor
  Future<void> fetchPendingPrescriptions(String vendorId) async {
    try {
      isLoading.value = true;
      final pending = await prescriptionService.getPendingPrescriptionsForVendor(vendorId);
      pendingPrescriptions.value = pending;
    } catch (e) {
      print('PrescriptionController fetchPendingPrescriptions error: $e');
      pendingPrescriptions.value = [];
    } finally {
      isLoading.value = false;
    }
  }

  /// Approve prescription
  Future<bool> approvePrescription(
    String prescriptionId,
    String vendorId, {
    String? notes,
  }) async {
    try {
      isLoading.value = true;
      final result = await prescriptionService.approvePrescription(
        prescriptionId,
        vendorId,
        notes,
      );
      if (result) {
        // Refresh pending prescriptions
        final vendorIdStr = vendorId.toString();
        await fetchPendingPrescriptions(vendorIdStr);
      }
      return result;
    } catch (e) {
      print('PrescriptionController approvePrescription error: $e');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Reject prescription
  Future<bool> rejectPrescription(
    String prescriptionId,
    String vendorId,
    String reason,
  ) async {
    try {
      isLoading.value = true;
      final result = await prescriptionService.rejectPrescription(
        prescriptionId,
        vendorId,
        reason,
      );
      if (result) {
        // Refresh pending prescriptions
        final vendorIdStr = vendorId.toString();
        await fetchPendingPrescriptions(vendorIdStr);
      }
      return result;
    } catch (e) {
      print('PrescriptionController rejectPrescription error: $e');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Check if prescription is approved
  bool isPrescriptionApproved(String? vendorOrderId) {
    if (vendorOrderId == null) return false;
    final presc = prescriptions.firstWhereOrNull(
      (p) => p.vendorOrderId == vendorOrderId,
    );
    return presc?.isApproved ?? false;
  }

  /// Check if prescription is pending
  bool isPrescriptionPending(String? vendorOrderId) {
    if (vendorOrderId == null) return false;
    final presc = prescriptions.firstWhereOrNull(
      (p) => p.vendorOrderId == vendorOrderId,
    );
    return presc?.isPending ?? false;
  }

  /// Check if prescription is rejected
  bool isPrescriptionRejected(String? vendorOrderId) {
    if (vendorOrderId == null) return false;
    final presc = prescriptions.firstWhereOrNull(
      (p) => p.vendorOrderId == vendorOrderId,
    );
    return presc?.isRejected ?? false;
  }

  /// Clear prescription data
  void clearPrescriptionData() {
    currentPrescription.value = null;
    prescriptions.value = [];
    pendingPrescriptions.value = [];
  }
}
