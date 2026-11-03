import 'dart:convert';

String resolveBackendPublicKey(String anonKey, String publishableKey) {
  final anon = anonKey.trim();
  final publishable = publishableKey.trim();
  if (anon.isNotEmpty && publishable.isNotEmpty && anon != publishable) {
    throw const FormatException(
      'Set only one of SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY.',
    );
  }
  return anon.isNotEmpty ? anon : publishable;
}

String get backendPublicKey => resolveBackendPublicKey(
  const String.fromEnvironment('SUPABASE_ANON_KEY'),
  const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
);

class BackendConfig {
  BackendConfig({
    required this.url,
    required this.key,
    this.isolatedTest = false,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || key.isEmpty) {
      throw const FormatException(
        'Backend configuration is missing. Pass --dart-define-from-file=.env '
        'with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY). '
        'See docs/PARTNER-WINDOWS-SETUP.md.',
      );
    }
    final local = const {
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
    }.contains(uri.host);
    if (isolatedTest &&
        !local &&
        uri.host != 'igeisilhtmglgnqvllrx.supabase.co') {
      throw const FormatException(
        'The FR-21 app must use its dedicated TEST backend.',
      );
    }
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
      if (!local &&
          claims['ref'] != null &&
          uri.host != '${claims['ref']}.supabase.co') {
        throw const FormatException(
          'The public key belongs to a different backend.',
        );
      }
    }
  }

  final String url;
  final String key;
  final bool isolatedTest;
}
