import 'dart:convert';
import 'package:http/http.dart' as http;

const pushTestUrl = 'https://igeisilhtmglgnqvllrx.supabase.co';
const pushTicketKey = 'fr30_push_ticket';

/// Withdraw an OS notice if logout/rebinding races the platform's async post.
Future<bool> publishPushForSession({
  required String ticket,
  required Future<String?> Function() readTicket,
  required Future<void> Function() publish,
  required Future<void> Function() withdraw,
}) async {
  if (await readTicket() != ticket) return false;
  await publish();
  try {
    if (await readTicket() == ticket) return true;
  } catch (_) {
    // A failed credential check must also remove the just-posted notice.
  }
  await withdraw();
  return false;
}

/// A push hint has no message text. Resolve only one snapshot delivery using a
/// device credential bound by the server to its live Supabase Auth session.
class BroadcastPushDelivery {
  BroadcastPushDelivery({
    required this.readTicket,
    required this.display,
    required this.publicKey,
    http.Client? client,
  }) : client = client ?? http.Client();
  final Future<String?> Function() readTicket;
  final Future<void> Function(String id, String title, String message) display;
  final String publicKey;
  final http.Client client;

  Future<bool> receive(Map<String, dynamic> hint) async {
    final id = hint['broadcast_id'];
    if (hint['kind'] != 'fr30_broadcast' ||
        id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id)) {
      return false;
    }
    try {
      final ticket = await readTicket();
      if (ticket == null) return false;
      final data = jsonDecode(ticket) as Map<String, dynamic>;
      if (data['installation'] is! String || data['secret'] is! String) {
        return false;
      }
      final response = await client
          .post(
            Uri.parse('$pushTestUrl/rest/v1/rpc/fr30_resolve_push'),
            headers: {
              'apikey': publicKey,
              'Authorization': 'Bearer $publicKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'p_installation': data['installation'],
              'p_secret': data['secret'],
              'p_broadcast': id,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || await readTicket() != ticket) {
        return false;
      }
      final notice = jsonDecode(response.body) as Map<String, dynamic>;
      if (notice['code'] != 'OK' ||
          notice['broadcast_id'] != id ||
          notice['title'] is! String ||
          notice['message'] is! String) {
        return false;
      }
      await display(id, notice['title'] as String, notice['message'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  void close() => client.close();
}
