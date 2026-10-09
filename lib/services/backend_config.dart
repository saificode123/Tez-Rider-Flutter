import 'dart:convert';

class BackendConfig {
  BackendConfig({
    required this.url,
    required this.key,
    this.isolatedTest = false,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || key.isEmpty) {
      throw const FormatException('Backend configuration is missing.');
    }
    final local = const {
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
    }.contains(uri.host);
    if (uri.scheme != 'https' &&
        !(isolatedTest && local && uri.scheme == 'http')) {
      throw const FormatException('A secure backend connection is required.');
    }
    if (key.startsWith('sb_secret_')) {
      throw const FormatException(
        'Private backend keys cannot be used in the app.',
      );
    }
    if (key.split('.').length == 3) {
      final claims =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(key.split('.')[1])),
                ),
              )
              as Map;
      if (claims['role'] != 'anon') {
        throw const FormatException(
          'Only a public backend key may be used in the app.',
        );
      }
    }
  }

  final String url;
  final String key;
  final bool isolatedTest;
}
