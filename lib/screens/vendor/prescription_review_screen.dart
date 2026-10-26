import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/private_photo.dart';
import '../../services/optional_media_service.dart';
import '../../controllers/prescription_controller.dart';

class VendorPrescriptionReviewScreen extends StatefulWidget {
  final String vendorId;

  const VendorPrescriptionReviewScreen({super.key, required this.vendorId});

  @override
  State<VendorPrescriptionReviewScreen> createState() =>
      _VendorPrescriptionReviewScreenState();
}

class _VendorPrescriptionReviewScreenState
    extends State<VendorPrescriptionReviewScreen> {
  final PrescriptionController _prescriptionController =
      Get.isRegistered<PrescriptionController>()
      ? Get.find<PrescriptionController>()
      : Get.put(PrescriptionController());
  final TextEditingController _rejectionReasonController =
      TextEditingController();

  static const _purple = Color(0xFF1B5E20);

  @override
  void initState() {
    super.initState();
    _prescriptionController.clearPrescriptionData();
    _fetchPendingPrescriptions();
  }

  Future<void> _fetchPendingPrescriptions() async {
    await _prescriptionController.fetchPendingPrescriptions(widget.vendorId);
  }

  void _showApprovalDialog(String prescriptionId) {
    Get.dialog(
      AlertDialog(
        title: Text('Approve Prescription'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add notes (optional):'.tr,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rejectionReasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add any notes about this prescription'.tr,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('Cancel'.tr)),
          Obx(
            () => ElevatedButton(
              onPressed: _prescriptionController.isLoading.value
                  ? null
                  : () async {
                      final success = await _prescriptionController
                          .approvePrescription(
                            prescriptionId,
                            widget.vendorId,
                            notes: _rejectionReasonController.text.trim(),
                          );

                      if (success) {
                        _rejectionReasonController.clear();
                        Get.back();
                        Get.snackbar(
                          'Success',
                          'Prescription approved successfully',
                          backgroundColor: Colors.green,
                          colorText: Colors.white,
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                disabledBackgroundColor: _purple.withValues(alpha: 0.5),
              ),
              child: _prescriptionController.isLoading.value
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text('Approve'.tr),
            ),
          ),
        ],
      ),
    );
  }

  void _showRejectionDialog(String prescriptionId) {
    Get.dialog(
      AlertDialog(
        title: Text('Reject Prescription'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reason for rejection:'.tr,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rejectionReasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'Provide a clear reason (e.g., "Prescription is expired" or "Not clearly visible")'
                        .tr,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('Cancel'.tr)),
          Obx(
            () => ElevatedButton(
              onPressed:
                  _prescriptionController.isLoading.value ||
                      _rejectionReasonController.text.isEmpty
                  ? null
                  : () async {
                      final success = await _prescriptionController
                          .rejectPrescription(
                            prescriptionId,
                            widget.vendorId,
                            _rejectionReasonController.text.trim(),
                          );

                      if (success) {
                        _rejectionReasonController.clear();
                        Get.back();
                        Get.snackbar(
                          'Rejected',
                          'Prescription rejection saved',
                          backgroundColor: Colors.orange,
                          colorText: Colors.white,
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                disabledBackgroundColor: Colors.red.withValues(alpha: 0.5),
              ),
              child: _prescriptionController.isLoading.value
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text('Reject'.tr),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Text(
          'Prescription Reviews'.tr,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A0533),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A0533)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPendingPrescriptions,
          ),
        ],
      ),
      body: Obx(() {
        if (_prescriptionController.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_prescriptionController.error.value != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_prescriptionController.error.value!.tr),
                TextButton(
                  onPressed: _fetchPendingPrescriptions,
                  child: Text('Retry'.tr),
                ),
              ],
            ),
          );
        }

        if (_prescriptionController.pendingPrescriptions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Pending Prescriptions'.tr,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'All prescriptions have been reviewed'.tr,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _prescriptionController.pendingPrescriptions.length,
          itemBuilder: (context, index) {
            final prescription =
                _prescriptionController.pendingPrescriptions[index];
            final prescriptionId = prescription['id']?.toString() ?? '';
            final imageUrl = prescription['prescription_image_url'] ?? '';
            final uploadedAt = prescription['uploaded_at'] != null
                ? DateTime.parse(prescription['uploaded_at'])
                : null;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prescription Image
                  if (imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: PrivatePhoto(
                        imageUrl: imageUrl,
                        service: OptionalMediaService(),
                        accountChanges: Supabase
                            .instance
                            .client
                            .auth
                            .onAuthStateChange
                            .map((_) {}),
                        width: double.infinity,
                        height: 250,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 250,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 250,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(
                              Icons.broken_image,
                              size: 60,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Details
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Status'.tr,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: Text(
                                'Pending Review'.tr,
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (uploadedAt != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Uploaded: ${uploadedAt.toString().split('.')[0]}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _showApprovalDialog(prescriptionId),
                                icon: const Icon(Icons.check_circle),
                                label: Text('Approve'.tr),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _purple,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _showRejectionDialog(prescriptionId),
                                icon: const Icon(Icons.cancel),
                                label: Text('Reject'.tr),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }

  @override
  void dispose() {
    _rejectionReasonController.dispose();
    super.dispose();
  }
}
