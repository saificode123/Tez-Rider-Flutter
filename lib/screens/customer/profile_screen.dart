import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kPurple  = Color(0xFF1B5E20);
const _kBg      = Color(0xFFF8F7FF);
const _kCard    = Color(0xFFFFFFFF);
const _kTextSub = Color(0xFF6B6B8A);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = true;
  bool _saving  = false;
  String _email = '';
  String _role  = 'customer';
  late final AnimationController _rewardPulseCtrl;
  late final Animation<double> _rewardPulseAnim;
  final int _rewardPoints = 120;

  @override
  void initState() {
    super.initState();
    _rewardPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _rewardPulseAnim = Tween<double>(begin: 0.95, end: 1.05)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_rewardPulseCtrl);
    _rewardPulseCtrl.repeat(reverse: true);
    _loadProfile();
  }

  @override
  void dispose() {
    _rewardPulseCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final rec = await _supabase
          .from('users')
          .select('name, phone, email, role')
          .eq('email', user.email!)
          .maybeSingle();
      if (rec != null && mounted) {
        _nameCtrl.text  = rec['name']  ?? '';
        _phoneCtrl.text = rec['phone'] ?? '';
        _email = rec['email'] ?? user.email ?? '';
        _role  = rec['role']  ?? 'customer';
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      Get.snackbar('Error', 'Name cannot be empty.',
          backgroundColor: Colors.redAccent, colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24), borderRadius: 14);
      return;
    }
    setState(() => _saving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase.from('users').update({
        'name':  _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      }).eq('email', user.email!);

      // Keep auth metadata in sync too — the dashboard greeting and
      // profile header read the name from here, not the users table.
      await _supabase.auth.updateUser(
        UserAttributes(data: {'name': _nameCtrl.text.trim()}),
      );

      if (mounted) setState(() {});
      Get.snackbar('Saved ✅', 'Profile updated successfully.',
          backgroundColor: _kPurple, colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          borderRadius: 14, duration: const Duration(seconds: 2));
    } catch (e) {
      Get.snackbar('Error', 'Failed to save: $e',
          backgroundColor: Colors.redAccent, colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = _nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPurple,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Profile',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const SizedBox(height: 12),

                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: _kPurple.withValues(alpha: 0.30),
                          blurRadius: 20, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Center(
                    child: Text(initial,
                        style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(_email, style: const TextStyle(color: _kTextSub, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: _kPurple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_role.capitalizeFirst ?? _role,
                      style: const TextStyle(color: _kPurple, fontSize: 11, fontWeight: FontWeight.w700)),
                ),

                const SizedBox(height: 24),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(children: [
                    ScaleTransition(
                      scale: _rewardPulseAnim,
                      child: Lottie.asset('assets/lottie/rewards.json', width: 64, height: 64),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('TezRider Rewards',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('$_rewardPoints points available',
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      const Text('Keep ordering to unlock exclusive rewards!',
                          style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ])),
                  ]),
                ),

                const SizedBox(height: 24),

                Container(
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: _kPurple.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 5)),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    _field(_nameCtrl, 'Full Name', Icons.person_outline, TextInputType.name),
                    const SizedBox(height: 16),
                    _field(_phoneCtrl, 'Phone Number', Icons.phone_outlined, TextInputType.phone),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _kBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _kPurple.withValues(alpha: 0.12)),
                      ),
                      child: Row(children: [
                        Icon(Icons.email_outlined, color: _kTextSub, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_email,
                            style: const TextStyle(color: _kTextSub, fontSize: 14))),
                        const Text('read-only',
                            style: TextStyle(color: Color(0xFFB0B0C0), fontSize: 10)),
                      ]),
                    ),
                  ]),
                ),

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity, height: 54,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        : const Text('Save Changes',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, TextInputType type) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _kPurple, size: 20),
        filled: true,
        fillColor: _kBg,
        labelStyle: const TextStyle(color: _kTextSub),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _kPurple.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kPurple, width: 1.5),
        ),
      ),
    );
  }
}