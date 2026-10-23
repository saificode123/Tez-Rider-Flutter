import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tailoring_controller.dart';

class TailoringScreen extends StatefulWidget {
  const TailoringScreen({super.key});

  @override
  State<TailoringScreen> createState() => _TailoringScreenState();
}

class _TailoringScreenState extends State<TailoringScreen> {
  final TailoringController _tailorCtrl = Get.put(TailoringController());

  final _instructionsCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _shoulderCtrl = TextEditingController();
  final _chestCtrl = TextEditingController();


  static const _purple = Color(0xFF1B5E20);

  void _submit() async {
    if (_instructionsCtrl.text.isEmpty) {
      Get.snackbar('Required', 'Please provide stitching instructions.');
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
    );

    if (success) {
      Get.back(); // Return to dashboard on success
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F1F9),
      appBar: AppBar(
        backgroundColor: _purple,
        title: const Text('Home Tailoring', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
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
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.dry_cleaning_rounded, size: 60, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    "We Pick Up, Stitch, and Deliver!",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Enter your requirements below. Our rider will pick up the unstitched cloth from your location.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Stitching Instructions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _instructionsCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: "E.g. A-line shirt with collar, standard trousers...",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  const Text("Reference Image", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Reference-image upload is not configured. No image was attached.'),
                      ));
                    },
                    child: Container(
                      width: double.infinity,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.add_photo_alternate_rounded, size: 40, color: Colors.grey),
                              SizedBox(height: 8),
                              Text("Tap to Upload Reference Image", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                              Text("e.g. Dress design, Flower bouquet", style: TextStyle(color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text("Measurements (Optional)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  const Text("You can leave this blank if you are sending a sample stitched cloth with the rider.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(child: _measurementField("Length (in)", _lengthCtrl)),
                      const SizedBox(width: 12),
                      Expanded(child: _measurementField("Shoulder (in)", _shoulderCtrl)),
                      const SizedBox(width: 12),
                      Expanded(child: _measurementField("Chest (in)", _chestCtrl)),
                    ],
                  ),
                  const SizedBox(height: 40),

                  Obx(() => SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _tailorCtrl.isSubmitting.value ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _tailorCtrl.isSubmitting.value
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Request Pickup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  )),
                ],
              ),
            )
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}
