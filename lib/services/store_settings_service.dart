import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;

typedef StoreSettingsRpc =
    Future<dynamic> Function(String name, Map<String, dynamic> params);

class StoreSettingsService {
  StoreSettingsService({
    StoreSettingsRpc? rpc,
    String? Function()? identity,
    Stream<void>? accountChanges,
  }) : rpc =
           rpc ??
           ((name, params) => Supabase.instance.client
               .rpc(name, params: params)
               .timeout(const Duration(seconds: 15))),
       identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id),
       accountChanges =
           accountChanges ??
           (identity != null
               ? const Stream<void>.empty()
               : Supabase.instance.client.auth.onAuthStateChange.map((_) {}));
  final StoreSettingsRpc rpc;
  final String? Function() identity;
  final Stream<void> accountChanges;
  Map<String, dynamic>? _pending;
  String? _owner;
  bool busy = false;
  bool get pending => _pending != null;
  static String? validate(
    String name,
    String address,
    double? lat,
    double? lng,
  ) {
    if (name.trim().isEmpty ||
        name.trim().length > 200 ||
        address.trim().isEmpty ||
        address.trim().length > 500 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name + address)) {
      return 'Enter a store name and address (up to 200 and 500 characters).';
    }
    if ((lat == null) != (lng == null) ||
        lat != null &&
            (!lat.isFinite ||
                lat.abs() > 90 ||
                !lng!.isFinite ||
                lng.abs() > 180)) {
      return 'Confirm a valid pickup location.';
    }
    return null;
  }

  Map<String, dynamic> parse(dynamic value) {
    if (value is! Map ||
        value['store_id'] is! int ||
        value['store_id'] <= 0 ||
        value['version'] is! int ||
        value['version'] < 0 ||
        value['is_active'] is! bool ||
        value['store_name'] != null && value['store_name'] is! String ||
        value['address'] != null && value['address'] is! String ||
        value['latitude'] != null && value['latitude'] is! num ||
        value['longitude'] != null && value['longitude'] is! num) {
      throw const FormatException('Store details were not confirmed.');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<dynamic> call(String name, Map<String, dynamic> params) async {
    final account = identity();
    if (account == null) throw StateError('Sign in as Vendor.');
    _owner ??= account;
    if (_owner != account) {
      throw StateError('Account changed. Open store settings again.');
    }
    final value = await rpc(name, params);
    if (identity() != account) {
      throw StateError('Account changed. Open store settings again.');
    }
    return value;
  }

  Future<Map<String, dynamic>> load() async {
    if (busy || pending) throw StateError('Retry the original save first.');
    return parse(await call('final2_store_settings', {}));
  }

  Future<Map<String, dynamic>> save({
    required int version,
    required String name,
    required String address,
    double? lat,
    double? lng,
  }) async {
    if (busy) throw StateError('Store is being saved.');
    final error = validate(name, address, lat, lng);
    if (error != null || version < 0) {
      throw FormatException(error ?? 'Reload the store.');
    }
    final payload = {
      'p_expected_version': version,
      'p_name': name.trim(),
      'p_address': address.trim(),
      'p_latitude': lat,
      'p_longitude': lng,
    };
    if (_pending != null &&
        payload.entries.any((e) => _pending![e.key] != e.value)) {
      throw StateError('Retry the original save first.');
    }
    _pending ??= {...payload, 'p_request_id': blockRequestId()};
    busy = true;
    try {
      final value = await call(
        'final2_save_store_settings',
        Map<String, dynamic>.from(_pending!),
      );
      if (value is! Map ||
          !['SAVED', 'ALREADY_APPLIED'].contains(value['code'])) {
        throw const FormatException('Store save was not confirmed.');
      }
      final store = parse(value['store']);
      _pending = null;
      return {'code': value['code'], 'store': store};
    } on PostgrestException catch (error) {
      if (['22023', 'PT409', '42501'].contains(error.code)) _pending = null;
      rethrow;
    } finally {
      busy = false;
    }
  }
}
