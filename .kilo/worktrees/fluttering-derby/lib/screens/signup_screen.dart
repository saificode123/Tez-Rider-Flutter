import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

const _kBg      = Color(0xFFF5F0E8);
const _kText    = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);
const _kGreen   = Color(0xFF10B981);
const _kDivider = Color(0xFFE5EDE6);

class SignupScreen extends StatefulWidget {
  final String? initialRole;
  const SignupScreen({super.key, this.initialRole});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name  = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass  = TextEditingController();
  final _cnic  = TextEditingController();
  final _storeName = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  late String _role;

  final List<Map<String, dynamic>> _roles = [
    {'value': 'customer', 'label': 'Customer', 'icon': Icons.person_rounded,         'color': AppColors.roleCustomer, 'desc': 'Order food, groceries & more'},
    {'value': 'vendor',   'label': 'Vendor',   'icon': Icons.storefront_rounded,    'color': AppColors.roleVendor,   'desc': 'Manage your store & orders'},
    {'value': 'rider',    'label': 'Rider',    'icon': Icons.delivery_dining_rounded, 'color': AppColors.roleRider,    'desc': 'Deliver orders & earn'},
    {'value': 'admin',    'label': 'Admin',    'icon': Icons.admin_panel_settings_rounded, 'color': AppColors.roleAdmin,    'desc': 'Manage the platform'},
  ];

