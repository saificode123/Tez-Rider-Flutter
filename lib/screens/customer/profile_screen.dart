import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import '../../services/profile_service.dart';
import '../../widgets/private_photo_editor.dart';
import '../../widgets/language_settings_tile.dart';

const _kPurple = Color(0xFF1B5E20);
const _kBg = Color(0xFFF8F7FF);
const _kCard = Color(0xFFFFFFFF);
const _kTextSub = Color(0xFF6B6B8A);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.service});
  final ProfileService? service;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final ProfileService _service;
  StreamSubscription<void>? _accountSubscription;
  String? _account;
  int _generation = 0;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _profileError;
  String? _saveNotice;
  String _email = '';
  String? _photo;
  String _role = 'customer';
  late final AnimationController _rewardPulseCtrl;
  late final Animation<double> _rewardPulseAnim;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProfileService();
    _account = _service.account;
    _accountSubscription = _service.accountChanges.listen((_) {
      if (!mounted || _service.account == _account) return;
      _account = _service.account;
      _generation++;
      _nameCtrl.clear();
      _phoneCtrl.clear();
      setState(() {
        _email = '';
        _photo = null;
        _role = '';
        _saveNotice = null;
        _loading = false;
        _profileError = 'Account changed. Open your profile again.';
      });
    });
    _rewardPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _rewardPulseAnim = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_rewardPulseCtrl);
    _rewardPulseCtrl.repeat(reverse: true);
    _loadProfile();
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_accountSubscription?.cancel());
    _rewardPulseCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _profileError = null;
    });
    final generation = ++_generation;
    try {
      final rec = await _service.load();
      if (mounted && generation == _generation) {
        _nameCtrl.text = rec['name'];
        _phoneCtrl.text = rec['phone'] ?? '';
        _email = rec['email'];
        _photo = rec['profile_image'] as String?;
        _role = rec['role'];
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        _profileError = 'Profile could not be loaded. Please retry.';
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_loading || _profileError != null || _service.account != _account) {
      return;
    }
    final error = ProfileService.validate(_nameCtrl.text, _phoneCtrl.text);
    if (error != null) {
      Get.snackbar("Error".tr, error, snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final generation = _generation;
    setState(() {
      _saving = true;
      _saveNotice = null;
    });
    try {
      final rec = await _service.save(_nameCtrl.text, _phoneCtrl.text);
      if (!mounted || generation != _generation) return;
      setState(() {
        _nameCtrl.text = rec['name'];
        _phoneCtrl.text = rec['phone'];
        _saveNotice = 'Profile updated successfully.';
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      Get.snackbar(
        "Error".tr,
        "Profile changes could not be confirmed. Please retry.".tr,
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final initial = _nameCtrl.text.isNotEmpty
        ? _nameCtrl.text[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPurple,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "My Profile".tr,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving || _loading || _profileError != null
                ? null
                : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    "Save".tr,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2),
            )
          : _profileError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_profileError!),
                  TextButton(onPressed: _loadProfile, child: Text("Retry".tr)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (_saveNotice != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _saveNotice!,
                        style: const TextStyle(
                          color: _kPurple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),

                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _kPurple.withValues(alpha: 0.30),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (widget.service == null)
                    PrivatePhotoEditor(
                      key: ValueKey(_account),
                      reference: _photo,
                      canUpload: !_saving && !_loading && _profileError == null,
                      onSaved: (value) => setState(() => _photo = value),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    _email,
                    style: const TextStyle(color: _kTextSub, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _kPurple.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _role.capitalizeFirst ?? _role,
                      style: const TextStyle(
                        color: _kPurple,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        ScaleTransition(
                          scale: _rewardPulseAnim,
                          child: Lottie.asset(
                            'assets/lottie/rewards.json',
                            width: 64,
                            height: 64,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "TezRider Rewards".tr,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Reward balance unavailable".tr,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Rewards are not currently configured.".tr,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Container(
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: _kPurple.withValues(alpha: 0.07),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _field(
                          _nameCtrl,
                          "Full Name".tr,
                          Icons.person_outline,
                          TextInputType.name,
                        ),
                        const SizedBox(height: 16),
                        _field(
                          _phoneCtrl,
                          "Phone Number".tr,
                          Icons.phone_outlined,
                          TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _kBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _kPurple.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.email_outlined,
                                color: _kTextSub,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _email,
                                  style: const TextStyle(
                                    color: _kTextSub,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Text(
                                "read-only".tr,
                                style: TextStyle(
                                  color: Color(0xFFB0B0C0),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const LanguageSettingsTile(),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _saving || _loading || _profileError != null
                          ? null
                          : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _saving
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                          : Text(
                              "Save Changes".tr,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon,
    TextInputType type,
  ) {
    return TextField(
      controller: ctrl,
      enabled: !_saving,
      onChanged: (_) {
        if (_saveNotice != null) setState(() => _saveNotice = null);
      },
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _kPurple, size: 20),
        filled: true,
        fillColor: _kBg,
        labelStyle: const TextStyle(color: _kTextSub),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
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
