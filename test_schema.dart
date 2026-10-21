import 'dart:io';
import 'package:supabase/supabase.dart';
import 'lib/services/diagnostic_backend.dart';

Future<void> main() async {
  try {
    final config = diagnosticBackend();
    final client = SupabaseClient(config.url, config.key);
    final rows = await client.from('users').select('id').limit(1);
    stdout.writeln(
      'TEST diagnostic completed; visible records: ${rows.length}',
    );
    await client.dispose();
  } catch (_) {
    stdout.writeln(
      'TEST diagnostic denied or unavailable. Check TEST configuration and access.',
    );
  }
}
