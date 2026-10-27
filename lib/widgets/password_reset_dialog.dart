import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_action_button.dart';

class PasswordResetDialog extends StatefulWidget {
  const PasswordResetDialog({super.key, required this.email});
  final String email;

  @override
  State<PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<PasswordResetDialog> {
  late final _email = TextEditingController(text: widget.email);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!GetUtils.isEmail(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      Navigator.of(context).pop();
      Get.snackbar('Email Sent'.tr, 'Check your inbox for the reset link.'.tr);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not send reset email. Check the address.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text('Reset Password'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("Enter your email and we'll send you a reset link.".tr),
              const SizedBox(height: 20),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                autofocus: true,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  labelText: 'Email Address'.tr,
                  errorText: _error?.tr,
                  prefixIcon: const Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 20),
              AppActionButton(
                label: 'Send Link'.tr,
                busy: _busy,
                onPressed: _send,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text('Cancel'.tr),
          ),
        ],
      ),
    );
  }
}