  Color get _selectedRoleColor =>
      _roles.firstWhere((r) => r['value'] == _role)['color'] as Color;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole ?? 'customer';
  }

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _phone.dispose();
    _pass.dispose(); _cnic.dispose(); _storeName.dispose();
    super.dispose();
  }

  bool _isValidEmail(String e) =>
      RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$').hasMatch(e);

  Future<void> _signup() async {
    final name  = _name.text.trim();
    final email = _email.text.trim();
    final pass  = _pass.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      _err('Please fill all required fields'); return;
    }
    if (!_isValidEmail(email)) { _err('Enter a valid email address'); return; }
    if (pass.length < 6)       { _err('Password must be at least 6 characters'); return; }
    if ((_role == 'rider' || _role == 'vendor') && _cnic.text.trim().isEmpty) {
      _err('CNIC is required for ${_role}s'); return;
    }
    if (_role == 'vendor' && _storeName.text.trim().isEmpty) {
      _err('Shop/store name is required for vendors'); return;
    }

    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: pass,
        data: {'name': name, 'role': _role},
      );

      if (res.user == null) {
        _err('Sign up failed. Please try again.');
        return;
      }

      // Always insert profile — regardless of whether email confirmation is required.
      // If session is null (email not yet confirmed), the upsert runs anyway so the
      // record exists the moment the user verifies and signs in.
      // Customers/admins are auto-approved. Riders & vendors must be
      // reviewed by an admin before they can access their dashboard —
      // this is enforced regardless of the table's default value.
      final needsAdminApproval = _role == 'rider' || _role == 'vendor';

      final Map<String, dynamic> profileData = {
        'name':  name,
        'email': email,
        'phone': _phone.text.trim(),
        'role':  _role,
        'verification_status': needsAdminApproval ? 'pending' : 'approved',
      };
      if (_role == 'rider' || _role == 'vendor') {
        profileData['cnic'] = _cnic.text.trim();
      }

      try {
        await Supabase.instance.client
            .from('users')
            .upsert(profileData, onConflict: 'email');
      } catch (insertErr) {
        debugPrint('users table upsert error: $insertErr');
      }

      // Vendors also get a row in the `vendors` table (store_name) —
      // this is what shows up as the shop name on customer product cards.
      if (_role == 'vendor') {
        try {
          final userRecord = await Supabase.instance.client
              .from('users')
              .select('id')
              .eq('email', email)
              .maybeSingle();
          if (userRecord != null) {
            await Supabase.instance.client.from('vendors').upsert({
              'user_id': userRecord['id'],
              'store_name': _storeName.text.trim(),
              'is_active': true,
            }, onConflict: 'user_id');
          }
        } catch (vendorErr) {
          debugPrint('vendors table upsert error: $vendorErr');
        }
      }

      final needsConfirmation = res.session == null;

      if (needsConfirmation) {
        Get.snackbar(
          'Verify Your Email',
          'A confirmation link has been sent to $email. Please verify before signing in.',
          backgroundColor: const Color(0xFF1565C0),
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          borderRadius: 14,
          duration: const Duration(seconds: 6),
          icon: const Icon(Icons.mark_email_unread_rounded, color: Colors.white),
        );
      } else {
        Get.snackbar(
          'Account Created!', 'Please sign in to continue.',
          backgroundColor: _kGreen,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          borderRadius: 14,
          icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
        );
      }
      Get.off(() => const LoginScreen());

    } on AuthApiException catch (e) {
      _handleAuthError(e.statusCode?.toString() ?? '', e.message);
    } on AuthException catch (e) {
      _handleAuthError('', e.message);
    } catch (e) {
      final msg = e.toString();
      debugPrint('Signup unknown error: $msg');
      if (msg.contains('already registered') || msg.contains('already exists') || msg.contains('duplicate')) {
        _err('This email is already registered. Try signing in instead.');
      } else if (msg.contains('network') || msg.contains('socket') || msg.contains('connection') || msg.contains('SocketException')) {
        _err('No internet connection. Please check your network.');
      } else {
        _err('Sign up failed: $msg');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleAuthError(String code, String message) {
    final msg = message.toLowerCase();
    if (code == '422' || msg.contains('already registered') || msg.contains('already been registered') || msg.contains('already exists') || msg.contains('user_already_exists')) {
      _err('This email is already registered. Try signing in instead.');
    } else if (msg.contains('rate limit') || msg.contains('too many') || code == '429') {
      _err('Too many attempts. Please wait a moment and try again.');
    } else if (msg.contains('weak password') || msg.contains('password should be')) {
      _err('Password is too weak. Use at least 6 characters with letters and numbers.');
    } else if (msg.contains('invalid email') || msg.contains('unable to validate email')) {
      _err('Invalid email address. Please check and try again.');
    } else if (msg.contains('signup') && msg.contains('disabled')) {
      _err('New registrations are currently disabled. Please contact support.');
    } else {
      _err('Sign up failed: $message');
    }
  }

  void _err(String msg) {
    Get.snackbar('', msg,
      titleText: const SizedBox.shrink(),
      messageText: Text(msg,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      backgroundColor: AppColors.error,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      borderRadius: 14,
      icon: const Icon(Icons.error_outline_rounded, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),

            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.initialRole == null) ...[
                    _label('Register as'),
                    const SizedBox(height: 12),
                    _buildRoleDropdown(),
                    const SizedBox(height: 8),
                    Text(
                      _roles.firstWhere((r) => r['value'] == _role)['desc'] as String,
                      style: const TextStyle(fontSize: 13, color: _kTextSub),
                    ),
                    const SizedBox(height: 22),
                  ],

                  _buildField('Full Name', _name, Icons.person_outline_rounded,
                      'Your full name'),
                  const SizedBox(height: 16),

                  _buildField('Email', _email, Icons.email_outlined,
                      'you@example.com', type: TextInputType.emailAddress),
                  const SizedBox(height: 16),

                  _buildField('Phone Number', _phone, Icons.phone_outlined,
                      '+92 3XX-XXXXXXX', type: TextInputType.phone),
                  const SizedBox(height: 16),

                  if (_role == 'rider' || _role == 'vendor') ...[
                    _buildField('CNIC Number', _cnic,
                        Icons.credit_card_outlined, '37400-1234567-9',
                        type: TextInputType.number),
                    const SizedBox(height: 16),
                  ],

                  if (_role == 'vendor') ...[
                    _buildField('Shop / Store Name', _storeName,
                        Icons.storefront_outlined, 'e.g. Hot N Spicy'),
                    const SizedBox(height: 16),
                  ],

                  _label('Password'),
                  const SizedBox(height: 8),
                  _buildPasswordField(),
                  const SizedBox(height: 28),

                  _buildPrimaryButton(),
                  const SizedBox(height: 20),

                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Already have an account? ',
                        style: TextStyle(color: _kTextSub, fontSize: 13)),
                    GestureDetector(
                      onTap: () => Get.back(),
                      child: Text('Sign In',
                          style: TextStyle(
                              color: _selectedRoleColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                  ]),

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
    final headerHeight = (MediaQuery.of(context).size.height * 0.26).clamp(180.0, 240.0);
    return Container(
      height: headerHeight,
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
        Positioned(top: -40, right: -40,
          child: Container(
            width: 180, height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
        Positioned(bottom: -20, left: -30,
          child: Container(
            width: 120, height: 120,
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
                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                  ),
                  onPressed: () => Get.back(),
                ),

                const SizedBox(height: 8),

                Center(
                  child: Column(children: [
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35), width: 2),
                      ),
                      child: const Icon(Icons.person_add_rounded,
                          size: 28, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    const Text('Create Account',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900,
                            color: Colors.white, letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Text('Join TezRider today',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 13)),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ]),
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
          value: _role,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: _selectedRoleColor),
          items: _roles.map((r) {
            return DropdownMenuItem<String>(
              value: r['value'] as String,
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: r['color'] as Color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(r['icon'] as IconData, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['label'] as String,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(r['desc'] as String,
                        style: const TextStyle(fontSize: 11, color: _kTextSub)),
                  ],
                )),
              ]),
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

  Widget _buildField(
    String label,
    TextEditingController ctrl,
    IconData icon,
    String hint, {
    TextInputType type = TextInputType.text,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(label),
      const SizedBox(height: 8),
      TextField(
        controller: ctrl,
        keyboardType: type,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500, color: _kText),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: _kTextSub.withValues(alpha: 0.6), fontSize: 14),
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
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        ),
      ),
    ]);
  }

  Widget _buildPasswordField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _pass,
        obscureText: _obscure,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500, color: _kText),
        decoration: InputDecoration(
          hintText: 'Min 6 characters',
          hintStyle: TextStyle(color: _kTextSub.withValues(alpha: 0.6), fontSize: 14),
          prefixIcon: Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 20),
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
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        ),
      ),
    ]);
  }

  Widget _buildPrimaryButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _loading ? null : _signup,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                    )
                  ],
          ),
          child: Container(
            alignment: Alignment.center,
            child: _loading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Create Account',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _kTextSub,
          letterSpacing: 0.3));
}