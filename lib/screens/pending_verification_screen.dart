import '../widgets/spatial_surface.dart';
import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import '../controllers/auth_controller.dart';
import 'splash_screen.dart';

class PendingVerificationScreen extends StatelessWidget {
  const PendingVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final args = Get.arguments as Map<String, dynamic>?;
    final String status = args?['status'] ?? 'pending';

    final bool isRejected = status == 'rejected';
    final reason = args?['reason'] as String?;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 64,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        title: Text("Account Status".tr),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: () async {
              await Get.find<AuthController>().logout(navigate: false);
              Get.offAll(
                () => const SplashScreen(showCyclist: false),
                transition: Transition.fadeIn,
              );
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SpatialSurface(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                isRejected
                    ? const Icon(
                        Icons.cancel_rounded,
                        size: 80,
                        color: Colors.redAccent,
                      )
                    : Lottie.asset(
                        'assets/lottie/otp_verification.json',
                        width: 180,
                        height: 180,
                      ),
                const SizedBox(height: 24),
                Text(
                  isRejected
                      ? "Account Rejected".tr
                      : "Verification Pending".tr,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isRejected
                      ? (reason?.trim().isNotEmpty == true
                            ? reason!
                            : "Your application was rejected. Please contact support for details."
                                  .tr)
                      : "Your account is currently under review by the admin. You will be able to access your dashboard once you are approved."
                            .tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () =>
                      Get.offAll(() => const SplashScreen(showCyclist: false)),
                  child: Text("Check approval status".tr),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      await Get.find<AuthController>().logout(navigate: false);
                      Get.offAll(
                        () => const SplashScreen(showCyclist: false),
                        transition: Transition.fadeIn,
                      );
                    },
                    child: Text(
                      "Return to Login".tr,
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
