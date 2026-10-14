import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

const refundInitiated = 'Refund has been initiated.';
const disputeRejected = 'Dispute rejected. See reason in app.';
String normalizedDisputeStatus(Object? value) =>
    value.toString().toUpperCase().replaceAll(' ', '_');
bool disputeDecisionAllowed(Map<String, dynamic> detail) =>
    detail['decision'] == null &&
    detail['order_id'] != null &&
    detail['customer_id'] != null &&
    const [
      'OPEN',
      'UNDER_REVIEW',
      'ESCALATED',
    ].contains(normalizedDisputeStatus(detail['status']));
String? validateAdminNote(String note, int minimum, int maximum) {
  final size = note.trim().runes.length;
  return size < minimum || size > maximum
      ? 'Enter an admin note of $minimum–$maximum characters.'
      : null;
}

String adminDisputeError(Object error) {
  if (error is PostgrestException) {
    if (error.code == '42501') return 'Admin authorization required.';
    if (const ['PT404', 'PT409', 'PT422'].contains(error.code)) {
      return error.message;
    }
  }
  return 'The request was not confirmed. Check your connection and Retry.';
}

abstract class AdminDisputeBackend {
  String get accountId;
  Future<Map<String, dynamic>> options();
  Future<List<Map<String, dynamic>>> queue({
    String? status,
    Map<String, dynamic>? before,
  });
  Future<Map<String, dynamic>> detail(int id);
  Future<List<Map<String, dynamic>>> vendors(int id, {int? before});
  Future<Map<String, dynamic>> decide(int id, String decision, String note);
  Future<void> Function() subscribe(
    void Function() change,
    void Function() error,
  );
}

class SupabaseAdminDisputeBackend implements AdminDisputeBackend {
  SupabaseClient get client => Supabase.instance.client;
  @override
  String get accountId => client.auth.currentUser?.id ?? '';
  Future<dynamic> _rpc(String name, Map<String, dynamic> params) =>
      client.rpc(name, params: params).timeout(const Duration(seconds: 15));
  @override
  Future<Map<String, dynamic>> options() async =>
      Map<String, dynamic>.from(await _rpc('fr26_options', {}));
  @override
  Future<List<Map<String, dynamic>>> queue({
    String? status,
    Map<String, dynamic>? before,
  }) async => List<Map<String, dynamic>>.from(
    await _rpc('fr26_queue', {
      'p_status': status,
      'p_before_at': before?['created_at'],
      'p_before_id': before?['id'],
      'p_limit': 30,
    }),
  );
  @override
  Future<Map<String, dynamic>> detail(int id) async =>
      Map<String, dynamic>.from(await _rpc('fr26_detail', {'p_id': id}));
  @override
  Future<List<Map<String, dynamic>>> vendors(int id, {int? before}) async =>
      List<Map<String, dynamic>>.from(
        await _rpc('fr26_vendors', {'p_id': id, 'p_before': before}),
      );
  @override
  Future<Map<String, dynamic>> decide(
    int id,
    String decision,
    String note,
  ) async => Map<String, dynamic>.from(
    await _rpc('admin_resolve_dispute', {
      'p_dispute_id': id,
      'p_decision': decision,
      'p_note': note.trim(),
    }),
  );
  @override
  Future<void> Function() subscribe(
    void Function() change,
    void Function() error,
  ) {
    // A positive-ID filter preserves notifications when status changes out of
    // the selected queue. Existing RLS independently authorizes every event.
    final channel = client
        .channel('fr26-admin-disputes-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'disputes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.gte,
            column: 'id',
            value: 0,
          ),
          callback: (_) => change(),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            error();
          }
        });
    return () async {
      await client.removeChannel(channel);
    };
  }
}
