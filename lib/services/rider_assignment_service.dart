import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class RiderAssignmentBackend {
  Future<Map<String, dynamic>> assign(int vendorOrderId);
  Future<Map<String, dynamic>> status(int vendorOrderId);
}

class SupabaseRiderAssignmentBackend implements RiderAssignmentBackend {
  SupabaseClient get client => Supabase.instance.client;

  Future<Map<String, dynamic>> _call(String name, int id) async {
    final result = await client
        .rpc(name, params: {'p_vendor_order_id': id})
        .timeout(const Duration(seconds: 8));
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<Map<String, dynamic>> assign(int vendorOrderId) =>
      _call('fr21_ready_and_assign', vendorOrderId);

  @override
  Future<Map<String, dynamic>> status(int vendorOrderId) =>
      _call('fr20_assignment_status', vendorOrderId);
}

String riderAssignmentMessage(
  String? code, {
  bool adminNotified = true,
}) => switch (code) {
  'ASSIGNED_5KM' => 'Order ready; rider assigned within 5 km.',
  'ASSIGNED_10KM' =>
    'Order ready; rider assigned after expanding the search to 10 km.',
  'ALREADY_ASSIGNED' => 'Order ready; rider already assigned.',
  'NO_RIDER_AVAILABLE' =>
    adminNotified
        ? 'Order ready. No eligible rider within 10 km. Administrators notified for manual assignment.'
        : 'Order ready. Manual assignment required; no eligible administrator is available for notification.',
  'FORBIDDEN' => 'An approved vendor account owning this order is required.',
  'INVALID_ORDER_STATE' =>
    'This order is no longer eligible for rider matching. Refresh your orders.',
  'PICKUP_LOCATION_REQUIRED' =>
    'Set your store location before matching a rider.',
  'RETRYABLE_CONFLICT' => 'Assignment is busy. Refresh the result and retry.',
  _ =>
    'Assignment was not confirmed. Check your connection and retry to check the saved result.',
};

class RiderAssignmentFlow {
  RiderAssignmentFlow(this.backend);
  final RiderAssignmentBackend backend;
  final busy = <String>{}.obs;
  final messages = <String, String>{}.obs;
  final uncertain = <int>{};

  bool _confirmed(Map<String, dynamic> result) => const {
    'ASSIGNED_5KM',
    'ASSIGNED_10KM',
    'ALREADY_ASSIGNED',
    'NO_RIDER_AVAILABLE',
    'FORBIDDEN',
    'INVALID_ORDER_STATE',
  }.contains(result['code']);

  Future<String> assign(int id) async {
    final key = id.toString();
    if (!busy.add(key)) return 'Assignment is already in progress.';
    messages.remove(key);
    try {
      if (uncertain.contains(id)) {
        // Resolve an earlier ambiguous request before issuing another mutation.
        final saved = await backend.status(id);
        if (_confirmed(saved)) {
          uncertain.remove(id);
          return messages[key] = riderAssignmentMessage(
            saved['code'] as String?,
            adminNotified: saved['admin_notified'] != false,
          );
        }
        if (saved['code'] != 'UNASSIGNED') throw StateError('Unknown status');
        uncertain.remove(id);
      }
      try {
        final result = await backend.assign(id);
        final code = result['code'] as String?;
        if (!const {
          'ASSIGNED_5KM',
          'ASSIGNED_10KM',
          'ALREADY_ASSIGNED',
          'NO_RIDER_AVAILABLE',
          'FORBIDDEN',
          'INVALID_ORDER_STATE',
          'PICKUP_LOCATION_REQUIRED',
          'RETRYABLE_CONFLICT',
        }.contains(code)) {
          throw StateError('Unknown assignment result');
        }
        return messages[key] = riderAssignmentMessage(
          code,
          adminNotified: result['admin_notified'] != false,
        );
      } on PostgrestException catch (error) {
        if (error.code == '42501' || error.code == 'PT403') {
          return messages[key] = riderAssignmentMessage('FORBIDDEN');
        }
        rethrow;
      }
    } catch (_) {
      uncertain.add(id);
      try {
        final saved = await backend.status(id);
        if (_confirmed(saved)) {
          uncertain.remove(id);
          return messages[key] = riderAssignmentMessage(
            saved['code'] as String?,
            adminNotified: saved['admin_notified'] != false,
          );
        }
      } catch (_) {
        // Keep the uncertainty; the next explicit retry checks server state.
      }
      return messages[key] = riderAssignmentMessage(null);
    } finally {
      busy.remove(key);
    }
  }
}
