import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/rider_presence.dart';

void main() {
  for (final scenario in [
    'recover',
    'offline',
    'withdraw',
    'withdraw-in-flight',
    'superseded',
  ]) {
    testWidgets('active delivery transport recovery: $scenario', (
      tester,
    ) async {
      var disconnected = true, consent = true, superseded = false, starts = 0;
      final writes = <Map<String, dynamic>>[];
      Completer<Map<String, dynamic>>? pending;
      final presence = RiderPresence(
        (name, parameters) async {
          if (name == 'fr21_begin_presence') {
            starts++;
            return {'epoch': 7, 'is_online': true};
          }
          writes.add(Map.of(parameters));
          if (pending != null) return pending!.future;
          if (superseded) throw const PresenceFailure('Stale presence epoch');
          if (disconnected) throw StateError('network disconnected');
          return {'is_online': parameters['p_online']};
        },
        () {},
        allowTransportRecovery: () => consent,
      );
      await presence.restore();
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (presence.transportInterrupted && !presence.busy) break;
      }
      expect(presence.transportInterrupted, isTrue);
      expect(presence.online, isFalse);
      expect(presence.ready, isFalse);
      disconnected = false;
      final before = writes.length;
      if (scenario == 'offline') await presence.offline();
      if (scenario == 'withdraw') consent = false;
      if (scenario == 'superseded') superseded = true;
      final response = Completer<Map<String, dynamic>>();
      if (scenario == 'withdraw-in-flight') pending = response;
      await tester.pump(const Duration(seconds: 11));
      if (scenario == 'withdraw-in-flight') {
        expect(presence.busy, isTrue);
        consent = false;
        pending = null;
        response.complete({'is_online': true});
      }
      await tester.pump();
      expect(starts, 1, reason: 'Recovery must not replace a superseded epoch');
      expect(writes.every((p) => p['p_epoch'] == 7), isTrue);
      expect(
        presence.online,
        scenario == 'recover',
        reason:
            'scenario=$scenario before=$before writes=$writes busy=${presence.busy}',
      );
      expect(presence.transportInterrupted, isFalse);
      if (scenario == 'withdraw') expect(writes.length, before);
      if (scenario == 'withdraw-in-flight')
        expect(writes.last['p_online'], isFalse);
      presence.dispose();
    });
  }
  testWidgets('background during startup releases returned lease', (
    tester,
  ) async {
    final startup = Completer<Map<String, dynamic>>();
    final writes = <bool>[];
    final presence = RiderPresence((name, parameters) async {
      if (name == 'fr21_begin_presence') return startup.future;
      writes.add(parameters['p_online'] as bool);
      return {'is_online': false};
    }, () {});
    final restoring = presence.restore();
    await presence.offline();
    startup.complete({'epoch': 9, 'is_online': true});
    await restoring;
    expect(writes, [false]);
    expect(presence.online, isFalse);
    expect(presence.ready, isFalse);
    presence.dispose();
  });

  test(
    'authorization failures do not retry and require reconciliation',
    () async {
      var writes = 0;
      final presence = RiderPresence((name, _) async {
        if (name == 'fr21_begin_presence') {
          return {'epoch': 1, 'is_online': false};
        }
        writes++;
        throw const PresenceFailure('Session expired. Please sign in again.');
      }, () {});
      await presence.restore();
      await presence.setOnline(true);
      expect(writes, 1);
      expect(presence.online, isFalse);
      expect(presence.ready, isFalse);
      expect(presence.error, contains('Session expired'));
      presence.dispose();
    },
  );

  test('resume during an in-flight toggle queues a server restore', () async {
    final write = Completer<Map<String, dynamic>>();
    final started = Completer<void>();
    var starts = 0;
    final presence = RiderPresence((name, _) async {
      if (name == 'fr21_begin_presence') {
        return {'epoch': ++starts, 'is_online': false};
      }
      started.complete();
      return write.future;
    }, () {});
    await presence.restore();
    final toggle = presence.setOnline(true);
    await started.future;
    await presence.restore();
    write.complete({'is_online': true});
    await toggle;
    await Future<void>.delayed(Duration.zero);
    expect(starts, 2);
    expect(presence.online, isFalse);
    expect(presence.ready, isTrue);
    presence.dispose();
  });
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
