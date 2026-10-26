import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;

class PostPickupCancellation {
  PostPickupCancellation({
    Future<dynamic> Function(Map<String, dynamic>)? submit,
    String? Function()? identity,
    Stream<void>? accountChanges,
  }) : _submit =
           submit ??
           ((args) => Supabase.instance.client
               .rpc('final_delivery_cancel_after_pickup', params: args)
               .timeout(const Duration(seconds: 15))),
       _identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id),
       accountChanges =
           accountChanges ??
           (identity != null
               ? const Stream<void>.empty()
               : Supabase.instance.client.auth.onAuthStateChange.map((_) {}));
  final Future<dynamic> Function(Map<String, dynamic>) _submit;
  final String? Function() _identity;
  final Stream<void> accountChanges;
  String? get account => _identity();
  bool busy = false;
  Map<String, dynamic>? _pending;
  String? _owner;
  bool get pending => _pending != null;
  String? get pendingReason => _pending?['p_reason'] as String?;

  Future<String> cancel(int orderId, String reason) async {
    if (busy) throw StateError('Cancellation already in progress');
    final owner = account;
    final text = reason.trim();
    if (owner == null ||
        orderId <= 0 ||
        text.runes.length < 5 ||
        text.runes.length > 300 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
      throw const FormatException(
        'A reason of 5 to 300 characters is required.',
      );
    }
    if (_owner != null && _owner != owner) {
      _pending = null;
      _owner = null;
    }
    if (_pending != null &&
        (_pending!['p_order_id'] != orderId || _pending!['p_reason'] != text)) {
      throw StateError('Retry the original cancellation before editing.');
    }
    _owner = owner;
    _pending ??= {
      'p_order_id': orderId,
      'p_request_id': blockRequestId(),
      'p_confirmed': true,
      'p_reason': text,
    };
    busy = true;
    try {
      final result = await _submit(Map<String, dynamic>.from(_pending!));
      if (account != owner) throw StateError('Account changed');
      if (result is! Map ||
          result['order_id'] != orderId ||
          !const {
            'CANCELLED',
            'ALREADY_CANCELLED',
            'PICKUP_REQUIRED',
            'PAYMENT_REVIEW_REQUIRED',
            'RETRYABLE_ERROR',
          }.contains(result['code'])) {
        throw const FormatException('Cancellation was not confirmed.');
      }
      final code = result['code'] as String;
      if (code != 'RETRYABLE_ERROR') _pending = null;
      return code;
    } on PostgrestException catch (error) {
      if (const {'22023', '42501', 'PT409'}.contains(error.code)) {
        _pending = null;
      }
      rethrow;
    } finally {
      busy = false;
    }
  }
}
