import 'package:get/get.dart';
import '../models/prescription_model.dart';
import '../services/prescription_service.dart';

class PrescriptionController extends GetxController {
  PrescriptionController({PrescriptionService? service})
    : prescriptionService = service ?? PrescriptionService();
  final PrescriptionService prescriptionService;
  final error = RxnString();

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
    if (isUploading.value) return false;
    try {
      error.value = null;
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
      error.value = 'Prescription operation was not confirmed. Retry.';
      return false;
    } finally {
      isUploading.value = false;
    }
  }

  /// Fetch prescriptions for customer
  Future<void> fetchCustomerPrescriptions(String customerId) async {
    try {
      error.value = null;
      isLoading.value = true;
      final presc = await prescriptionService.getPrescriptionsByCustomer(
        customerId,
      );
      prescriptions.value = presc;
    } catch (e) {
      error.value = 'Prescriptions could not be loaded. Retry.';
      prescriptions.value = [];
    } finally {
      isLoading.value = false;
    }
  }

  /// Fetch pending prescriptions for vendor
  Future<void> fetchPendingPrescriptions(String vendorId) async {
    try {
      error.value = null;
      isLoading.value = true;
      final pending = await prescriptionService
          .getPendingPrescriptionsForVendor(vendorId);
      pendingPrescriptions.value = pending;
    } catch (e) {
      error.value = 'Prescriptions could not be loaded. Retry.';
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
    if (isLoading.value) return false;
    try {
      error.value = null;
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
      error.value = 'Prescription operation was not confirmed. Retry.';
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
    if (isLoading.value) return false;
    try {
      error.value = null;
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
      error.value = 'Prescription operation was not confirmed. Retry.';
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
    error.value = null;
    currentPrescription.value = null;
    prescriptions.value = [];
    pendingPrescriptions.value = [];
  }
}
