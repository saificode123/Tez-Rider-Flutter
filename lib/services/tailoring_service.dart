import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;
import 'prescription_service.dart' show PrescriptionRpc;

class TailoringService {
  TailoringService({PrescriptionRpc? call, String? Function()? identity})
    : _call =
          call ??
          ((name, body) => Supabase.instance.client.rpc(name, params: body)),
      _identity =
          identity ?? (() => Supabase.instance.client.auth.currentUser?.id);
  final PrescriptionRpc _call;
  final String? Function() _identity;
  Map<String, dynamic>? _pending;
  String? _owner;
  bool busy = false;

  Future<Map<String, dynamic>> submit({
    required String instructions,
    required Map<String, dynamic> measurements,
    String? reference,
  }) async {
    if (busy) throw StateError('Request already in progress.');
    final owner = _identity();
    if (owner == null || (_owner != null && owner != _owner)) {
      throw StateError('Account changed. Reopen tailoring.');
    }
    if (instructions.trim().isEmpty || instructions.trim().length > 2000) {
      throw const FormatException(
        'Provide up to 2,000 characters of instructions.',
      );
    }
    final payload = {
      'p_instructions': instructions.trim(),
      'p_measurements': measurements,
      'p_reference': reference,
    };
    if (_pending != null &&
        jsonEncode(payload) !=
            jsonEncode({for (final key in payload.keys) key: _pending![key]})) {
      throw StateError('Retry the original tailoring request.');
    }
    _owner = owner;
    _pending ??= jsonDecode(
      jsonEncode({...payload, 'p_request_id': blockRequestId()}),
    );
    busy = true;
    try {
      final value = await _call(
        'optional_submit_tailoring',
        Map.from(_pending!),
      ).timeout(const Duration(seconds: 20));
      if (_identity() != owner) {
        throw StateError('Account changed. Reopen tailoring.');
      }
      if (value is! Map ||
          value['id'] is! int ||
          value['id'] <= 0 ||
          value['status'] != 'pickup_requested' ||
          value['instructions'] != instructions.trim()) {
        throw const FormatException('Request persistence was not confirmed.');
      }
      return Map<String, dynamic>.from(value);
    } finally {
      busy = false;
    }
  }
}
