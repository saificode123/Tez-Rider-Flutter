import 'dart:convert';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;

abstract interface class OrderTransitionBackend {
  Future<String> transition(int id, String status);
  Future<String?> status(int id);
}

class SupabaseOrderTransitionBackend implements OrderTransitionBackend {
  SupabaseClient get client => Supabase.instance.client;
  @override
  Future<String> transition(int id, String status) async {
    final result = await client
        .rpc(
          'fr10_vendor_transition',
          params: {'p_vendor_order_id': id, 'p_status': status},
        )
        .timeout(const Duration(seconds: 12));
    return result['code'] as String;
  }

  @override
  Future<String?> status(int id) async {
    final row = await client
        .from('vendor_orders')
        .select('status')
        .eq('id', id)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    return row?['status'] as String?;
  }
}

class OrderTransitionFlow {
  OrderTransitionFlow(this.backend);
  final OrderTransitionBackend backend;
  final busy = <String>{}.obs;
  final messages = <String, String>{}.obs;
  Future<String> change(int id, String status) async {
    final key = id.toString();
    if (!busy.add(key)) return 'An order update is already in progress.';
    try {
      final code = await backend.transition(id, status);
      final message = switch (code) {
        'ACCEPTED' || 'ALREADY_ACCEPTED' => 'Order accepted.',
        'ORDER_EXPIRED' =>
          'This order has expired and can no longer be accepted.',
        'ORDER_CANCELLED' => 'This order is cancelled.',
        'UPDATED' || 'ALREADY_UPDATED' => 'Order status confirmed.',
        'REVIEW_REQUIRED' =>
          'Fulfillment has started. This cancellation needs review.',
        'FORBIDDEN' => 'You cannot update this order.',
        'RETRYABLE_ERROR' => 'The order is busy. Refresh and retry.',
        _ => 'This order cannot make that transition. Refresh its status.',
      };
      messages[key] = message;
      return message;
    } catch (_) {
      // An uncertain request may have committed: inspect before reporting it.
      String? saved;
      try {
        saved = await backend.status(id);
      } catch (_) {}
      final message = saved == status
          ? 'Server confirmed the order is $saved.'
          : saved == 'cancelled'
          ? 'This order is cancelled.'
          : 'Update could not be confirmed. Refresh the order and retry when connected.';
      messages[key] = message;
      return message;
    } finally {
      busy.remove(key);
    }
  }
}

typedef CheckoutSubmit =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class OrderCheckoutFlow {
  OrderCheckoutFlow(this.submit);
  final CheckoutSubmit submit;
  Map<String, dynamic>? _request;
  bool busy = false;
  Future<Map<String, dynamic>> place(
    List<Map<String, dynamic>> items,
    Map<String, dynamic> delivery,
  ) async {
    if (busy) throw StateError('Checkout is already in progress.');
    final payload = {'p_items': items, 'p_delivery': delivery};
    if (_request != null &&
        jsonEncode({
              'p_items': _request!['p_items'],
              'p_delivery': _request!['p_delivery'],
            }) !=
            jsonEncode(payload)) {
      throw StateError(
        'The previous checkout result is uncertain. Retry with its original cart and delivery details.',
      );
    }
    _request ??= Map<String, dynamic>.from(
      jsonDecode(jsonEncode({'p_request_id': blockRequestId(), ...payload}))
          as Map,
    );
    busy = true;
    try {
      final result = await submit(_request!);
      if (!['PLACED', 'ALREADY_PLACED'].contains(result['code']) ||
          result['order_id'] is! int) {
        throw StateError(
          'Order placement was not confirmed. Refresh and retry.',
        );
      }
      return result;
    } finally {
      busy = false;
    }
  }
}
