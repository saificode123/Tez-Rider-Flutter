import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileEmailState {
  const ProfileEmailState(this.email, this.pendingEmail);
  final String email;
  final String? pendingEmail;
}

/// Auth owns the change/confirmation; the canonical profile changes server-side
/// only when Auth's verified email really changes. A request is not delivery.
class ProfileEmailService {
  ProfileEmailService({
    Future<dynamic> Function()? read,
    Future<User?> Function(String)? request,
    String? Function()? identity,
    Stream<void>? accountChanges,
  }) : _read = read ?? _readCurrent,
       _request =
           request ??
           ((email) async =>
               (await Supabase.instance.client.auth
                       .updateUser(UserAttributes(email: email))
                       .timeout(const Duration(seconds: 20)))
                   .user),
       _identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id),
       accountChanges =
           accountChanges ??
           (identity != null
               ? const Stream<void>.empty()
               : Supabase.instance.client.auth.onAuthStateChange.map((_) {}));
  final Future<dynamic> Function() _read;
  final Future<User?> Function(String) _request;
  final String? Function() _identity;
  final Stream<void> accountChanges;
  String? get account => _identity();
  bool busy = false;

  static Future<dynamic> _readCurrent() async {
    final client = Supabase.instance.client;
    final owner = client.auth.currentUser?.id;
    final value = await client
        .rpc('final_delivery_email_status')
        .timeout(const Duration(seconds: 15));
    if (value is Map &&
        value['code'] == 'OK' &&
        value['account'] == owner &&
        value['email'] is String &&
        client.auth.currentUser?.id == owner &&
        value['email'] != client.auth.currentUser?.email) {
      // Confirmation may finish in the user's browser. Refresh the SDK's token
      // and cached user only after canonical server confirmation, so legacy
      // email displays and the existing secure refresh-token copy stay aligned.
      final refreshed = await client.auth.refreshSession().timeout(
        const Duration(seconds: 15),
      );
      if (refreshed.user?.id != owner ||
          refreshed.user?.email != value['email']) {
        throw StateError('Confirmed email session could not be refreshed');
      }
    }
    return value;
  }

  static bool valid(String email) =>
      email.length <= 254 &&
      RegExp(
        r'^[^@\s\x00-\x1f\x7f]+@[^@\s\x00-\x1f\x7f]+\.[^@\s\x00-\x1f\x7f]+$',
      ).hasMatch(email);

  Future<ProfileEmailState> load() async {
    final owner = account;
    if (owner == null) throw StateError('Sign in required');
    final result = await _read();
    if (account != owner) throw StateError('Account changed');
    if (result is! Map ||
        result['code'] != 'OK' ||
        result['account'] != owner ||
        result['verified'] != true ||
        result['email'] is! String ||
        !valid(result['email']) ||
        (result['pending_email'] != null &&
            (result['pending_email'] is! String ||
                !valid(result['pending_email'])))) {
      throw const FormatException('Email status could not be verified.');
    }
    return ProfileEmailState(result['email'], result['pending_email']);
  }

  Future<ProfileEmailState> request(String email) async {
    final target = email.trim();
    if (!valid(target))
      throw const FormatException('Enter a valid new email address.');
    if (busy) throw StateError('Email request already in progress');
    final owner = account;
    if (owner == null) throw StateError('Sign in required');
    busy = true;
    try {
      // Recheck the live canonical account immediately before the Auth write.
      // Reopening/retrying an already-pending request must not resend mail.
      final before = await load();
      if (before.pendingEmail != null) {
        if (before.pendingEmail!.toLowerCase() == target.toLowerCase())
          return before;
        throw StateError('An email change is already awaiting confirmation.');
      }
      if (before.email.toLowerCase() == target.toLowerCase()) {
        throw const FormatException('Enter a valid new email address.');
      }
      final user = await _request(target);
      if (account != owner || user?.id != owner)
        throw StateError('Account changed');
      final status = await load();
      if (status.email.toLowerCase() != target.toLowerCase() &&
          status.pendingEmail?.toLowerCase() != target.toLowerCase()) {
        throw const FormatException(
          'Email change request could not be confirmed.',
        );
      }
      return status;
    } finally {
      busy = false;
    }
  }
}
