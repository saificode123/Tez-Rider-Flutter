import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../controllers/prescription_controller.dart';
import '../../services/storage_service.dart';

class PrescriptionUploadWidget extends StatefulWidget {
  final String vendorOrderId;
  final String customerId;
  final VoidCallback? onUploadSuccess;
  final VoidCallback? onUploadFailed;

  const PrescriptionUploadWidget({
    super.key,
    required this.vendorOrderId,
    required this.customerId,
    this.onUploadSuccess,
    this.onUploadFailed,
  });

  @override
  State<PrescriptionUploadWidget> createState() =>
      _PrescriptionUploadWidgetState();
}

class _PrescriptionUploadWidgetState extends State<PrescriptionUploadWidget> {
  final ImagePicker _imagePicker = ImagePicker();
  final PrescriptionController _prescriptionController =
      Get.find<PrescriptionController>();
  final StorageService _storageService = StorageService();

  File? _selectedImage;
  XFile? _imageFile;

  static const _purple = Color(0xFF1B5E20);

  Future<void> _pickImage() async {
    try {
      final XFile? image =
          await _imagePicker.pickImage(source: ImageSource.camera);

      if (image != null) {
        setState(() {
          _imageFile = image;
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to pick image: $e');
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image =
          await _imagePicker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        setState(() {
          _imageFile = image;
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to pick image: $e');
    }
  }

  Future<void> _uploadPrescription() async {
    if (_selectedImage == null || _imageFile == null) {
      Get.snackbar('Error', 'Please select a prescription image');
      return;
    }

    try {
      // Upload image to Supabase Storage
      final prescriptionUrl = await _storageService.uploadPrescriptionImage(
        imageFile: _selectedImage!,
        customerId: widget.customerId,
        vendorOrderId: widget.vendorOrderId,
      );

      if (prescriptionUrl == null) {
        Get.snackbar('Error', 'Failed to upload image to storage');
        return;
      }

      // Save prescription record with image URL
      final success = await _prescriptionController.uploadPrescription(
        vendorOrderId: widget.vendorOrderId,
        customerId: widget.customerId,
        prescriptionImageUrl: prescriptionUrl,
      );

      if (success) {
        Get.snackbar(
          'Success',
          'Prescription uploaded successfully! Waiting for vendor review.',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
        widget.onUploadSuccess?.call();
      } else {
        Get.snackbar('Error', 'Failed to upload prescription');
        widget.onUploadFailed?.call();
      }
    } catch (e) {
      Get.snackbar('Error', 'Error uploading prescription: $e');
      widget.onUploadFailed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, color: _purple, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Prescription Required',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Please upload a valid prescription for medicines',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_selectedImage != null)
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Image.file(
                  _selectedImage!,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _purple.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  color: _purple.withValues(alpha: 0.05),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_outlined,
                        size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'No prescription selected',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade300,
                      foregroundColor: Colors.grey.shade800,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImageFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('From Gallery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade300,
                      foregroundColor: Colors.grey.shade800,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Obx(() => SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed:
                    _prescriptionController.isUploading.value ? null : _uploadPrescription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  disabledBackgroundColor: _purple.withValues(alpha: 0.5),
                ),
                child: _prescriptionController.isUploading.value
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Upload Prescription',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}