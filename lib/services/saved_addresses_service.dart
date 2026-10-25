import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;

typedef AddressRpc =
    Future<dynamic> Function(String name, Map<String, dynamic> params);

class SavedAddressesService {
  SavedAddressesService({
    AddressRpc? rpc,
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
  final AddressRpc rpc;
  final String? Function() identity;
  final Stream<void> accountChanges;
  String? _owner;
  Map<String, dynamic>? _pending;
  bool busy = false;
  bool get pending => _pending != null;
  Future<dynamic> call(String name, Map<String, dynamic> params) async {
    final account = identity();
    if (account == null) throw StateError('Sign in required.');
    _owner ??= account;
    if (_owner != account) {
      throw StateError('Account changed. Open saved addresses again.');
    }
    final value = await rpc(name, params);
    if (identity() != account) {
      throw StateError('Account changed. Open saved addresses again.');
    }
    return value;
  }

  Future<Map<String, dynamic>> load({int? before}) async {
    final value = await call('final2_saved_addresses', {
      'p_before': before,
      'p_limit': 50,
    });
    if (value is! Map ||
        value['items'] is! List ||
        value['has_more'] is! bool ||
        value['cursor'] != null && value['cursor'] is! int) {
      throw const FormatException('Addresses were not confirmed.');
    }
    int? previous = before;
    for (final item in value['items']) {
      if (item is! Map ||
          item['id'] is! int ||
          item['id'] <= 0 ||
          previous != null && item['id'] >= previous ||
          item['label'] is! String ||
          item['address'] is! String ||
          item['revision'] is! int ||
          item['revision'] < 0) {
        throw const FormatException('Addresses were not confirmed.');
      }
      previous = item['id'];
    }
    if (value['has_more'] == true &&
        (value['items'].isEmpty || value['cursor'] != previous)) {
      throw const FormatException('Address page was not confirmed.');
    }
    return Map<String, dynamic>.from(value);
  }

  static String? validate(String label, String address) {
    if (label.trim().isEmpty ||
        label.trim().length > 100 ||
        address.trim().isEmpty ||
        address.trim().length > 2000 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(label + address)) {
      return 'Enter a label (up to 100 characters) and address (up to 2000 characters).';
    }
    return null;
  }

  Future<Map<String, dynamic>> change({
    required String operation,
    int? id,
    int? revision,
    String? label,
    String? address,
  }) async {
    if (busy) throw StateError('An address change is already in progress.');
    if (!['create', 'edit', 'delete'].contains(operation) ||
        operation != 'create' &&
            (id == null || id <= 0 || revision == null || revision < 0)) {
      throw const FormatException('Reload the address first.');
    }
    if (operation != 'delete') {
      final error = validate(label ?? '', address ?? '');
      if (error != null) throw FormatException(error);
    }
    final payload = {
      'p_operation': operation,
      'p_id': id,
      'p_expected_revision': revision,
      'p_label': label?.trim(),
      'p_address': address?.trim(),
    };
    if (_pending != null &&
        jsonEncode({..._pending!}..remove('p_request_id')) !=
            jsonEncode(payload)) {
      throw StateError('Retry the original address change first.');
    }
    _pending ??= {...payload, 'p_request_id': blockRequestId()};
    return retry();
  }

  Future<Map<String, dynamic>> retry() async {
    if (busy || _pending == null) {
      throw StateError('No pending address change.');
    }
    busy = true;
    try {
      final value = await call(
        'final2_change_address',
        Map<String, dynamic>.from(_pending!),
      );
      if (value is! Map ||
          !['APPLIED', 'ALREADY_APPLIED'].contains(value['code']) ||
          value['operation'] != _pending!['p_operation'] ||
          value['address_id'] is! int ||
          value['address_id'] <= 0 ||
          _pending!['p_id'] != null &&
              value['address_id'] != _pending!['p_id'] ||
          value['changed'] is! bool) {
        throw const FormatException('Address change was not confirmed.');
      }
      _pending = null;
      return Map<String, dynamic>.from(value);
    } on PostgrestException catch (error) {
      if (['22023', 'PT409', '42501'].contains(error.code)) _pending = null;
      rethrow;
    } finally {
      busy = false;
    }
  }
}
