import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import '../controllers/auth_controller.dart';
import 'splash_screen.dart';

class PendingVerificationScreen extends StatelessWidget {
  const PendingVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments as Map<String, dynamic>?;
    final String status = args?['status'] ?? 'pending';

    final bool isRejected = status == 'rejected';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Account Status'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: () async {
              await Get.find<AuthController>().logout(navigate: false);
              Get.offAll(() => const SplashScreen(showCyclist: false), transition: Transition.fadeIn);
            },
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              isRejected
                  ? const Icon(Icons.cancel_rounded, size: 80, color: Colors.redAccent)
                  : Lottie.asset('assets/lottie/otp_verification.json',
                      width: 180, height: 180),
              const SizedBox(height: 24),
              Text(
                isRejected ? 'Account Rejected' : 'Verification Pending',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isRejected
                  ? 'Unfortunately, your account application has been rejected by the admin. Please contact support for more details.'
                  : 'Your account is currently under review by the admin. You will be able to access your dashboard once you are approved.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    await Get.find<AuthController>().logout(navigate: false);
                    Get.offAll(() => const SplashScreen(showCyclist: false), transition: Transition.fadeIn);
                  },
                  child: const Text('Return to Login', style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
