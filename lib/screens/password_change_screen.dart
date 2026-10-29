import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/auth_controller.dart';
import '../services/password_change.dart';

class PasswordChangeScreen extends StatefulWidget {
  const PasswordChangeScreen({super.key, this.service});
  final PasswordChangeService? service;
  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  late final _service = widget.service ?? PasswordChangeService();
  bool _updated = false, _closing = false;
  String? _notice;
  @override
  void dispose() {
    _password.clear();
    _confirmation.clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (_service.busy || _updated) return;
    final operation = _service.change(_password.text, _confirmation.text);
    setState(() {});
    final result = await operation;
    if (!mounted) return;
    setState(() {
      _updated = result == 'UPDATED';
      if (_updated) {
        _password.clear();
        _confirmation.clear();
      }
      _notice = switch (result) {
        'UPDATED' =>
          'Password updated. Sign out all sessions, then sign in with your new password.',
        'WEAK_PASSWORD' =>
          'Use a new, unique password with at least 12 characters.',
        'MISMATCH' => 'Passwords do not match.',
        'SIGN_IN_REQUIRED' ||
        'ACCOUNT_CHANGED' => 'Sign in again before changing your password.',
        _ =>
          'Password change could not be confirmed. No success is claimed. Check your account before retrying.',
      };
    });
  }

  Future<void> _finish() async {
    if (!_updated || _closing) return;
    setState(() => _closing = true);
    try {
      if (!_service.isCurrentAccount) {
        throw StateError('Account changed');
      }
      await Supabase.instance.client.auth
          .signOut(scope: SignOutScope.global)
          .timeout(const Duration(seconds: 15));
      final current = Supabase.instance.client.auth.currentUser?.id;
      if (current != null && current != _service.account) {
        throw StateError('Account changed');
      }
      if (Get.isRegistered<AuthController>()) {
        await Get.find<AuthController>().logout(navigate: false);
      }
      if (mounted) Get.offAllNamed('/login');
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Password updated. Signing out all sessions was not confirmed. Retry sign-out.',
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final busy = _service.busy || _closing;
    return PopScope(
      canPop: !busy && !_updated,
      child: Scaffold(
        appBar: AppBar(title: Text('Change password'.tr)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter a strong, unique new password here. Never share it in chat.'
                      .tr,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  enabled: !busy && !_updated,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(labelText: 'New password'.tr),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmation,
                  enabled: !busy && !_updated,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Confirm new password'.tr,
                  ),
                ),
                if (busy) const LinearProgressIndicator(),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(_notice!.tr),
                  ),
                if (!_updated)
                  FilledButton(
                    onPressed: busy ? null : _change,
                    child: Text('Update password'.tr),
                  ),
                if (_updated)
                  FilledButton(
                    onPressed: busy ? null : _finish,
                    child: Text('Sign out all sessions'.tr),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
