import 'package:get/get.dart';
import '../middleware/auth_middleware.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/customer_dashboard.dart';
import '../screens/vendor_dashboard.dart';
import '../screens/rider_dashboard.dart';
import '../screens/admin_dashboard.dart';
import '../screens/pending_verification_screen.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const signup = '/signup';
  static const customerHome = '/customer_home';
  static const vendorHome = '/vendor_home';
  static const riderHome = '/rider_home';
  static const adminHome = '/admin_home';
  static const pendingVerification = '/pending_verification';

  static final pages = [
    GetPage(name: splash, page: () => const SplashScreen()),
    GetPage(name: login, page: () => const LoginScreen()),
    GetPage(name: signup, page: () => const SignupScreen()),
    GetPage(name: pendingVerification, page: () => const PendingVerificationScreen()),
    GetPage(
      name: customerHome,
      page: () => const CustomerDashboard(),
      middlewares: [AuthMiddleware()],
      transition: Transition.cupertino,
    ),
    GetPage(
      name: vendorHome,
      page: () => const VendorDashboard(),
      middlewares: [AuthMiddleware()],
      transition: Transition.cupertino,
    ),
    GetPage(
      name: riderHome,
      page: () => const RiderDashboard(),
      middlewares: [AuthMiddleware()],
      transition: Transition.cupertino,
    ),
    GetPage(
      name: adminHome,
      page: () => const AdminDashboard(),
      middlewares: [AuthMiddleware()],
      transition: Transition.cupertino,
    ),
  ];
}
