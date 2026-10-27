import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'package:flutter/material.dart';
import '../services/account_session_service.dart';
import '../services/account_access.dart';
import '../services/onboarding_service.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/session_credentials.dart';
import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';
import '../theme/app_motion.dart';
import '../widgets/app_language_selector.dart';
import '../widgets/app_action_button.dart';
import '../widgets/password_reset_dialog.dart';
import 'signup_screen.dart';
import 'cnic_document_screen.dart';
import 'customer/help_center_screen.dart';

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

  bool _loading = false;
  bool _obscure = true;
  String? _error;
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
    _animCtrl = AnimationController(vsync: this, duration: AppMotion.entrance);
    _cardFade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    final args = Get.arguments;
    if (args is Map && args['account_message'] is String) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showError(args['account_message'] as String);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _animCtrl.value = 1;
    } else if (_animCtrl.status == AnimationStatus.dismissed) {
      _animCtrl.forward();
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
    final route = switch (role) {
      'vendor' => '/vendor_home',
      'rider' => '/rider_home',
      'admin' => '/admin_home',
      _ => '/customer_home',
    };
    Get.offAllNamed(route);
  }

  bool _isValidEmail(String email) => RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  ).hasMatch(email);

  bool _isStrongPassword(String pw) => pw.length >= 6;

  Future<void> _login() async {
    if (_loading) return;
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

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
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

      if (!await authController.enforceAccountAccess(passwordLogin: true)) {
        if (authController.accountGate.current ==
            AccountDisposition.unavailable) {
          _showError(
            'Account access could not be verified. Check your connection and Retry.',
          );
        }
        return;
      }
      try {
        await OnboardingService().completeFromMetadata(res.user!);
      } on RegistrationRequired catch (required) {
        Get.off(
          () =>
              SignupScreen(initialRole: required.role, completeExisting: true),
        );
        return;
      }
      // The first check may have seen PROFILE_MISSING. Bind the live account
      // watcher to the now-confirmed profile before any dashboard is opened.
      await authController.accountGate.reset();
      if (!await authController.enforceAccountAccess(passwordLogin: true)) {
        _showError('Account access could not be confirmed. Please retry.');
        return;
      }
      final userRecord = await Supabase.instance.client
          .from('users')
          .select('id,role,verification_status,is_blocked,rejection_reason')
          .eq('auth_user_id', res.user!.id)
          .single();

      final access = AccountAccess.fromProfile(userRecord);
      final realRole = access.role;
      final vStatus = access.status;

      try {
        await authController.credentials.remember(res.session!, realRole);
        authController.isBioEnabled.value = false;
      } catch (_) {
        await authController.logout(navigate: false);
        _showError(secureSessionUnavailable);
        return;
      }

      if (access.needsApproval) {
        if (realRole == 'rider') {
          Get.offAll(() => const CnicDocumentScreen());
          return;
        }
        Get.offAllNamed(
          '/pending_verification',
          arguments: {
            'status': vStatus,
            'reason': userRecord['rejection_reason'],
          },
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
          _showError('Sign in could not be confirmed. Retry.');
      }
    } catch (_) {
      _showError('Sign in was not confirmed. Check your connection and Retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _biometricLogin() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final saved = await authController.credentials.read(
        currentAccount: Supabase.instance.client.auth.currentUser?.id,
      );
      if (saved == null ||
          !await authController.credentials.biometricEnabled(saved.account)) {
        _showError(
          'Please sign in with your password first to enable biometrics.',
        );
        return;
      }
      if (!authController.isBioSupported.value) {
        _showError('Biometrics not available on this device.');
        return;
      }
      final ok = await authController.authenticateWithBiometrics();
      if (ok) {
        final res = await Supabase.instance.client.auth.setSession(
          saved.refreshToken,
        );
        if (res.session != null) {
          if (res.user?.id != saved.account) {
            await authController.logout(navigate: false);
            _showError('Please sign in with your password.');
            return;
          }
          if (!await authController.enforceAccountAccess()) {
            _showError(
              authController.accountGate.current == AccountDisposition.blocked
                  ? blockedAccountMessage
                  : 'Account access could not be verified. Retry.',
            );
            return;
          }
          final profile = await Supabase.instance.client
              .from('users')
              .select('role,verification_status,is_blocked,rejection_reason')
              .eq('auth_user_id', saved.account)
              .maybeSingle();
          final access = AccountAccess.fromProfile(profile);
          await authController.credentials.remember(
            res.session!,
            access.role,
            preserveBiometric: true,
          );
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
      }
    } catch (_) {
      await authController.logout(navigate: false);
      _showError('Session expired. Please sign in with your password.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (mounted) setState(() => _error = msg);
  }

  void _showForgotPassword() {
    Get.dialog(
      PasswordResetDialog(email: _emailCtrl.text.trim()),
      barrierDismissible: false,
    );
  }

  Widget _buildRoleDropdown(_RoleOption role) {
    return DropdownButtonFormField<String>(
      initialValue: role.value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Signing in as'.tr,
        prefixIcon: Icon(role.icon, color: AppColors.primary),
      ),
      items: [
        for (final item in _roles)
          DropdownMenuItem(value: item.value, child: Text(item.label.tr)),
      ],
      onChanged: _loading
          ? null
          : (value) {
              if (value != null) setState(() => _role = value);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final role = _currentRole;
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth < 360 ? 16 : 24,
                vertical: 16,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: AppLanguageSelector(),
                      ),
                      const SizedBox(height: 28),
                      Center(
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                            boxShadow: AppShadow.soft,
                          ),
                          child: const Icon(
                            Icons.delivery_dining_rounded,
                            size: 42,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'TEZRIDER'.tr,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Welcome back'.tr,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      AnimatedSwitcher(
                        duration: AppMotion.duration(context),
                        child: Text(
                          role.desc.tr,
                          key: ValueKey('${role.value}:${role.desc.tr}'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SlideTransition(
                        position: _cardSlide,
                        child: FadeTransition(
                          opacity: _cardFade,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: AutofillGroup(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildRoleDropdown(role),
                                    if (_error != null) ...[
                                      const SizedBox(height: 16),
                                      Semantics(
                                        liveRegion: true,
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: AppColors.error.withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            _error!.tr,
                                            style: const TextStyle(
                                              color: AppColors.error,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 20),
                                    TextField(
                                      controller: _emailCtrl,
                                      enabled: !_loading,
                                      keyboardType: TextInputType.emailAddress,
                                      textDirection: TextDirection.ltr,
                                      autofillHints: const [
                                        AutofillHints.username,
                                        AutofillHints.email,
                                      ],
                                      textInputAction: TextInputAction.next,
                                      autocorrect: false,
                                      decoration: InputDecoration(
                                        labelText: 'Email Address'.tr,
                                        hintText: 'your@email.com',
                                        prefixIcon: const Icon(
                                          Icons.mail_outline_rounded,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextField(
                                      controller: _passCtrl,
                                      enabled: !_loading,
                                      obscureText: _obscure,
                                      textDirection: TextDirection.ltr,
                                      autofillHints: const [
                                        AutofillHints.password,
                                      ],
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => _login(),
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      decoration: InputDecoration(
                                        labelText: 'Password'.tr,
                                        prefixIcon: const Icon(
                                          Icons.lock_outline_rounded,
                                        ),
                                        suffixIcon: IconButton(
                                          tooltip:
                                              (_obscure
                                                      ? 'Show password'
                                                      : 'Hide password')
                                                  .tr,
                                          onPressed: _loading
                                              ? null
                                              : () => setState(
                                                  () => _obscure = !_obscure,
                                                ),
                                          icon: AnimatedSwitcher(
                                            duration: AppMotion.duration(
                                              context,
                                              AppMotion.quick,
                                            ),
                                            child: Icon(
                                              _obscure
                                                  ? Icons
                                                        .visibility_off_outlined
                                                  : Icons.visibility_outlined,
                                              key: ValueKey(_obscure),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: TextButton(
                                        onPressed: _loading
                                            ? null
                                            : _showForgotPassword,
                                        child: Text('Forgot password?'.tr),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    AppActionButton(
                                      label: 'Sign in as @slot0end'.uiTr({
                                        'slot0end': role.label.tr,
                                      }),
                                      busy: _loading,
                                      onPressed: _login,
                                    ),
                                    const SizedBox(height: 12),
                                    AppActionButton(
                                      label: 'Create Account'.tr,
                                      style: AppActionStyle.secondary,
                                      onPressed: _loading
                                          ? null
                                          : () => Get.to(
                                              () => SignupScreen(
                                                initialRole: _role,
                                              ),
                                            ),
                                    ),
                                    Obx(
                                      () =>
                                          authController.isBioSupported.value &&
                                              authController.isBioEnabled.value
                                          ? Padding(
                                              padding: const EdgeInsets.only(
                                                top: 12,
                                              ),
                                              child: TextButton.icon(
                                                onPressed: _loading
                                                    ? null
                                                    : _biometricLogin,
                                                icon: const Icon(
                                                  Icons.fingerprint_rounded,
                                                ),
                                                label: Text(
                                                  'Continue with Biometrics'.tr,
                                                ),
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _loading
                            ? null
                            : () => Get.to(() => const HelpCenterScreen()),
                        icon: const Icon(Icons.help_outline_rounded, size: 20),
                        label: Text('help_support'.tr),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
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
