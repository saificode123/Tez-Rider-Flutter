import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'cnic_document_screen.dart';
import '../services/cnic_document.dart';
import '../services/onboarding_service.dart';
import '../controllers/auth_controller.dart';
import 'package:image_picker/image_picker.dart';

const _kBg = Color(0xFFF5F0E8);
const _kText = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);

class SignupScreen extends StatefulWidget {
  final String? initialRole;
  final bool completeExisting;
  const SignupScreen({
    super.key,
    this.initialRole,
    this.completeExisting = false,
  });
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _cnic = TextEditingController();
  final _storeName = TextEditingController();
  final _storeAddress = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  CnicImage? _cnicImage;
  final _cnicImages = CnicImageService();
  final _cnicDraft = CnicDraftStore();
  String _cnicRequest = cnicRequestId();
  late String _role;

  final List<Map<String, dynamic>> _roles = [
    {
      'value': 'customer',
      'label': 'Customer',
      'icon': Icons.person_rounded,
      'color': AppColors.roleCustomer,
      'desc': 'Order food, groceries & more',
    },
    {
      'value': 'vendor',
      'label': 'Vendor',
      'icon': Icons.storefront_rounded,
      'color': AppColors.roleVendor,
      'desc': 'Manage your store & orders',
    },
    {
      'value': 'rider',
      'label': 'Rider',
      'icon': Icons.delivery_dining_rounded,
      'color': AppColors.roleRider,
      'desc': 'Deliver orders & earn',
    },
  ];

  Color get _selectedRoleColor =>
      _roles.firstWhere((r) => r['value'] == _role)['color'] as Color;

