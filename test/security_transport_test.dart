import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_application_1/services/account_session_service.dart';

void main() {
  final base = Uri.parse('https://igeisilhtmglgnqvllrx.supabase.co');
  test('TEST REST uses gateway with user identity and preserves query/range semantics', () async {
    final client = AccountHttpClient((_) => fail('No denial expected'), gatewayBase: base, inner: MockClient((r) async {
      expect(r.url, base.resolve('/functions/v1/security-gateway'));
      expect(r.headers['authorization'], 'Bearer synthetic-user-jwt');
      final body = jsonDecode(r.body);
      expect(body['method'], 'GET');
      expect(body['path'], '/products');
      expect(body['query'], 'select=id&limit=1');
      expect(body['headers']['range'], '0-0');
      expect(body['headers'].containsKey('x-final01-proof'), isFalse);
      return http.Response('[{"id":1}]', 200, headers: {'content-range': '0-0/1'});
    }));
    final response = await client.get(base.resolve('/rest/v1/products?select=id&limit=1'), headers: {'Authorization': 'Bearer synthetic-user-jwt', 'Range': '0-0', 'x-final01-proof': 'untrusted'});
    expect(response.statusCode, 200);
    expect(response.headers['content-range'], '0-0/1');
    expect(jsonDecode(response.body)[0]['id'], 1);
    client.close();
  });
  test('POST body and idempotency payload survive transport unchanged', () async {
    final client = AccountHttpClient((_) {}, gatewayBase: base, inner: MockClient((r) async {
      final envelope = jsonDecode(r.body);
      expect(envelope['method'], 'POST');
      expect(envelope['path'], '/rpc/fr10_checkout');
      expect(jsonDecode(envelope['body']), {'p_request_id': 'synthetic-request', 'p_items': []});
      expect(envelope['headers']['content-type'], contains('application/json'));
      return http.Response('{"code":"SHORTAGE"}', 200);
    }));
    final r = await client.post(base.resolve('/rest/v1/rpc/fr10_checkout'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'p_request_id': 'synthetic-request', 'p_items': []}));
    expect(jsonDecode(r.body)['code'], 'SHORTAGE');
    client.close();
  });
  test('Auth and unrelated origins are not rerouted', () async {
    final seen = <Uri>[];
    final client = AccountHttpClient((_) {}, gatewayBase: base, inner: MockClient((r) async { seen.add(r.url); return http.Response('{}', 200); }));
    final auth = base.resolve('/auth/v1/token?grant_type=password');
    final other = Uri.parse('https://other.example.test/rest/v1/products');
    await client.post(auth, body: '{}');
    await client.get(other);
    expect(seen, [auth, other]);
    client.close();
  });
  test('shared quota denial preserves retry-after without signing out', () async {
    final denied = <String>[];
    final client = AccountHttpClient(denied.add, gatewayBase: base, inner: MockClient((_) async => http.Response('{"code":"RATE_LIMITED"}', 429, headers: {'retry-after': '17'})));
    final r = await client.get(base.resolve('/rest/v1/products'));
    expect(r.statusCode, 429);
    expect(r.headers['retry-after'], '17');
    expect(denied, isEmpty);
    client.close();
  });
  test('gateway expiry still triggers canonical session cleanup', () async {
    final denied = <String>[];
    final client = AccountHttpClient(denied.add, gatewayBase: base, inner: MockClient((_) async => http.Response('{"code":"FR28_SESSION_REVOKED"}', 401)));
    final r = await client.get(base.resolve('/rest/v1/products'));
    await Future<void>.delayed(Duration.zero);
    expect(r.statusCode, 401);
    expect(denied, ['FR28_SESSION_REVOKED']);
    client.close();
  });
  test('oversized REST payload never leaves client', () async {
    var calls = 0;
    final client = AccountHttpClient((_) {}, gatewayBase: base, inner: MockClient((_) async { calls++; return http.Response('{}', 200); }));
    await expectLater(client.post(base.resolve('/rest/v1/users'), body: 'x' * 900001), throwsStateError);
    expect(calls, 0);
    client.close();
  });
}
