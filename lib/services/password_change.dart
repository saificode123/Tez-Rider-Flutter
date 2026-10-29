import 'package:supabase_flutter/supabase_flutter.dart';

/// New passwords go only to Auth over its existing TLS client. No old password,
/// logging, preferences or database profile writes.
class PasswordChangeService {
  PasswordChangeService({
    String? Function()? identity,
    Future<String?> Function()? verify,
    Future<String?> Function(String)? update,
  }) : _identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id),
       _verify =
           verify ??
           (() async => (await Supabase.instance.client.auth.getUser().timeout(
             const Duration(seconds: 12),
           )).user?.id),
       _update =
           update ??
           ((password) async =>
               (await Supabase.instance.client.auth
                       .updateUser(UserAttributes(password: password))
                       .timeout(const Duration(seconds: 15)))
                   .user
                   ?.id) {
    _owner = _identity();
  }
  final String? Function() _identity;
  final Future<String?> Function() _verify;
  final Future<String?> Function(String) _update;
  late final String? _owner;
  String? get account => _owner;
  bool get isCurrentAccount => _owner != null && _identity() == _owner;
  bool busy = false;
  Future<String> change(String password, String confirmation) async {
    if (busy) return 'BUSY';
    if (password.length < 12) return 'WEAK_PASSWORD';
    if (password != confirmation) return 'MISMATCH';
    final owner = _owner;
    if (owner == null || _identity() == null) return 'SIGN_IN_REQUIRED';
    if (!isCurrentAccount) return 'ACCOUNT_CHANGED';
    busy = true;
    try {
      if (await _verify() != owner || _identity() != owner) {
        return 'ACCOUNT_CHANGED';
      }
      final updated = await _update(password);
      return updated == owner && _identity() == owner
          ? 'UPDATED'
          : 'UNCONFIRMED';
    } catch (_) {
      return 'UNCONFIRMED';
    } finally {
      busy = false;
    }
  }
}
