import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/rider_presence.dart';

void main() {
  testWidgets('online heartbeat renews lease and stops after offline', (
    tester,
  ) async {
    final writes = <bool>[];
    final presence = RiderPresence((name, parameters) async {
      if (name == 'fr21_begin_presence') {
        return {'epoch': 1, 'is_online': true};
      }
      final online = parameters['p_online'] as bool;
      writes.add(online);
      return {'is_online': online};
    }, () {});
    await presence.restore();
    await tester.pump(const Duration(seconds: 55));
    await tester.pump();
    expect(writes, [true]);
    await presence.offline();
    await tester.pump(const Duration(minutes: 3));
    expect(writes, [true, false]);
    presence.dispose();
  });

  test(
    'restores effective server status and fails closed on restore error',
    () async {
      final presence = RiderPresence(
        (_, _) async => {'epoch': 3, 'is_online': true},
        () {},
      );
      await presence.restore();
      expect(presence.online, isTrue);
      expect(presence.ready, isTrue);
      presence.dispose();
      final failed = RiderPresence(
        (_, _) async => throw StateError('offline'),
        () {},
      );
      await failed.restore();
      expect(failed.online, isFalse);
      expect(failed.ready, isFalse);
      expect(failed.error, isNotNull);
      failed.dispose();
    },
  );

  test('blocks duplicate taps and reverts an unconfirmed toggle', () async {
    var writes = 0;
    final presence = RiderPresence((name, _) async {
      if (name == 'fr21_begin_presence') {
        return {'epoch': 1, 'is_online': false};
      }
      writes++;
      throw StateError('network');
    }, () {});
    await presence.restore();
    final first = presence.setOnline(true);
    await presence.setOnline(false);
    expect(presence.busy, isTrue);
    await first;
    expect(writes, 3);
    expect(presence.online, isFalse);
    expect(presence.error, isNotNull);
    presence.dispose();
  });

  test('all retries retain sequence and epoch', () async {
    final requests = <Map<String, dynamic>>[];
    final presence = RiderPresence((name, parameters) async {
      if (name == 'fr21_begin_presence') {
        return {'epoch': 7, 'is_online': false};
      }
      requests.add(Map.of(parameters));
      if (requests.length == 1) {
        throw StateError('response lost');
      }
      return {'is_online': true};
    }, () {});
    await presence.restore();
    await presence.setOnline(true);
    expect(requests[0], requests[1]);
    expect(requests[1]['p_epoch'], 7);
    expect(presence.online, isTrue);
    presence.dispose();
  });

  test('logout supersedes an in-flight online response', () async {
    final onlineResponse = Completer<Map<String, dynamic>>();
    final onlineStarted = Completer<void>();
    final sequences = <int>[];
    final presence = RiderPresence((name, parameters) async {
      if (name == 'fr21_begin_presence') {
        return {'epoch': 1, 'is_online': false};
      }
      sequences.add(parameters['p_sequence'] as int);
      if (parameters['p_online'] == true) {
        onlineStarted.complete();
        return onlineResponse.future;
      }
      return {'is_online': false};
    }, () {});
    await presence.restore();
    final toggle = presence.setOnline(true);
    await onlineStarted.future;
    await presence.offline();
    onlineResponse.complete({'is_online': true});
    await toggle;
    expect(sequences, [1, 2]);
    expect(presence.online, isFalse);
    presence.dispose();
  });

  test('offline cancels a toggle still inside debounce', () async {
    final writes = <bool>[];
    final presence = RiderPresence((name, parameters) async {
      if (name == 'fr21_begin_presence') {
        return {'epoch': 1, 'is_online': false};
      }
      writes.add(parameters['p_online'] as bool);
      return {'is_online': false};
    }, () {});
    await presence.restore();
    final toggle = presence.setOnline(true);
    await presence.offline();
    await toggle;
    expect(writes, [false]);
    expect(presence.online, isFalse);
    presence.dispose();
  });
}
