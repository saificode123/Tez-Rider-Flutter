import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ProfileRead = Future<dynamic> Function(String account);
typedef ProfileWrite =
    Future<dynamic> Function(Map<String, dynamic> parameters);

/// Canonical profile edits use the already deployed, validated registration API.
/// Email, role, verification and identity documents are never editable here.
class ProfileService {
  ProfileService({
    ProfileRead? read,
    ProfileWrite? write,
    String? Function()? identity,
    Stream<void>? accountChanges,
  }) : _read =
           read ??
           ((id) => Supabase.instance.client
               .from('users')
               .select('id,name,phone,email,role,profile_image')
               .eq('auth_user_id', id)
               .single()
               .timeout(const Duration(seconds: 15))),
       _write =
           write ??
           ((parameters) => Supabase.instance.client
               .rpc('final2_complete_registration', params: parameters)
               .timeout(const Duration(seconds: 15))),
       _identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id),
       accountChanges =
           accountChanges ??
           (identity != null
               ? const Stream<void>.empty()
               : Supabase.instance.client.auth.onAuthStateChange.map((_) {}));
  final ProfileRead _read;
  final ProfileWrite _write;
  final String? Function() _identity;
  final Stream<void> accountChanges;
  String? get account => _identity();
  static const roles = {'customer', 'vendor', 'rider', 'admin'};
  bool busy = false;
  String _signedIn() => account ?? (throw StateError('Sign in required.'));
  void _same(String original) {
    if (account != original) {
      throw StateError('Account changed. Open your profile again.');
    }
  }

  Future<Map<String, dynamic>> load() async {
    final original = _signedIn();
    final value = await _read(original);
    _same(original);
    if (value is! Map ||
        value['id'] is! int ||
        value['id'] <= 0 ||
        value['name'] is! String ||
        value['email'] is! String ||
        (value['phone'] != null && value['phone'] is! String) ||
        !roles.contains(value['role'])) {
      throw const FormatException('Profile could not be confirmed.');
    }
    return Map<String, dynamic>.from(value);
  }

  static String? validate(String name, String phone) {
    if (name.trim().isEmpty ||
        name.trim().length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      return 'Enter your name (up to 120 characters).';
    }
    if (phone.trim().isEmpty ||
        phone.trim().length > 32 ||
        !RegExp(r'^[+0-9() .-]+$').hasMatch(phone.trim()) ||
        !RegExp(r'[0-9]').hasMatch(phone)) {
      return 'Enter a valid phone number.';
    }
    return null;
  }

  Future<Map<String, dynamic>> save(String name, String phone) async {
    if (busy) throw StateError('Profile is being saved.');
    final error = validate(name, phone);
    if (error != null) throw FormatException(error);
    final original = _signedIn();
    busy = true;
    try {
      final value = await _write({
        'p_name': name.trim(),
        'p_phone': phone.trim(),
        'p_update_profile': true,
      });
      _same(original);
      if (value is! Map ||
          value['code'] != 'OK' ||
          value['id'] is! int ||
          value['id'] <= 0 ||
          value['name'] != name.trim() ||
          value['phone'] != phone.trim() ||
          !roles.contains(value['role'])) {
        throw const FormatException('Profile changes could not be confirmed.');
      }
      return Map<String, dynamic>.from(value);
    } finally {
      busy = false;
    }
  }
}
