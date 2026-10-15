import 'package:supabase_flutter/supabase_flutter.dart';

const broadcastAudiences = {
  'ALL': 'All users',
  'CUSTOMERS': 'Customers',
  'VENDORS': 'Vendors',
  'RIDERS': 'Riders',
};

abstract interface class AdminBroadcastBackend {
  Future<int> estimate(String audience);
  Future<List<Map<String, dynamic>>> history(Map<String, dynamic>? before);
  Future<Map<String, dynamic>> send(Map<String, dynamic> request);
}

class SupabaseAdminBroadcastBackend implements AdminBroadcastBackend {
  SupabaseClient get client => Supabase.instance.client;

  @override
  Future<int> estimate(String audience) async =>
      (await client
                  .rpc('fr30_estimate', params: {'p_audience': audience})
                  .timeout(const Duration(seconds: 12))
              as num)
          .toInt();

  @override
  Future<List<Map<String, dynamic>>> history(
    Map<String, dynamic>? before,
  ) async {
    var query = client
        .from('admin_broadcasts')
        .select('id,title,audience,recipient_count,created_at,status');
    if (before != null) {
      final time = DateTime.parse(
        before['created_at'] as String,
      ).toUtc().toIso8601String();
      final id = before['id'] as String;
      if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
        throw StateError('Invalid cursor');
      }
      query = query.or(
        'created_at.lt.$time,and(created_at.eq.$time,id.lt.$id)',
      );
    }
    return await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(25)
        .timeout(const Duration(seconds: 12));
  }

  @override
  Future<Map<String, dynamic>> send(Map<String, dynamic> request) async =>
      Map<String, dynamic>.from(
        await client
                .rpc('admin_send_broadcast', params: request)
                .timeout(const Duration(seconds: 25))
            as Map,
      );
}

String broadcastResultMessage(
  Map<String, dynamic> result,
) => switch (result['code']) {
  'SENT' || 'ALREADY_SENT' =>
    'Accepted for ${result['recipient_count']} recipients. In-app delivery is available when they connect.',
  'COOLDOWN' =>
    'Please wait ${result['retry_after_seconds'] ?? 60} seconds before another broadcast.',
  'DAILY_LIMIT' =>
    'The rolling 24-hour broadcast limit has been reached. Try again later.',
  'FORBIDDEN' => 'Only an approved, active administrator can send broadcasts.',
  'INVALID_INPUT' =>
    'Enter a title (1–100 characters), message (1–1,000 characters), and valid audience.',
  'IDEMPOTENCY_CONFLICT' =>
    'This request ID belongs to another broadcast. Refresh before trying again.',
  _ => 'Delivery acceptance was not confirmed. Retry the same broadcast.',
};
