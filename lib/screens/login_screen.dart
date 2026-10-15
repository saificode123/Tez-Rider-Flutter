import 'package:flutter/material.dart';
import '../services/account_session_service.dart';
import '../services/account_access.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';
import 'signup_screen.dart';
import 'customer_dashboard.dart';
import 'vendor_dashboard.dart';
import 'rider_dashboard.dart';
import 'admin_dashboard.dart';
import 'cnic_document_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final AuthController authController = Get.find<AuthController>();
  final _storage = const FlutterSecureStorage();

  bool _loading = false;
  bool _obscure = true;
  String _role = 'customer';

  late AnimationController _animCtrl;
  late Animation<double> _cardFade;
  late Animation<Offset> _cardSlide;

  static const _roles = [
    _RoleOption(
      value: 'customer',
      label: 'Customer',
      icon: Icons.person_rounded,
      color: AppColors.roleCustomer,
      desc: 'Order food, groceries & more',
    ),
    _RoleOption(
      value: 'vendor',
      label: 'Vendor',
      icon: Icons.storefront_rounded,
      color: AppColors.roleVendor,
      desc: 'Manage your store & orders',
    ),
    _RoleOption(
      value: 'rider',
      label: 'Rider',
      icon: Icons.delivery_dining_rounded,
      color: AppColors.roleRider,
      desc: 'Deliver orders & earn',
    ),
    _RoleOption(
      value: 'admin',
      label: 'Admin',
      icon: Icons.admin_panel_settings_rounded,
      color: AppColors.roleAdmin,
      desc: 'Manage the platform',
    ),
  ];

  _RoleOption get _currentRole => _roles.firstWhere((r) => r.value == _role);

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _cardFade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
    final args = Get.arguments;
    if (args is Map && args['account_message'] is String) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showError(args['account_message'] as String);
      });
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _goTo(String role) {
    switch (role) {
      case 'vendor':
        Get.offAll(
          () => const VendorDashboard(),
          transition: Transition.fadeIn,
        );
        break;
      case 'rider':
        Get.offAll(() => const RiderDashboard(), transition: Transition.fadeIn);
        break;
      case 'admin':
        Get.offAll(() => const AdminDashboard(), transition: Transition.fadeIn);
        break;
      default:
        Get.offAll(
          () => const CustomerDashboard(),
          transition: Transition.fadeIn,
        );
    }
  }

  bool _isValidEmail(String email) => RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  ).hasMatch(email);

  bool _isStrongPassword(String pw) => pw.length >= 6;

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }
    if (!_isValidEmail(email)) {
      _showError('Enter a valid email address');
      return;
    }
    if (!_isStrongPassword(password)) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.session == null) {
        _showError(
          'Sign in failed. Please check your credentials and try again.',
        );
        return;
      }

      if (!await authController.enforceAccountAccess()) {
        if (authController.accountGate.current ==
            AccountDisposition.unavailable) {
          _showError(
            'Account access could not be verified. Check your connection and Retry.',
          );
        }
        return;
      }
      final authenticatedEmail = res.user?.email ?? email;
      var userRecord = await Supabase.instance.client
          .from('users')
          .select('*')
          .eq('email', authenticatedEmail)
          .maybeSingle();

      // Recovery: user exists in Auth but has no profile row (e.g. signed up
      // before the insert-always fix). Create the row now so the app works.
      if (userRecord == null) {
        final meta = res.user?.userMetadata;
        final recoveryData = <String, dynamic>{
          'email': authenticatedEmail,
          'role': const {'customer', 'vendor', 'rider'}.contains(meta?['role'])
              ? meta!['role']
              : _role,
          'name': meta?['name'] ?? '',
          'phone': meta?['phone'],
          'verification_status': 'pending',
        };
        try {
          // RLS permits creating an own pending profile. An upsert also needs
          // UPDATE on email/role, which are deliberately protected columns.
          await Supabase.instance.client.from('users').insert(recoveryData);
        } on PostgrestException catch (error) {
          // Another sign-in can create the same profile concurrently.
          if (error.code != '23505') rethrow;
        }
        userRecord = await Supabase.instance.client
            .from('users')
            .select('*')
            .eq('email', authenticatedEmail)
            .maybeSingle();
      }

      final access = AccountAccess.fromProfile(userRecord);
      final realRole = access.role;
      final vStatus = access.status;

      await _storage.write(
        key: 'tr_refresh',
        value: res.session!.refreshToken ?? '',
      );
      await _storage.write(key: 'tr_role', value: realRole);
      await _storage.write(key: 'user_logged_in', value: 'true');
      await authController.setBioPreference(authController.isBioEnabled.value);

      if (access.needsApproval) {
        if (realRole == 'rider') {
          Get.offAll(() => const CnicDocumentScreen());
          return;
        }
        Get.offAllNamed(
          '/pending_verification',
          arguments: {'status': vStatus},
        );
      } else {
        _goTo(realRole);
      }
    } on AuthApiException catch (e) {
      switch (e.code) {
        case 'user_banned':
          _showError(blockedAccountMessage);
          break;
        case 'invalid_credentials':
          _showError('Incorrect email or password. Please try again.');
          break;
        case 'email_not_confirmed':
          _showError(
            'Please verify your email first. Check your inbox for the confirmation link.',
          );
          break;
        case 'user_not_found':
          _showError('No account found with this email. Please sign up first.');
          break;
        case 'too_many_requests':
          _showError('Too many login attempts. Please wait a few minutes.');
          break;
        default:
          _showError('Sign in failed: ${e.message}');
      }
    } catch (error) {
      _showError(
        // 'Something went wrong. Please check your internet and try again.',
        error.toString(),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _biometricLogin() async {
    final refreshToken = await _storage.read(key: 'tr_refresh');
    if (refreshToken == null || refreshToken.isEmpty) {
      _showError(
        'Please sign in with your password first to enable biometrics.',
      );
      return;
    }
    if (!authController.isBioSupported.value) {
      _showError('Biometrics not available on this device.');
      return;
    }
    setState(() => _loading = true);
    final ok = await authController.authenticateWithBiometrics();
    if (ok) {
      try {
        final res = await Supabase.instance.client.auth.setSession(
          refreshToken,
        );
        if (res.session != null) {
          if (!await authController.enforceAccountAccess()) {
            _showError(
              authController.accountGate.current == AccountDisposition.blocked
                  ? blockedAccountMessage
                  : 'Account access could not be verified. Retry.',
            );
            return;
          }
          await _storage.write(
            key: 'tr_refresh',
            value: res.session!.refreshToken ?? refreshToken,
          );
          final profile = await Supabase.instance.client
              .from('users')
              .select('role,verification_status')
              .eq('email', res.user!.email!)
              .maybeSingle();
          final access = AccountAccess.fromProfile(profile);
          await _storage.write(key: 'tr_role', value: access.role);
          if (access.needsApproval) {
            if (access.role == 'rider') {
              Get.offAll(() => const CnicDocumentScreen());
              return;
            }
            Get.offAllNamed(
              '/pending_verification',
              arguments: {'status': access.status},
            );
          } else {
            _goTo(access.role);
          }
        } else {
          _showError('Session expired. Please sign in with your password.');
        }
      } catch (_) {
        _showError('Session expired. Please sign in with your password.');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showError(String msg) {
    Get.snackbar(
      '',
      msg,
      titleText: const SizedBox.shrink(),
      messageText: Text(
        msg,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: AppColors.error,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      borderRadius: 14,
      duration: const Duration(seconds: 3),
      icon: const Icon(Icons.error_outline_rounded, color: Colors.white),
    );
  }

  void _showForgotPassword() {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Reset Password',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email and we\'ll send you a reset link.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'your@email.com',
                prefixIcon: const Icon(Icons.email_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = ctrl.text.trim();
              if (email.isEmpty) return;
              Get.back();
              try {
                await Supabase.instance.client.auth.resetPasswordForEmail(
                  email,
                );
                Get.snackbar(
                  'Email Sent',
                  'Check your inbox for the reset link.',
                  backgroundColor: AppColors.success,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  borderRadius: 14,
                  icon: const Icon(
                    Icons.mark_email_read_rounded,
                    color: Colors.white,
                  ),
                );
              } catch (_) {
                Get.snackbar(
                  'Error',
                  'Could not send reset email. Check the address.',
                  backgroundColor: AppColors.error,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  borderRadius: 14,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Send Link',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleDropdown(_RoleOption role) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSection,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: role.value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: role.color),
          dropdownColor: Colors.white,
          items: _roles.map((r) {
            return DropdownMenuItem<String>(
              value: r.value,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: r.color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(r.icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.desc,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _role = value);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final role = _currentRole;
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: size.height * 0.42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0F351B), // Dark brand green
                  role.color, // Role specific color
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),

          Positioned(
            top: -40,
            right: -40,
            child: _blob(180, AppColors.headerShape),
          ),
          Positioned(
            top: size.height * 0.18,
            left: -60,
            child: _blob(160, role.color.withValues(alpha: 0.14)),
          ),

          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: size.height * 0.34,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.headerGlass,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: role.color.withValues(alpha: 0.24),
                              blurRadius: 22,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(role.icon, size: 40, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'TEZRIDER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          role.desc,
                          key: ValueKey(role.value),
                          style: TextStyle(
                            color: AppColors.headerText.withValues(alpha: 0.88),
                            fontSize: 13,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SlideTransition(
                    position: _cardSlide,
                    child: FadeTransition(
                      opacity: _cardFade,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(36),
                          ),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel('Signing in as'),
                              const SizedBox(height: 10),
                              _buildRoleDropdown(role),
                              const SizedBox(height: 8),
                              Text(
                                role.desc,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 20),

                              _sectionLabel('Email Address'),
                              const SizedBox(height: 8),
                              _buildTextField(
                                controller: _emailCtrl,
                                hint: '••••••••',
                                icon: Icons.email_outlined,
                                type: TextInputType.emailAddress,
                                accentColor: role.color,
                              ),
                              const SizedBox(height: 16),

                              _sectionLabel('Password'),
                              const SizedBox(height: 8),
                              _buildTextField(
                                controller: _passCtrl,
                                hint: '••••••••',
                                icon: Icons.lock_outline_rounded,
                                obscure: _obscure,
                                accentColor: role.color,
                                suffix: GestureDetector(
                                  onTap: () =>
                                      setState(() => _obscure = !_obscure),
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 16),
                                    child: Icon(
                                      _obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 20,
                                      color: AppColors.textHint,
                                    ),
                                  ),
                                ),
                              ),

                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _showForgotPassword,
                                  style: TextButton.styleFrom(
                                    foregroundColor: role.color,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                  ),
                                  child: const Text(
                                    'Forgot password?',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 4),

                              _buildPrimaryButton(
                                label: 'Sign in as ${role.label}',
                                roleColor: role.color,
                                onTap: _loading ? null : _login,
                                loading: _loading,
                              ),

                              const SizedBox(height: 14),

                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: OutlinedButton(
                                  onPressed: () => Get.to(
                                    () => SignupScreen(initialRole: _role),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: role.color,
                                    side: BorderSide(
                                      color: role.color,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text(
                                    'Create Account',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              Obx(
                                () => authController.isBioSupported.value
                                    ? _buildBiometricButton(role.color)
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
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
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType type = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
    Color accentColor = AppColors.primary,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSection,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        obscureText: obscure,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
          prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
          suffixIcon: suffix,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 4,
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required Color roleColor,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: onTap == null
              ? null
              : LinearGradient(
                  colors: [const Color(0xFF0F351B), roleColor],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          color: onTap == null ? AppColors.textHint : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: onTap == null
              ? []
              : [
                  BoxShadow(
                    color: roleColor.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildBiometricButton(Color roleColor) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: TextButton.icon(
        onPressed: _loading ? null : _biometricLogin,
        icon: Icon(Icons.fingerprint_rounded, color: roleColor, size: 24),
        label: Text(
          'Continue with Biometrics',
          style: TextStyle(
            color: roleColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          backgroundColor: roleColor.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      letterSpacing: 0.3,
    ),
  );

  Widget _blob(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _RoleOption {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final String desc;
  const _RoleOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.desc,
  });
}
