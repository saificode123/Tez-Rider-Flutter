import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_application_1/services/account_session_service.dart';

class Backend implements AccountSessionBackend {
  @override
  String? accountId = 'synthetic';
  String code = 'OK';
  int subscriptions = 0, removed = 0, checks = 0;
  void Function()? changed;
  Completer<Map<String, dynamic>>? delayed;
  bool fail = false;
  Completer<void>? delayedUnsubscribe;
  @override
  Future<Map<String, dynamic>> status() async {
    checks++;
    if (fail) throw TimeoutException('synthetic');
    return delayed?.future ?? Future.value({'code': code, 'id': 1});
  }

  @override
  Future<void> subscribe(int profile, void Function() callback) async {
    subscriptions++;
    changed = callback;
  }

  @override
  Future<void> unsubscribe() async {
    removed++;
    changed = null;
    final pending = delayedUnsubscribe;
    delayedUnsubscribe = null;
    if (pending != null) await pending.future;
  }
}

void main() {
  test('late denial cannot sign out a newly restored session', () async {
    final backend = Backend();
    final denied = <AccountDisposition>[];
    final gate = AccountSessionGate(backend, (d) async {
      denied.add(d);
    });
    await gate.check();
    final pause = Completer<void>();
    backend.delayedUnsubscribe = pause;
    backend.code = 'FR28_ACCOUNT_BLOCKED';
    final old = gate.check();
    await Future<void>.delayed(Duration.zero);
    await gate.reset();
    backend.code = 'OK';
    expect(await gate.check(), AccountDisposition.allowed);
    pause.complete();
    expect(await old, AccountDisposition.expired);
    expect(denied, isEmpty);
    expect(gate.current, AccountDisposition.allowed);
    await gate.dispose();
  });
  test(
    'login/restoration blocked and expired checks; network keeps session',
    () async {
      final backend = Backend();
      final denied = <AccountDisposition>[];
      final gate = AccountSessionGate(backend, (d) async {
        denied.add(d);
      });
      expect(await gate.check(), AccountDisposition.allowed);
      await gate.check();
      expect(backend.subscriptions, 1);
      backend.fail = true;
      expect(await gate.check(), AccountDisposition.unavailable);
      expect(denied, isEmpty);
      backend.fail = false;
      backend.code = 'FR28_ACCOUNT_BLOCKED';
      expect(await gate.check(), AccountDisposition.blocked);
      expect(denied, [AccountDisposition.blocked]);
      backend.code = 'FR28_SESSION_REVOKED';
      expect(await gate.check(), AccountDisposition.expired);
      await gate.dispose();
    },
  );
  test('Realtime events coalesce and force blocked sign-out', () async {
    final backend = Backend();
    final denied = <AccountDisposition>[];
    final gate = AccountSessionGate(backend, (d) async {
      denied.add(d);
    });
    await gate.check();
    backend.code = 'FR28_ACCOUNT_BLOCKED';
    backend.changed!();
    backend.changed!();
    backend.changed!();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(backend.checks, 2);
    expect(denied, [AccountDisposition.blocked]);
    expect(backend.changed, isNull);
    await gate.dispose();
  });
  test('reset invalidates an earlier restoration for same identity', () async {
    final backend = Backend()..delayed = Completer();
    final gate = AccountSessionGate(backend, (_) async {});
    final previous = gate.check();
    await gate.reset();
    backend.delayed!.complete({'code': 'OK', 'id': 1});
    expect(await previous, AccountDisposition.expired);
    expect(backend.subscriptions, 0);
    backend.delayed = null;
    expect(await gate.check(), AccountDisposition.allowed);
    await gate.dispose();
  });
  test(
    'global handling recognizes trusted code; unrelated 403 is preserved',
    () async {
      final denied = <String>[];
      var body = '{"code":"42501","message":"ordinary permission denial"}';
      final client = AccountHttpClient(
        denied.add,
        inner: MockClient((_) async => http.Response(body, 403)),
      );
      final url = Uri.parse('https://example.test/rest/v1/orders');
      expect((await client.get(url)).body, body);
      expect(denied, isEmpty);
      body = '{"code":"PT403","message":"FR28_ACCOUNT_BLOCKED"}';
      expect((await client.get(url)).statusCode, 403);
      await Future<void>.delayed(Duration.zero);
      expect(denied, ['FR28_ACCOUNT_BLOCKED']);
      client.close();
    },
  );
}
