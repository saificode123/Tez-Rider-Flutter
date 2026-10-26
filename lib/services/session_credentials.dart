import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
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
  static const _coldReadTimeout = Duration(seconds: 8);
  bool _storageWarmed = false;
  Future<String?> _readSecure(String key) async {
    // Android must initialize its keystore on the first native read. Keep that
    // bounded without treating a slower cold start as an explicit logout.
    final value = await storage
        .read(key: key)
        .timeout(_storageWarmed ? _storageTimeout : _coldReadTimeout);
    _storageWarmed = true;
    return value;
  }

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
    for (final key in [
      'tr_refresh',
      'tr_role',
      'tr_account',
      'bio_account',
      'bio_enabled',
    ]) {
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

  Future<void> remember(
    Session session,
    String role, {
    bool preserveBiometric = false,
  }) async {
    // Password/server authorization must precede this call. Partial writes
    // never enable restoration or a leftover credential from another account.
    final keepBiometric =
        preserveBiometric && await biometricEnabled(session.user.id);
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
      if (keepBiometric) await setBiometricEnabled(session.user.id, true);
    } catch (_) {
      await invalidate();
      throw StateError(secureSessionUnavailable);
    }
  }

  /// A legacy device-wide flag never grants enrollment to another account.
  Future<bool> biometricEnabled(String account) async {
    if (!await restorationAllowed()) return false;
    try {
      return await _readSecure('bio_enabled') == 'true' &&
          await _readSecure('bio_account') == account &&
          (await read(currentAccount: account)) != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricEnabled(String account, bool enabled) async {
    if (!enabled) {
      // Clear the enabling flag first: partial cleanup cannot authorize entry.
      await storage
          .write(key: 'bio_enabled', value: 'false')
          .timeout(_storageTimeout);
      await storage.delete(key: 'bio_account').timeout(_storageTimeout);
      return;
    }
    if (await read(currentAccount: account) == null) {
      throw StateError(secureSessionUnavailable);
    }
    try {
      await storage
          .write(key: 'bio_account', value: account)
          .timeout(_storageTimeout);
      await storage
          .write(key: 'bio_enabled', value: 'true')
          .timeout(_storageTimeout);
    } catch (_) {
      await invalidate();
      throw StateError(secureSessionUnavailable);
    }
  }

  /// SDK refresh-token rotation must update only the remembered account.
  Future<void> synchronize(Session session) async {
    final saved = await read(currentAccount: session.user.id);
    final token = session.refreshToken;
    if (saved == null || token == null || token.isEmpty || _denied) return;
    try {
      await storage
          .write(key: 'tr_refresh', value: token)
          .timeout(_storageTimeout);
    } catch (_) {
      await invalidate();
    }
  }

  Future<SavedSessionCredentials?> read({String? currentAccount}) async {
    if (!await restorationAllowed()) return null;
    try {
      final enabled = await _readSecure('user_logged_in');
      final account = await _readSecure('tr_account');
      final token = await _readSecure('tr_refresh');
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
    } on TimeoutException {
      // An unanswered read proves neither corruption nor logout. Deny this
      // attempt, retaining the existing account binding for a later retry.
      if (kDebugMode) debugPrint('Secure session read temporarily unavailable');
      return null;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Secure session read unavailable (${error.runtimeType})');
      }
      await invalidate();
      return null;
    }
  }
}
