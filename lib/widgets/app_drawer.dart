import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/auth_controller.dart';
import '../controllers/language_controller.dart';
import '../screens/splash_screen.dart';
import '../screens/customer/saved_stores_screen.dart';
import '../screens/customer/help_center_screen.dart';
import '../screens/customer/about_tezrider_screen.dart';
import '../screens/customer/order_history_screen.dart';
import '../screens/chat_rooms_screen.dart';
import '../screens/customer/notifications_screen.dart';

const _kGreen = Color(0xFF1B5E20);
const _kGreenL = Color(0xFF388E3C);

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.role});
  // Supplied by the canonically guarded dashboard, never editable metadata.
  final String role;

  @override
  Widget build(BuildContext context) {
    // Subscribe this route to locale changes as Get translation lookups are global.
    Localizations.localeOf(context);
    final authController = Get.find<AuthController>();
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['name'] as String? ?? 'User';
    final email = user?.email ?? 'No email';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D3B12), _kGreen, _kGreenL],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            accountName: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            accountEmail: Text(email),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _kGreen,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _drawerItem(
                  icon: Icons.dashboard_rounded,
                  text: 'dashboard'.tr,
                  onTap: () => Get.back(),
                ),
                if (role == 'customer') ...[
                  _drawerItem(
                    icon: Icons.receipt_long_rounded,
                    text: 'my_orders'.tr,
                    onTap: () {
                      Get.back();
                      Get.to(() => const OrderHistoryScreen());
                    },
                  ),
                  _drawerItem(
                    icon: Icons.favorite_rounded,
                    text: 'saved_vendors'.tr,
                    onTap: () {
                      Get.back();
                      Get.to(() => const SavedStoresScreen());
                    },
                  ),
                ],
                _drawerItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  text: 'Inbox'.tr,
                  onTap: () {
                    Get.back();
                    Get.to(() => const ChatRoomsScreen());
                  },
                ),
                _drawerItem(
                  icon: Icons.notifications_outlined,
                  text: 'Notifications'.tr,
                  onTap: () {
                    Get.back();
                    Get.to(() => NotificationsScreen());
                  },
                ),
                if (role == 'admin') ...[
                  _drawerItem(
                    icon: Icons.settings_rounded,
                    text: 'Platform Settings'.tr,
                    onTap: () {
                      Get.back();
                      Get.snackbar(
                        'Coming Soon',
                        'Platform settings will be available in a future update.',
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    },
                  ),
                  _drawerItem(
                    icon: Icons.report_rounded,
                    text: 'Reports'.tr,
                    onTap: () {
                      Get.back();
                      Get.snackbar(
                        'Coming Soon',
                        'Analytics reports will be available in a future update.',
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    },
                  ),
                ],
                const Divider(),
                _drawerItem(
                  icon: Icons.language_rounded,
                  text: 'language'.tr,
                  onTap: () async {
                    final language = Get.isRegistered<LanguageController>()
                        ? LanguageController.to
                        : Get.put(LanguageController(), permanent: true);
                    Get.back();
                    final saved = await language.toggle();
                    if (!saved) {
                      Get.snackbar(
                        'Language preference not saved'.tr,
                        'Please retry the language setting.'.tr,
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    }
                  },
                ),
                _drawerItem(
                  icon: Icons.help_outline_rounded,
                  text: 'help_support'.tr,
                  onTap: () {
                    Get.back();
                    Get.to(() => const HelpCenterScreen());
                  },
                ),
                _drawerItem(
                  icon: Icons.info_outline_rounded,
                  text: 'about'.tr,
                  onTap: () {
                    Get.back();
                    Get.to(() => const AboutTezRiderScreen());
                  },
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Get.back();
                  await authController.logout(navigate: false);
                  Get.offAll(
                    () => const SplashScreen(showCyclist: false),
                    transition: Transition.fadeIn,
                  );
                },
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                label: Text(
                  'sign_out'.tr,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: _kGreen),
      title: Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}
