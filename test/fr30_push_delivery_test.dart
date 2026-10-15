import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_application_1/services/broadcast_push_delivery.dart';

void main() {
  for (final scenario in [
    'valid',
    'logout before post',
    'logout during post',
    'read failure after post',
  ]) {
    test('OS post session race: $scenario', () async {
      String? ticket = scenario == 'logout before post' ? null : 'session';
      var posted = 0, withdrawn = 0;
      final result = await publishPushForSession(
        ticket: 'session',
        readTicket: () async {
          if (scenario == 'read failure after post' && posted == 1) {
            throw StateError('storage unavailable');
          }
          return ticket;
        },
        publish: () async {
          posted++;
          if (scenario == 'logout during post') ticket = null;
        },
        withdraw: () async {
          withdrawn++;
        },
      );
      expect(result, scenario == 'valid');
      expect(posted, scenario == 'logout before post' ? 0 : 1);
      expect(
        withdrawn,
        ['logout during post', 'read failure after post'].contains(scenario)
            ? 1
            : 0,
      );
    });
  }
  const id = '12345678-1234-1234-1234-123456789abc';
  const hint = {'kind': 'fr30_broadcast', 'broadcast_id': id};
  final credential = jsonEncode({'installation': id, 'secret': 'a' * 64});
  final notice = {
    'code': 'OK',
    'broadcast_id': id,
    'title': '<b>Literal</b>',
    'message': 'Private snapshot',
  };
  for (final scenario in [
    'valid',
    'logout',
    'denied',
    'wrong snapshot',
    'malformed',
    'server failure',
    'no credential',
    'wrong hint',
  ]) {
    test('push lookup: $scenario', () async {
      String? ticket = scenario == 'no credential' ? null : credential;
      var requests = 0;
      final displayed = <List<String>>[];
      final delivery = BroadcastPushDelivery(
        readTicket: () async => ticket,
        display: (id, title, message) async =>
            displayed.add([id, title, message]),
        publicKey: 'public-test-key',
        client: MockClient((request) async {
          requests++;
          expect(
            request.url.toString(),
            '$pushTestUrl/rest/v1/rpc/fr30_resolve_push',
          );
          expect(jsonDecode(request.body), {
            'p_installation': id,
            'p_secret': 'a' * 64,
            'p_broadcast': id,
          });
          if (scenario == 'logout') ticket = null;
          if (scenario == 'denied') {
            return http.Response('{"code":"FORBIDDEN"}', 200);
          }
          if (scenario == 'malformed') {
            return http.Response('invalid JSON', 200);
          }
          if (scenario == 'server failure') return http.Response('{}', 503);
          return http.Response(
            jsonEncode({
              ...notice,
              if (scenario == 'wrong snapshot') 'broadcast_id': 'other',
            }),
            200,
          );
        }),
      );
      addTearDown(delivery.close);
      final result = await delivery.receive(
        scenario == 'wrong hint' ? {'kind': 'other', 'broadcast_id': id} : hint,
      );
      expect(result, scenario == 'valid');
      expect(
        displayed,
        scenario == 'valid'
            ? [
                [id, '<b>Literal</b>', 'Private snapshot'],
              ]
            : isEmpty,
      );
      expect(
        requests,
        ['no credential', 'wrong hint'].contains(scenario) ? 0 : 1,
      );
    });
  }
}
