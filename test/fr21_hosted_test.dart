import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/backend_config.dart';
import 'package:flutter_application_1/services/rider_presence.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final enabled = Platform.environment['FR21_RIDER_EMAIL'] != null;

  Future<SupabaseClient> login(String role) async {
    final values =
        jsonDecode(File('build/fr21-public-defines.json').readAsStringSync())
            as Map<String, dynamic>;
    final config = BackendConfig(
      url: values['SUPABASE_URL'] as String,
      key: values['SUPABASE_ANON_KEY'] as String,
      isolatedTest: true,
    );
    final client = SupabaseClient(config.url, config.key);
    await client.auth.signInWithPassword(
      email: Platform.environment['FR21_${role}_EMAIL']!,
      password: Platform.environment['FR21_${role}_PASSWORD']!,
    );
    return client;
  }

  test(
    'hosted Flutter presence restores and persists online/offline',
    () async {
      final client = await login('RIDER');
      final presence = RiderPresence(
        (name, parameters) async => Map<String, dynamic>.from(
          await client.rpc(name, params: parameters) as Map,
        ),
        () {},
      );
      try {
        await presence.restore();
        expect(presence.ready, isTrue);
        await presence.setOnline(true);
        expect(presence.online, isTrue);
        expect(presence.error, isNull);
        final actor = await client.rpc('fr21_actor');
        final row = await client
            .from('riders')
            .select('is_online,last_seen')
            .eq('userid', actor)
            .single();
        expect(row['is_online'], isTrue);
        expect(DateTime.tryParse(row['last_seen'] as String), isNotNull);
        await presence.offline();
        final persisted = await client
            .from('riders')
            .select('is_online')
            .eq('userid', actor)
            .single();
        expect(persisted['is_online'], isFalse);
        await presence.restore();
        expect(presence.online, isFalse);
      } finally {
        await presence.offline();
        presence.dispose();
        await client.dispose();
      }
    },
    skip: !enabled,
  );

  test('hosted Flutter customer cannot invoke rider presence', () async {
    final client = await login('CUSTOMER');
    try {
      await expectLater(
        client.rpc('fr21_begin_presence'),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
    } finally {
      await client.dispose();
    }
  }, skip: !enabled);
}
