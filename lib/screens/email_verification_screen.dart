import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/email_verification.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    this.email = '',
    this.notice,
    this.service,
    this.recentlyRequested = false,
  });
  final String email;
  final String? notice;
  final EmailVerificationService? service;
  final bool recentlyRequested;
  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  late final _email = TextEditingController(text: widget.email);
  late final _service =
      widget.service ??
      EmailVerificationService(recentlyRequested: widget.recentlyRequested);
  late final Timer _timer;
  String? _notice;
  bool _checking = false;
  @override
  void initState() {
    super.initState();
    _notice = widget.notice;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _email.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    if (_service.busy || _checking) return;
    setState(() {});
    final operation = _service.request(_email.text);
    setState(() {});
    final code = await operation;
    if (!mounted) return;
    setState(
      () => _notice = switch (code) {
        'REQUEST_ACCEPTED' =>
          'Verification requested. Check your inbox and spam folder. Delivery is not yet confirmed.',
        'INVALID_EMAIL' => 'Enter a valid email address.',
        'COOLDOWN' || 'RATE_LIMIT' =>
          'Please wait before requesting another verification email.',
        'EMAIL_CONFIGURATION' =>
          'Verification email is not configured for this address. Contact support.',
        _ =>
          'Verification request could not be confirmed. Wait before retrying.',
      },
    );
  }

  Future<void> _check() async {
    if (_checking || _service.busy) return;
    setState(() => _checking = true);
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) {
        if (mounted) {
          setState(
            () => _notice =
                'Open the genuine verification link, then sign in with your password.',
          );
        }
        return;
      }
      final user = (await client.auth.getUser().timeout(
        const Duration(seconds: 12),
      )).user;
      if (!mounted) return;
      if (user == null ||
          user.id != client.auth.currentUser?.id ||
          user.emailConfirmedAt == null ||
          user.email?.toLowerCase() != _email.text.trim().toLowerCase()) {
        setState(
          () => _notice =
              'Email confirmation has not been verified for this account.',
        );
        return;
      }
      Get.offAllNamed(
        '/',
      ); // Existing live Auth/profile/Admin routing, never a role supplied by a link.
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Email confirmation could not be checked. Retry when connected.',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final busy = _service.busy || _checking;
    return Scaffold(
      appBar: AppBar(title: Text('Verify your email'.tr)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Open the genuine email confirmation link. Email verification does not approve Rider identity.'
                    .tr,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                maxLength: 254,
                decoration: InputDecoration(labelText: 'Email'.tr),
              ),
              if (busy) const LinearProgressIndicator(),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_notice!.tr),
                ),
              FilledButton(
                onPressed: busy || _service.remainingSeconds > 0
                    ? null
                    : _resend,
                child: Text('Resend verification email'.tr),
              ),
              if (_service.remainingSeconds > 0)
                Text(
                  '${'Retry in'.tr} ${_service.remainingSeconds} ${'seconds'.tr}',
                ),
              TextButton(
                onPressed: busy ? null : _check,
                child: Text('I have verified my email'.tr),
              ),
              TextButton(
                onPressed: busy ? null : () => Get.offAllNamed('/login'),
                child: Text('Return to Login'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
