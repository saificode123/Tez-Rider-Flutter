import 'package:get/get.dart';
import '../middleware/auth_middleware.dart';
import '../widgets/role_access_gate.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/customer_dashboard.dart';
import '../screens/vendor_dashboard.dart';
import '../screens/rider_dashboard.dart';
import '../screens/admin_dashboard.dart';
import '../screens/pending_verification_screen.dart';
import '../screens/customer/notifications_screen.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const signup = '/signup';
  static const customerHome = '/customer_home';
  static const vendorHome = '/vendor_home';
  static const riderHome = '/rider_home';
  static const adminHome = '/admin_home';
  static const pendingVerification = '/pending_verification';
  static const notifications = '/notifications';

  static final pages = [
    GetPage(name: splash, page: () => const SplashScreen()),
    GetPage(name: login, page: () => const LoginScreen()),
    GetPage(name: signup, page: () => const SignupScreen()),
    GetPage(
      name: pendingVerification,
      page: () => const PendingVerificationScreen(),
    ),
    GetPage(
      name: notifications,
      page: () => NotificationsScreen(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: customerHome,
      page: () => RoleAccessGate(
        role: 'customer',
        builder: (_) => const CustomerDashboard(),
      ),
      middlewares: [AuthMiddleware()],
      transition: Transition.native,
    ),
    GetPage(
      name: vendorHome,
      page: () => RoleAccessGate(
        role: 'vendor',
        builder: (_) => const VendorDashboard(),
      ),
      middlewares: [AuthMiddleware()],
      transition: Transition.native,
    ),
    GetPage(
      name: riderHome,
      page: () =>
          RoleAccessGate(role: 'rider', builder: (_) => const RiderDashboard()),
      middlewares: [AuthMiddleware()],
      transition: Transition.native,
    ),
    GetPage(
      name: adminHome,
      page: () =>
          RoleAccessGate(role: 'admin', builder: (_) => const AdminDashboard()),
      middlewares: [AuthMiddleware()],
      transition: Transition.native,
    ),
  ];
}
