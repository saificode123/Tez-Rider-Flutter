import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

const testAuthEmailRedirect = 'tezrider-fr21-test://login-callback/';

String registrationEmailError(String status, String message, {String? code}) {
  final lower = message.toLowerCase();
  if (const [
        'email_address_not_authorized',
        'email_provider_disabled',
        'email_not_allowed',
      ].contains(code) ||
      lower.contains('sending confirmation email')) {
    return 'Verification email could not be submitted. Contact support before retrying.';
  }
  if (const ['user_already_exists', 'email_exists'].contains(code) ||
      lower.contains('already registered') ||
      lower.contains('already been registered') ||
      lower.contains('already exists')) {
    return 'This email is already registered. Try signing in instead.';
  }
  if (status == '429' ||
      const [
        'over_email_send_rate_limit',
        'over_request_rate_limit',
      ].contains(code) ||
      lower.contains('rate limit') ||
      lower.contains('too many')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (code == 'weak_password' ||
      lower.contains('weak password') ||
      lower.contains('password should be')) {
    return 'Password is too weak. Use at least 6 characters with letters and numbers.';
  }
  if (code == 'email_address_invalid' ||
      lower.contains('invalid email') ||
      lower.contains('unable to validate email')) {
    return 'Invalid email address. Please check and try again.';
  }
  if (code == 'signup_disabled' ||
      (lower.contains('signup') && lower.contains('disabled'))) {
    return 'New registrations are currently disabled. Please contact support.';
  }
  return 'Sign up could not be confirmed. Retry.';
}

/// Only the configured TEST app callback can start an Auth link exchange.
/// Tokens/codes remain inside the SDK; only a one-shot routing flag is kept.
class AuthEmailLink {
  static bool _pending = false;
  static bool accept(Uri uri) {
    try {
      final allowed =
          uri.scheme == 'tezrider-fr21-test' &&
          uri.host == 'login-callback' &&
          (uri.path.isEmpty || uri.path == '/') &&
          uri.userInfo.isEmpty &&
          !uri.hasPort;
      final values = {
        ...uri.queryParameters,
        ...Uri.splitQueryString(uri.fragment),
      };
      final callback =
          allowed &&
          const [
            'code',
            'access_token',
            'error',
            'error_code',
            'error_description',
          ].any(values.containsKey);
      if (callback) _pending = true;
      return callback;
    } on FormatException {
      return false;
    }
  }

  static bool consume() {
    final value = _pending;
    _pending = false;
    return value;
  }
}

class EmailVerificationService {
  EmailVerificationService({
    Future<void> Function(String)? send,
    Duration Function()? elapsed,
    bool recentlyRequested = false,
  }) : _send = send ?? ((email) => resendWith(Supabase.instance.client, email)),
       _elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter {
    if (recentlyRequested) _lastAttempt = _elapsed();
  }
  final Future<void> Function(String) _send;
  final Duration Function() _elapsed;
  Duration? _lastAttempt;
  bool busy = false;
  int get remainingSeconds {
    final last = _lastAttempt;
    if (last == null) return 0;
    final remaining = const Duration(seconds: 60) - (_elapsed() - last);
    return remaining.inMilliseconds <= 0
        ? 0
        : (remaining.inMilliseconds / 1000).ceil();
  }

  static bool valid(String email) =>
      email.length <= 254 &&
      RegExp(
        r'^[^@\s\x00-\x1f\x7f]+@[^@\s\x00-\x1f\x7f]+\.[^@\s]+$',
      ).hasMatch(email);
  static Future<void> resendWith(SupabaseClient client, String email) async {
    await client.auth
        .resend(
          type: OtpType.signup,
          email: email,
          emailRedirectTo: testAuthEmailRedirect,
        )
        .timeout(const Duration(seconds: 20));
  }

  Future<String> request(String email) async {
    final target = email.trim();
    if (!valid(target)) return 'INVALID_EMAIL';
    if (busy) return 'BUSY';
    if (remainingSeconds > 0) return 'COOLDOWN';
    busy = true;
    // An uncertain request may have sent mail. Do not permit immediate retries.
    _lastAttempt = _elapsed();
    try {
      await _send(target);
      return 'REQUEST_ACCEPTED'; // Neither account existence nor delivery proven.
    } on AuthException catch (error) {
      if (const [
            'over_email_send_rate_limit',
            'over_request_rate_limit',
          ].contains(error.code) ||
          error.statusCode == '429') {
        return 'RATE_LIMIT';
      }
      if (const [
        'email_address_not_authorized',
        'email_provider_disabled',
        'email_address_invalid',
        'email_not_allowed',
      ].contains(error.code)) {
        return 'EMAIL_CONFIGURATION';
      }
      return 'SEND_UNCONFIRMED';
    } catch (_) {
      return 'SEND_UNCONFIRMED';
    } finally {
      busy = false;
    }
  }
}

extension on Stopwatch {
  Duration elapsedGetter() => elapsed;
}