  @override
  void initState() {
    super.initState();
    _role = const {'customer', 'vendor', 'rider'}.contains(widget.initialRole)
        ? widget.initialRole!
        : 'customer';
    if (widget.completeExisting) {
      final user = Supabase.instance.client.auth.currentUser;
      final data = OnboardingService.fromMetadata(user?.userMetadata ?? {});
      _name.text = data.name;
      _phone.text = data.phone;
      _email.text = user?.email ?? '';
      _storeName.text = data.storeName;
      _storeAddress.text = data.storeAddress;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _pass.dispose();
    _cnic.dispose();
    _storeName.dispose();
    _storeAddress.dispose();
    super.dispose();
  }

  bool _isValidEmail(String e) =>
      RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$').hasMatch(e);

  Future<void> _signup() async {
    if (_loading) return;
    final email = _email.text.trim();
    final pass = _pass.text;
    if (_name.text.trim().isEmpty ||
        email.isEmpty ||
        (!widget.completeExisting && pass.isEmpty)) {
      _err('Please fill all required fields');
      return;
    }
    if (!_isValidEmail(email)) {
      _err('Enter a valid email address');
      return;
    }
    if (!widget.completeExisting && pass.length < 6) {
      _err('Password must be at least 6 characters');
      return;
    }
    final data = RegistrationData(
      name: _name.text,
      phone: _phone.text,
      role: _role,
      storeName: _storeName.text,
      storeAddress: _storeAddress.text,
    );
    if (data.error != null) {
      _err(data.error!);
      return;
    }
    if (_role == 'rider' && !widget.completeExisting) {
      try {
        normalizeCnic(_cnic.text.trim());
      } on FormatException catch (e) {
        _err(e.message);
        return;
      }
      if (_cnicImage == null) {
        _err('Please upload your CNIC document to continue.');
        return;
      }
    }
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      if (widget.completeExisting) {
        await OnboardingService().complete(data, updateProfile: true);
        await Get.find<AuthController>().logout(navigate: false);
        Get.offAll(() => const LoginScreen());
        Get.snackbar(
          "Profile saved".tr,
          "Sign in to check your account approval.".tr,
        );
        return;
      }
      if (_role == 'rider') {
        await _cnicDraft.save(
          email,
          normalizeCnic(_cnic.text.trim()),
          _cnicImage!.sourcePath,
          _cnicRequest,
        );
      }
      final res = await client.auth.signUp(
        email: email,
        password: pass,
        data: data.metadata,
      );
      if (res.user == null) {
        _err('Sign up was not confirmed. Please retry.');
        return;
      }
      if (res.session == null) {
        Get.off(() => const LoginScreen());
        Get.snackbar(
          "Verify your email".tr,
          "Verify your email, then sign in to finish registration. Vendor and Rider access remains pending Admin approval."
              .tr,
          duration: const Duration(seconds: 8),
        );
        return;
      }
      final completed = await OnboardingService().complete(data);
      if (completed['role'] == 'rider') {
        final auth = Get.find<AuthController>();
        await auth.accountGate.reset();
        if (!await auth.enforceAccountAccess(passwordLogin: true)) {
          throw StateError('Account access was not confirmed.');
        }
        await auth.credentials.remember(client.auth.currentSession!, 'rider');
        Get.off(() => const CnicDocumentScreen());
      } else {
        await Get.find<AuthController>().logout(navigate: false);
        Get.offAll(() => const LoginScreen());
        Get.snackbar(
          "Profile saved".tr,
          "Sign in to continue. Vendor accounts require Admin approval.".tr,
        );
      }
    } on AuthApiException catch (e) {
      _handleAuthError(e.statusCode?.toString() ?? '', e.message);
    } on AuthException catch (e) {
      _handleAuthError('', e.message);
    } on RegistrationRequired {
      _err('Complete your profile and store details, then retry.');
    } catch (_) {
      _err(
        'Registration was not fully confirmed. Verify your email and sign in to resume, or retry when connected.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseCnic(ImageSource source) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final image = await _cnicImages.pick(source);
      if (mounted && image != null) {
        setState(() {
          _cnicImage = image;
          _cnicRequest = cnicRequestId();
        });
      }
    } on FormatException catch (e) {
      _err(e.message);
    } catch (_) {
      _err('Could not select the image. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleAuthError(String code, String message) {
    final msg = message.toLowerCase();
    if (code == '422' ||
        msg.contains('already registered') ||
        msg.contains('already been registered') ||
        msg.contains('already exists') ||
        msg.contains('user_already_exists')) {
      _err('This email is already registered. Try signing in instead.');
    } else if (msg.contains('rate limit') ||
        msg.contains('too many') ||
        code == '429') {
      _err('Too many attempts. Please wait a moment and try again.');
    } else if (msg.contains('weak password') ||
        msg.contains('password should be')) {
      _err(
        'Password is too weak. Use at least 6 characters with letters and numbers.',
      );
    } else if (msg.contains('invalid email') ||
        msg.contains('unable to validate email')) {
      _err('Invalid email address. Please check and try again.');
    } else if (msg.contains('signup') && msg.contains('disabled')) {
      _err('New registrations are currently disabled. Please contact support.');
    } else {
      _err('Sign up could not be confirmed. Retry.');
    }
  }

  void _err(String msg) {
    Get.snackbar(
      '',
      msg.tr,
      titleText: const SizedBox.shrink(),
      messageText: Text(
        msg.tr,
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
      icon: const Icon(Icons.error_outline_rounded, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),

            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  24,
                  28,
                  24,
                  24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.initialRole == null) ...[
                      _label("Register as".tr),
                      const SizedBox(height: 12),
                      _buildRoleDropdown(),
                      const SizedBox(height: 8),
                      Text(
                        (_roles.firstWhere((r) => r['value'] == _role)['desc']
                                as String)
                            .tr,
                        style: const TextStyle(fontSize: 13, color: _kTextSub),
                      ),
                      const SizedBox(height: 22),
                    ],

                    _buildField(
                      'Full Name',
                      _name,
                      Icons.person_outline_rounded,
                      "Your full name".tr,
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      'Email',
                      _email,
                      Icons.email_outlined,
                      "you@example.com".tr,
                      type: TextInputType.emailAddress,
                      readOnly: widget.completeExisting,
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      'Phone Number',
                      _phone,
                      Icons.phone_outlined,
                      "+92 3XX-XXXXXXX".tr,
                      type: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),

                    if (_role == 'rider' && !widget.completeExisting) ...[
                      _buildField(
                        'CNIC Number',
                        _cnic,
                        Icons.credit_card_outlined,
                        '37400-1234567-9',
                        type: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_role == 'rider' && !widget.completeExisting) ...[
                      _label("CNIC document image".tr),
                      if (_cnicImage != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Image.memory(
                            _cnicImage!.bytes,
                            height: 150,
                            fit: BoxFit.contain,
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () => _chooseCnic(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: Text("Camera".tr),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () => _chooseCnic(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: Text("Gallery".tr),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "JPEG or PNG only · maximum 5 MB · private access".tr,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_role == 'vendor') ...[
                      _buildField(
                        'Shop / Store Name',
                        _storeName,
                        Icons.storefront_outlined,
                        "e.g. Hot N Spicy".tr,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        'Store Address',
                        _storeAddress,
                        Icons.location_on_outlined,
                        "Street and city".tr,
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (!widget.completeExisting) ...[
                      _label("Password".tr),
                      const SizedBox(height: 8),
                      _buildPasswordField(),
                    ],
                    const SizedBox(height: 28),

                    _buildPrimaryButton(),
                    const SizedBox(height: 20),

                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          "Already have an account? ".tr,
                          style: TextStyle(color: _kTextSub, fontSize: 13),
                        ),
                        GestureDetector(
                          onTap: () => Get.back(),
                          child: Text(
                            "Sign In".tr,
                            style: TextStyle(
                              color: _selectedRoleColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final headerHeight = (MediaQuery.of(context).size.height * 0.26).clamp(
      180.0,
      240.0,
    );
    return Container(
      constraints: BoxConstraints(minHeight: headerHeight),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF0F351B), _selectedRoleColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    onPressed: () => Get.back(),
                  ),

                  const SizedBox(height: 8),

                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.person_add_rounded,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.completeExisting
                              ? "Complete Registration".tr
                              : "Create Account".tr,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Join TezRider today".tr,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          itemHeight: null,
          value: _role,
          isExpanded: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _selectedRoleColor,
          ),
          items: _roles.map((r) {
            return DropdownMenuItem<String>(
              value: r['value'] as String,
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: r['color'] as Color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      r['icon'] as IconData,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (r['label'] as String).tr,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (r['desc'] as String).tr,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _kTextSub,
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
            if (!_loading) setState(() => _role = value);
          },
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl,
    IconData icon,
    String hint, {
    TextInputType type = TextInputType.text,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          enabled: !_loading,
          readOnly: readOnly,
          keyboardType: type,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _kText,
          ),
          decoration: InputDecoration(
            hintText: hint.tr,
            hintStyle: TextStyle(
              color: _kTextSub.withValues(alpha: 0.6),
              fontSize: 14,
            ),
            prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
            filled: true,
            fillColor: AppColors.bgSection,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _pass,
          obscureText: _obscure,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _kText,
          ),
          decoration: InputDecoration(
            hintText: "Min 6 characters".tr,
            hintStyle: TextStyle(
              color: _kTextSub.withValues(alpha: 0.6),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.lock_outline_rounded,
              color: AppColors.primary,
              size: 20,
            ),
            suffixIcon: GestureDetector(
              onTap: () => setState(() => _obscure = !_obscure),
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: _kTextSub,
                ),
              ),
            ),
            filled: true,
            fillColor: AppColors.bgSection,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _loading ? null : _signup,
        style:
            ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.all(Colors.transparent),
              elevation: WidgetStateProperty.all(0),
            ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _loading
                ? null
                : LinearGradient(
                    colors: [const Color(0xFF0F351B), _selectedRoleColor],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            color: _loading ? Colors.grey.shade300 : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _loading
                ? []
                : [
                    BoxShadow(
                      color: _selectedRoleColor.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Container(
            alignment: Alignment.center,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    widget.completeExisting
                        ? "Complete Registration".tr
                        : "Create Account".tr,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text.tr,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: _kTextSub,
      letterSpacing: 0.3,
    ),
  );
}
