import 'backend_config.dart';

/// Diagnostic tools must never target production or embed keys in source.
BackendConfig diagnosticBackend() => BackendConfig(
  url: const String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://igeisilhtmglgnqvllrx.supabase.co',
  ),
  key: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  isolatedTest: true,
);
