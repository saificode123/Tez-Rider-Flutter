import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../../services/optional_media_service.dart';
import '../../widgets/private_photo_editor.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tailoring_controller.dart';

class TailoringScreen extends StatefulWidget {
  const TailoringScreen({super.key, this.pickReference});
  final Future<Uint8List?> Function(ImageSource source)? pickReference;

  @override
  State<TailoringScreen> createState() => _TailoringScreenState();
}

class _TailoringScreenState extends State<TailoringScreen> {
  final TailoringController _tailorCtrl = Get.put(TailoringController());

  final _instructionsCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _shoulderCtrl = TextEditingController();
  final _chestCtrl = TextEditingController();

  String? _reference;

  static const _purple = Color(0xFF1B5E20);

  void _submit() async {
    if (_instructionsCtrl.text.trim().isEmpty) {
      Get.snackbar('Required'.tr, 'Please provide stitching instructions.'.tr);
      return;
    }

    final measurements = {
      'length': _lengthCtrl.text,
      'shoulder': _shoulderCtrl.text,
      'chest': _chestCtrl.text,
    };

    final success = await _tailorCtrl.submitRequest(
      instructions: _instructionsCtrl.text,
      measurements: measurements,
      reference: _reference,
    );

    if (success && mounted) {
      Get.back(); // Return to dashboard on success
    }
  }

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    _lengthCtrl.dispose();
    _shoulderCtrl.dispose();
    _chestCtrl.dispose();
    Get.delete<TailoringController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F1F9),
      appBar: AppBar(
        backgroundColor: _purple,
        title: Text(
          'Home Tailoring'.tr,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Get.back(),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: _purple,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.dry_cleaning_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Request home tailoring".tr,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Submit your requirements. Pickup and tailor assignment must be confirmed before fulfillment."
                        .tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Stitching Instructions".tr,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _instructionsCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText:
                          "E.g. A-line shirt with collar, standard trousers..."
                              .tr,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    "Reference Image".tr,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  PrivatePhotoEditor(
                    service: OptionalMediaService(),
                    pick: widget.pickReference,
                    chooseLabel: 'Choose reference image',
                    accountChanges: Supabase
                        .instance
                        .client
                        .auth
                        .onAuthStateChange
                        .map((_) {}),
                    onSaved: (value) => _reference = value,
                  ),
                  const SizedBox(height: 24),

                  Text(
                    "Measurements (Optional)".tr,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "You can leave this blank if you are sending a sample stitched cloth with the rider."
                        .tr,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _measurementField("Length (in)".tr, _lengthCtrl),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _measurementField(
                          "Shoulder (in)".tr,
                          _shoulderCtrl,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _measurementField("Chest (in)".tr, _chestCtrl),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  Obx(
                    () => SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _tailorCtrl.isSubmitting.value
                            ? null
                            : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _purple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _tailorCtrl.isSubmitting.value
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : Text(
                                'Request Pickup'.tr,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _measurementField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
