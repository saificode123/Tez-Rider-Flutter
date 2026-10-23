import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrationData {
  const RegistrationData({
    required this.name,
    required this.phone,
    required this.role,
    this.storeName = '',
    this.storeAddress = '',
  });
  final String name, phone, role, storeName, storeAddress;
  String? get error {
    if (!const {'customer', 'vendor', 'rider'}.contains(role)) {
      return 'Choose a valid registration role.';
    }
    if (name.trim().isEmpty ||
        name.trim().length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      return 'Enter your name (up to 120 characters).';
    }
    if (phone.trim().isEmpty ||
        phone.length > 32 ||
        !RegExp(r'^[+0-9() .-]+$').hasMatch(phone) ||
        !RegExp(r'[0-9]').hasMatch(phone)) {
      return 'Enter a valid phone number.';
    }
    if (role == 'vendor' &&
        (storeName.trim().isEmpty ||
            storeName.trim().length > 200 ||
            storeAddress.trim().isEmpty ||
            storeAddress.trim().length > 500 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch('$storeName$storeAddress'))) {
      return 'Enter your store name and address.';
    }
    return null;
  }

  Map<String, dynamic> get metadata => {
    'name': name.trim(),
    'phone': phone.trim(),
    'role': role,
    if (role == 'vendor') ...{
      'store_name': storeName.trim(),
      'store_address': storeAddress.trim(),
    },
  };

  Map<String, dynamic> get parameters => {
    'p_name': name.trim(),
    'p_phone': phone.trim(),
    'p_role': role,
    'p_store_name': storeName.trim(),
    'p_store_address': storeAddress.trim(),
    'p_update_profile': false,
  };
}

class RegistrationRequired implements Exception {
  const RegistrationRequired(this.role, this.code);
  final String role, code;
}

typedef RegistrationCall = Future<dynamic> Function(Map<String, dynamic>);

class OnboardingService {
  OnboardingService({RegistrationCall? call})
    : _call =
          call ??
          ((params) => Supabase.instance.client
              .rpc('final2_complete_registration', params: params)
              .timeout(const Duration(seconds: 15)));
  final RegistrationCall _call;

  Future<Map<String, dynamic>> complete(
    RegistrationData data, {
    bool updateProfile = false,
  }) async {
    final value = await _call({
      ...data.parameters,
      'p_update_profile': updateProfile,
    });
    if (value is! Map) {
      throw StateError('Profile completion was not confirmed.');
    }
    final result = Map<String, dynamic>.from(value);
    if (const {'PROFILE_REQUIRED', 'STORE_REQUIRED'}.contains(result['code'])) {
      throw RegistrationRequired(
        result['role'] as String,
        result['code'] as String,
      );
    }
    if (result['code'] != 'OK' ||
        result['id'] is! num ||
        !const {
          'customer',
          'vendor',
          'rider',
          'admin',
        }.contains(result['role']) ||
        !const {
          'approved',
          'pending',
          'rejected',
          'suspended',
        }.contains(result['verification_status']) ||
        (result['role'] == 'vendor' && result['store_id'] is! num)) {
      throw StateError('Profile completion was not confirmed.');
    }
    return result;
  }

  Future<Map<String, dynamic>> completeFromMetadata(User user) =>
      complete(fromMetadata(user.userMetadata ?? {}));

  static RegistrationData fromMetadata(Map<String, dynamic> metadata) {
    String text(String key) =>
        metadata[key] is String ? metadata[key] as String : '';
    final role = text('role');
    return RegistrationData(
      name: text('name'),
      phone: text('phone'),
      role: const {'customer', 'vendor', 'rider'}.contains(role)
          ? role
          : 'customer',
      storeName: text('store_name'),
      storeAddress: text('store_address'),
    );
  }
}
