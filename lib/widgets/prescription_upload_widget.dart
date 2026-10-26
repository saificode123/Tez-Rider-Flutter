import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../controllers/prescription_controller.dart';
import '../services/optional_media_service.dart';

typedef PrescriptionPicker = Future<Uint8List?> Function(ImageSource source);

class PrescriptionUploadWidget extends StatefulWidget {
  const PrescriptionUploadWidget({
    super.key,
    required this.vendorOrderId,
    required this.customerId,
    this.onUploadSuccess,
    this.onUploadFailed,
    this.controller,
    this.media,
    this.picker,
  });
  final String vendorOrderId, customerId;
  final VoidCallback? onUploadSuccess, onUploadFailed;
  final PrescriptionController? controller;
  final OptionalMediaService? media;
  final PrescriptionPicker? picker;
  @override
  State<PrescriptionUploadWidget> createState() =>
      _PrescriptionUploadWidgetState();
}

class _PrescriptionUploadWidgetState extends State<PrescriptionUploadWidget> {
  late final PrescriptionController controller =
      widget.controller ??
      (Get.isRegistered<PrescriptionController>()
          ? Get.find<PrescriptionController>()
          : Get.put(PrescriptionController()));
  late final OptionalMediaService media =
      widget.media ??
      OptionalMediaService(
        kind: 'prescription',
        orderId: int.tryParse(widget.vendorOrderId),
      );
  Uint8List? image;
  String? reference, error;
  bool busy = false, done = false;

  Future<void> pick(ImageSource source) async {
    if (busy || done || media.hasPendingUpload) return;
    try {
      final bytes = widget.picker != null
          ? await widget.picker!(source)
          : await (await ImagePicker().pickImage(
              source: source,
              maxWidth: 1600,
              imageQuality: 85,
            ))?.readAsBytes();
      if (!mounted || bytes == null) return;
      setState(() {
        image = bytes;
        reference = null;
        error = null;
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Image selection failed. Retry.');
    }
  }

  Future<void> upload() async {
    if (busy || done || image == null) return;
    if (int.tryParse(widget.vendorOrderId) == null) {
      setState(
        () => error = 'Place the order first, then upload from its details.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      reference ??= await media.upload(image!);
      final saved = await controller.uploadPrescription(
        vendorOrderId: widget.vendorOrderId,
        customerId: widget.customerId,
        prescriptionImageUrl: reference!,
      );
      if (!mounted) return;
      if (!saved) throw StateError('Unconfirmed prescription');
      setState(() {
        done = true;
        image = null;
      });
      widget.onUploadSuccess?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Prescription was not confirmed. Retry the same image.',
        );
        widget.onUploadFailed?.call();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prescription'.tr,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            (done
                    ? 'Prescription uploaded. Waiting for vendor review.'
                    : 'Upload a clear JPEG or PNG prescription, up to 5 MB.')
                .tr,
          ),
          if (image != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Image.memory(
                image!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
          if (!done) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: busy || media.hasPendingUpload
                      ? null
                      : () => pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text('Take Photo'.tr),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: busy || media.hasPendingUpload
                      ? null
                      : () => pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text('From Gallery'.tr),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: busy || image == null ? null : upload,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text((busy ? 'Uploading...' : 'Upload Prescription').tr),
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!.tr,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}
