import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/services/account_session_service.dart';
import 'package:flutter_application_1/services/session_credentials.dart';

class MemoryFence extends LocalStorage {
  String? value;
  bool fail = false;
  @override
  Future<void> initialize() async {
    if (fail) throw StateError('injected fence failure');
  }

  @override
  Future<bool> hasAccessToken() async => value != null;
  @override
  Future<String?> accessToken() async {
    if (fail) throw StateError('injected fence failure');
    return value;
  }

  @override
  Future<void> persistSession(String value) async {
    if (fail) throw StateError('injected fence failure');
    this.value = value;
  }

  @override
  Future<void> removePersistedSession() async {
    if (fail) throw StateError('injected fence failure');
    value = null;
  }
}

class VaultDouble {
  final data = <String, String>{};
  final calls = <String>[];
  final failures = <String>{};
  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = Map<String, dynamic>.from(
              call.arguments as Map? ?? {},
            );
            final key = args['key'] as String? ?? '';
            calls.add('${call.method}:$key');
            if (failures.contains('${call.method}:$key')) {
              throw PlatformException(code: 'STORAGE_UNAVAILABLE');
            }
            switch (call.method) {
              case 'read':
                return data[key];
              case 'write':
                data[key] = args['value'] as String;
                return null;
              case 'delete':
                data.remove(key);
                return null;
              case 'readAll':
                return Map<String, String>.from(data);
              case 'deleteAll':
                data.clear();
                return null;
              case 'containsKey':
                return data.containsKey(key);
            }
            throw StateError('Unexpected secure storage method');
          },
        );
  }
}

class TestPkce extends GotrueAsyncStorage {
  const TestPkce();
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {}
}

Session unitSession([String id = '00000000-0000-0000-0000-000000000001']) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final jwt =
      '${encode({'alg': 'HS256'})}.${encode({'sub': id, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.unit-signature';
  return Session(
    accessToken: jwt,
    expiresIn: 3600,
    refreshToken: 'unit-refresh-$id',
    tokenType: 'bearer',
    user: User(
      id: id,
      email: 'unit@example.test',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-10-23T00:00:00Z',
    ),
  );
}

class UiTransport {
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? respond;
  Future<http.Response> send(http.Request request) async {
    requests.add(request);
    final response = respond != null
        ? await respond!(request)
        : jsonResponse([]);
    // Installed PostgREST inspects the originating request when parsing data.
    return http.Response.bytes(
      response.bodyBytes,
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  static http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json'},
      );
  static Future<http.Response> offline(http.Request _) async =>
      throw const SocketException('injected offline');
}

Future<void> initializeClosureClient(UiTransport transport) =>
    Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'closure-widget-public-key',
      httpClient: MockClient(transport.send),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        pkceAsyncStorage: TestPkce(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    ).then((_) {});

class UnitAccountBackend implements AccountSessionBackend {
  @override
  String? accountId = unitSession().user.id;
  @override
  Future<Map<String, dynamic>> status() async => {
    'code': 'OK',
    'id': 1,
    'role': 'customer',
    'verification_status': 'approved',
  };
  @override
  Future<void> subscribe(int profile, void Function() changed) async {}
  @override
  Future<void> unsubscribe() async {}
}

class QuietAuth extends AuthController {
  QuietAuth({SessionCredentials? credentials})
    : super(
        sessionCredentials:
            credentials ?? SessionCredentials(fence: MemoryFence()),
      );
  @override
  // The harness excludes native sensor listeners while exercising real logout.
  // ignore: must_call_super
  void onInit() {
    accountGate = AccountSessionGate(UnitAccountBackend(), (_) async {});
  }
}
