import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/auth_controller.dart';
import '../controllers/cnic_document_controller.dart';
import '../services/cnic_document.dart';
import '../theme/app_theme.dart';
import '../widgets/cnic_document_viewer.dart';
import 'rider_dashboard.dart';

class CnicDocumentScreen extends StatefulWidget {
  const CnicDocumentScreen({super.key});
  @override
  State<CnicDocumentScreen> createState() => _CnicDocumentScreenState();
}

class _CnicDocumentScreenState extends State<CnicDocumentScreen> {
  final ctrl = CnicDocumentController();
  final number = TextEditingController();
  final draft = CnicDraftStore();
  String get email => Supabase.instance.client.auth.currentUser?.email ?? '';
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await ctrl.loadStatus();
    if (!mounted) return;
    try {
      final saved = await draft.read(email);
      if (saved != null) {
        // An older valid document does not confirm a failed replacement.
        // Clear only the exact immutable request already confirmed by the server.
        if (cnicDraftWasSubmitted(ctrl.application, saved)) {
          await draft.clear(email);
          return;
        }
        number.text = saved['cnic'] as String;
        ctrl.requestId = saved['request_id'] as String;
        ctrl.prepareRequest(saved['cnic'] as String);
        final restored = await ctrl.images.read(saved['path'] as String);
        if (mounted) ctrl.image.value = restored;
      } else {
        ctrl.image.value = await ctrl.images.lostSelection();
      }
    } catch (_) {
      if (mounted) {
        ctrl.error.value =
            'Select your document again to continue the interrupted submission.';
      }
    }
  }

  Future<void> _submit() async {
    final ownerEmail = email;
    final selected = ctrl.image.value;
    if (selected == null) {
      ctrl.error.value = 'Please select your CNIC document image.';
      return;
    }
    try {
      if (await ctrl.submit(
        number.text.trim(),
        persistDraft: (number, id, image) =>
            draft.save(ownerEmail, number, image.sourcePath, id),
      )) {
        await draft.clear(ownerEmail);
        if (mounted) {
          number.clear();
          ctrl.image.value = null;
        }
      }
    } catch (_) {
      ctrl.error.value = 'Could not save your submission. Please retry.';
    }
  }

  @override
  void dispose() {
    ctrl.onClose();
    number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Rider CNIC verification'),
      actions: [
        IconButton(
          onPressed: () => Get.find<AuthController>().logout(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: Obx(
      () => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (ctrl.application['document_valid'] == true) ...[
            const Icon(Icons.hourglass_top, color: AppColors.warning, size: 48),
            Text(
              ctrl.application['verification_status'] == 'approved'
                  ? 'Your rider account is approved.'
                  : 'Document submitted. Your account is awaiting admin approval.',
            ),
            if (ctrl.application['verification_status'] == 'approved')
              TextButton(
                onPressed: () => Get.offAll(() => const RiderDashboard()),
                child: const Text('Continue to Rider Dashboard'),
              ),
            Text('CNIC: ${ctrl.application['cnic_masked'] ?? 'Protected'}'),
            TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const CnicDocumentViewer(),
              ),
              child: const Text('View submitted document'),
            ),
          ] else
            const Text(
              'Upload your CNIC image to complete registration. Your account remains pending until an administrator reviews it.',
            ),
          const SizedBox(height: 20),
          TextField(
            controller: number,
            enabled: !ctrl.busy.value,
            keyboardType: TextInputType.number,
            maxLength: 15,
            decoration: const InputDecoration(
              labelText: 'CNIC number',
              hintText: '12345-1234567-1',
            ),
          ),
          if (ctrl.image.value != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Image.memory(
                ctrl.image.value!.bytes,
                height: 200,
                fit: BoxFit.contain,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ctrl.busy.value
                      ? null
                      : () => ctrl.select(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ctrl.busy.value
                      ? null
                      : () => ctrl.select(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const Text(
            'JPEG or PNG only · maximum 5 MB. Images are prepared on your device before upload.',
          ),
          if (ctrl.error.value != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                ctrl.error.value!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          if (ctrl.busy.value)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
          ElevatedButton(
            onPressed: ctrl.busy.value ? null : _submit,
            child: Text(
              ctrl.busy.value
                  ? 'Preparing or uploading…'
                  : ctrl.application['document_valid'] == true
                  ? 'Replace and resubmit document'
                  : 'Submit CNIC document',
            ),
          ),
          TextButton(
            onPressed: ctrl.busy.value ? null : ctrl.loadStatus,
            child: const Text('Refresh status / Retry'),
          ),
        ],
      ),
    ),
  );
}
