import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/auth_controller.dart';
import '../controllers/cnic_document_controller.dart';
import '../services/cnic_document.dart';
import '../theme/app_theme.dart';
import '../widgets/cnic_document_viewer.dart';

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
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text("Rider CNIC verification".tr),
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
              const Icon(
                Icons.hourglass_top,
                color: AppColors.warning,
                size: 48,
              ),
              Text(
                ctrl.application['verification_status'] == 'approved'
                    ? "Your rider account is approved.".tr
                    : "Document submitted. Your account is awaiting admin approval."
                          .tr,
              ),
              if (ctrl.application['verification_status'] == 'approved')
                TextButton(
                  onPressed: () => Get.offAllNamed('/rider_home'),
                  child: Text("Continue to Rider Dashboard".tr),
                ),
              Text(
                "CNIC: @slot0end".uiTr({
                  "slot0end": (ctrl.application['cnic_masked'] ?? 'Protected')
                      .toString(),
                }),
              ),
              TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const CnicDocumentViewer(),
                ),
                child: Text("View submitted document".tr),
              ),
            ] else
              Text(
                "Upload your CNIC image to complete registration. Your account remains pending until an administrator reviews it."
                    .tr,
              ),
            const SizedBox(height: 20),
            TextField(
              controller: number,
              enabled: !ctrl.busy.value,
              keyboardType: TextInputType.number,
              maxLength: 15,
              decoration: InputDecoration(
                labelText: "CNIC number".tr,
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
                    label: Text("Camera".tr),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ctrl.busy.value
                        ? null
                        : () => ctrl.select(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: Text("Gallery".tr),
                  ),
                ),
              ],
            ),
            Text(
              "JPEG or PNG only · maximum 5 MB. Images are prepared on your device before upload."
                  .tr,
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
                    ? "Preparing or uploading…".tr
                    : ctrl.application['document_valid'] == true
                    ? "Replace and resubmit document".tr
                    : "Submit CNIC document".tr,
              ),
            ),
            TextButton(
              onPressed: ctrl.busy.value ? null : ctrl.loadStatus,
              child: Text("Refresh status / Retry".tr),
            ),
          ],
        ),
      ),
    );
  }
}
