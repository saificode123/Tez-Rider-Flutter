import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/backend_config.dart';

void main() {
  test('HTTP is limited to explicitly enabled local testing', () {
    expect(
      () => BackendConfig(url: 'http://127.0.0.1:54321', key: 'local-public'),
      throwsFormatException,
    );
    expect(
      BackendConfig(
        url: 'http://127.0.0.1:54321',
        key: 'local-public',
        isolatedTest: true,
      ).isolatedTest,
      isTrue,
    );
    expect(
      () => BackendConfig(
        url: 'http://example.com',
        key: 'public',
        isolatedTest: true,
      ),
      throwsFormatException,
    );
  });
  test('privileged backend credentials are rejected in Flutter', () {
    expect(
      () => BackendConfig(
        url: 'https://example.supabase.co',
        key: 'sb_secret_private',
      ),
      throwsFormatException,
    );
    final payload = base64Url
        .encode(utf8.encode('{"role":"service_role"}'))
        .replaceAll('=', '');
    expect(
      () => BackendConfig(
        url: 'https://example.supabase.co',
        key: 'header.$payload.signature',
      ),
      throwsFormatException,
    );
  });
}
