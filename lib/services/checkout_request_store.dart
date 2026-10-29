import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_timeout_service.dart';

/// Account-bound unresolved checkout; never expires an ambiguous submission.
class SecureCheckoutRequestStore implements CheckoutRequestStore {
  SecureCheckoutRequestStore({
    FlutterSecureStorage? storage,
    String? Function()? currentAccount,
    String? expectedAccount,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _currentAccount =
           currentAccount ??
           (() => Supabase.instance.client.auth.currentUser?.id) {
    _owner = expectedAccount ?? _currentAccount();
  }

  final FlutterSecureStorage _storage;
  final String? Function() _currentAccount;
  late final String? _owner;
  static const _timeout = Duration(seconds: 8);

  @override
  String? get identity =>
      _owner != null && _currentAccount() == _owner ? _owner : null;

  String get _key {
    final account = identity;
    if (account == null) throw StateError('Sign in again before checkout.');
    return 'tezrider.checkout.pending.v1.$account';
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    final key = _key;
    final raw = await _storage.read(key: key).timeout(_timeout);
    if (_key != key) throw StateError('Checkout account changed.');
    if (raw == null) return null;
    if (raw.length > 65536) throw StateError('Saved checkout requires review.');
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw StateError('Saved checkout requires review.');
    }
    return value;
  }

  @override
  Future<void> write(Map<String, dynamic> request) async {
    final key = _key, raw = jsonEncode(request);
    if (raw.length > 65536) throw StateError('Checkout details are too large.');
    await _storage.write(key: key, value: raw).timeout(_timeout);
    final saved = await _storage.read(key: key).timeout(_timeout);
    if (_key != key || saved != raw) {
      throw StateError('Secure checkout storage was not confirmed. Retry.');
    }
  }

  @override
  Future<void> clear() async {
    final key = _key;
    await _storage.delete(key: key).timeout(_timeout);
    if (_key != key ||
        await _storage.read(key: key).timeout(_timeout) != null) {
      throw StateError('Checkout cleanup was not confirmed. Retry.');
    }
  }
}
