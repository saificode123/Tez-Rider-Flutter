import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const secureSessionUnavailable =
    'Secure sign-in storage is unavailable. Please sign in again or retry.';

class SavedSessionCredentials {
  const SavedSessionCredentials(this.account, this.refreshToken);
  final String account;
  final String refreshToken;
}

/// Existing secure keys plus a nonsecret logout tombstone in the SDK's already
/// available local-storage adapter. No token is stored in the tombstone.
class SessionCredentials {
  SessionCredentials({FlutterSecureStorage? secureStorage, LocalStorage? fence})
    : storage = secureStorage ?? const FlutterSecureStorage(),
      _fence =
          fence ??
          SharedPreferencesLocalStorage(
            persistSessionKey: 'tezrider.logout.pending',
          );

  final FlutterSecureStorage storage;
  final LocalStorage _fence;
  Future<void>? _ready;
  static const _storageTimeout = Duration(seconds: 2);
  bool _denied = false;
  bool get denied => _denied;
  Future<void> _initialize() async {
    try {
      await (_ready ??= _fence.initialize()).timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      _ready = null;
      rethrow;
    }
  }

  Future<bool> restorationAllowed() async {
    if (_denied) return false;
    try {
      await _initialize();
      _denied =
          await _fence.accessToken().timeout(const Duration(seconds: 2)) !=
          null;
      return !_denied;
    } catch (_) {
      _denied = true;
      return false;
    }
  }

  Future<void> invalidate() async {
    _denied = true;
    try {
      await _initialize();
      await _fence
          .persistSession('pending')
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Deny in memory even when both storage mechanisms are unavailable.
    }
    // Each key is attempted independently; one corrupt key cannot skip others.
    for (final key in ['tr_refresh', 'tr_role', 'tr_account']) {
      try {
        await storage.delete(key: key).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    try {
      await storage
          .write(key: 'user_logged_in', value: 'false')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> remember(Session session, String role) async {
    // Password/server authorization must precede this call. Partial writes
    // never enable restoration or a leftover credential from another account.
    await invalidate();
    try {
      final refresh = session.refreshToken;
      if (refresh == null || refresh.isEmpty) {
        throw StateError('Missing session');
      }
      await storage
          .write(key: 'tr_refresh', value: refresh)
          .timeout(_storageTimeout);
      await storage.write(key: 'tr_role', value: role).timeout(_storageTimeout);
      await storage
          .write(key: 'tr_account', value: session.user.id)
          .timeout(_storageTimeout);
      await storage
          .write(key: 'user_logged_in', value: 'true')
          .timeout(_storageTimeout);
      await _initialize();
      await _fence.removePersistedSession().timeout(_storageTimeout);
      if (await _fence.accessToken().timeout(_storageTimeout) != null) {
        throw StateError('Logout fence not cleared');
      }
      _denied = false;
    } catch (_) {
      await invalidate();
      throw StateError(secureSessionUnavailable);
    }
  }

  Future<SavedSessionCredentials?> read({String? currentAccount}) async {
    if (!await restorationAllowed()) return null;
    try {
      final enabled = await storage
          .read(key: 'user_logged_in')
          .timeout(_storageTimeout);
      final account = await storage
          .read(key: 'tr_account')
          .timeout(_storageTimeout);
      final token = await storage
          .read(key: 'tr_refresh')
          .timeout(_storageTimeout);
      if (enabled != 'true' ||
          account == null ||
          account.isEmpty ||
          token == null ||
          token.isEmpty ||
          token.length > 8192 ||
          RegExp(r'\s|[\x00-\x1f]').hasMatch(token) ||
          (currentAccount != null && account != currentAccount)) {
        return null;
      }
      return SavedSessionCredentials(account, token);
    } catch (_) {
      await invalidate();
      return null;
    }
  }
}
