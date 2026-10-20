import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/delivery_location.dart';

class Source implements RiderLocationSource {
  final fixes = StreamController<DeviceFix>.broadcast();
  final services = StreamController<bool>.broadcast();
  String? problem;
  int starts = 0;
  final modes = <bool>[];
  @override
  Future<String?> prepare({
    required bool requestPermission,
    bool delivery = false,
  }) async => problem;
  @override
  Stream<DeviceFix> positions({required bool delivery}) {
    starts++;
    modes.add(delivery);
    return fixes.stream;
  }

  @override
  Stream<bool> get serviceEnabled => services.stream;
  Future<void> close() async {
    await fixes.close();
    await services.close();
  }
}

class Backend implements DeliveryLocationBackend {
  @override
  String accountId = 'rider';
  String eligibility = 'OK', outcome = 'PUBLISHED';
  int sent = 0, idleWrites = 0;
  bool fail = false;
  Completer<String>? pendingPublish;
  final publishedFixes = <DeviceFix>[];
  Completer<Map<String, dynamic>>? pendingStop;
  @override
  Future<Map<String, dynamic>> context(int order, {bool? enable}) async =>
      enable == false && pendingStop != null
      ? await pendingStop!.future
      : {
          'code': enable == false ? 'STOPPED' : eligibility,
          'sharing': true,
          'order_id': order,
        };
  @override
  Future<String> publish(int order, DeviceFix fix, String request) async {
    sent++;
    publishedFixes.add(fix);
    final pending = pendingPublish;
    pendingPublish = null;
    if (pending != null) return pending.future;
    if (fail) throw StateError('offline');
    return outcome;
  }

  @override
  Future<void> idle(DeviceFix fix) async {
    idleWrites++;
  }
}

class Lease implements TrackingSubscription {
  int closed = 0;
  @override
  Future<void> close() async {
    closed++;
  }
}

class Tracking implements CustomerTrackingBackend {
  Tracking(this.stamp);
  DateTime stamp;
  String code = 'OK', topic = 'fr13:1:2:session';
  int joins = 0, reads = 0;
  bool fail = false;
  final leases = <Lease>[];
  void Function(Map<String, dynamic>)? received;
  void Function()? connected, disconnected;
  @override
  Future<Map<String, dynamic>> context(int order) async {
    reads++;
    if (fail) throw StateError('offline');
    return {
      'code': code,
      'sharing': true,
      'topic': topic,
      'assignment_id': 2,
      'server_now': stamp.toIso8601String(),
    };
  }

  @override
  Future<TrackingSubscription> subscribe(
    String topic,
    int order,
    void Function(Map<String, dynamic>) receive,
    void Function() onConnect,
    void Function() onDisconnect,
  ) async {
    joins++;
    received = receive;
    connected = onConnect;
    disconnected = onDisconnect;
    final lease = Lease();
    leases.add(lease);
    return lease;
  }
}

void main() {
  final base = DateTime.utc(2026, 10, 18, 12);
  Map<String, dynamic> position({
    int order = 1,
    int assignment = 2,
    int seconds = 0,
  }) => {
    'order_id': order,
    'assignment_id': assignment,
    'latitude': 33.7,
    'longitude': 73.05,
    'accuracy': 5,
    'device_at': base.add(Duration(seconds: seconds)).toIso8601String(),
    'received_at': base.add(Duration(seconds: seconds)).toIso8601String(),
  };
  test('no active simulation or fake GPS writes remain', () {
    final map = File('lib/screens/map_screen.dart').readAsStringSync();
    expect(map, isNot(contains('_simulateRider')));
    expect(map, isNot(contains("from('gps_locations')")));
    // FR14 now renders only server-derived road geometry; FR13 must still
    // reject simulation and direct legacy GPS access.
    expect(map, contains('points: route.points'));
    expect(map, isNot(contains('RoutingService.fetchRoute')));
    expect(map, isNot(contains('_etaText')));
    expect(map, contains('fr04_order_rider_identity'));
  });
  for (final problem in [
    'Location permission denied',
    'Location permission permanently denied',
    'Location services disabled',
  ]) {
    test('$problem prevents device stream', () async {
      final source = Source()..problem = problem;
      final backend = Backend();
      final service = RiderLocationService(source, backend, now: () => base);
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      expect(source.starts, 0);
      expect(service.sharing.value, false);
      expect(service.message.value, problem);
      await service.stop();
      service.onClose();
      await Future<void>.delayed(Duration.zero);
      await source.close();
    });
  }
  for (final result in ['INELIGIBLE', 'FORBIDDEN']) {
    test('$result blocks delivery stream after authoritative check', () async {
      final source = Source();
      final backend = Backend()..eligibility = result;
      final service = RiderLocationService(source, backend, now: () => base);
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      expect(service.sharing.value, false);
      expect(source.modes.where((mode) => mode), isEmpty);
      await service.stop();
      service.onClose();
      await Future<void>.delayed(Duration.zero);
      await source.close();
    });
  }
  test('offline never starts; idle uses only low frequency mode', () async {
    final source = Source();
    final backend = Backend();
    var tick = Duration.zero;
    final service = RiderLocationService(
      source,
      backend,
      now: () => base.add(tick),
      elapsed: () => tick,
    );
    await service.reconcile(online: false, activeOrder: 1, foreground: true);
    await service.share(1);
    expect(source.starts, 0);
    await service.reconcile(online: true, activeOrder: null, foreground: true);
    for (var i = 0; i < 25; i++) {
      tick = Duration(seconds: i * 3);
      source.fixes.add(DeviceFix(33.7, 73.05, 5, base.add(tick)));
      await Future<void>.delayed(Duration.zero);
    }
    expect(source.modes, [false]);
    expect(backend.idleWrites, 2);
    expect(backend.sent, 0);
    await service.stop();
    service.onClose();
    await Future<void>.delayed(Duration.zero);
    await source.close();
  });
  for (final scenario in ['success', 'stop', 'failure', 'expired']) {
    final stopFirst = scenario == 'stop';
    test('slow publication keeps only newest real fix; $scenario', () async {
      final source = Source();
      final backend = Backend();
      var tick = Duration.zero;
      final service = RiderLocationService(
        source,
        backend,
        now: () => base.add(tick),
        elapsed: () => tick,
      );
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      final pending = Completer<String>();
      backend.pendingPublish = pending;
      for (var i = 0; i < 3; i++) {
        tick = Duration(milliseconds: i * 2500);
        source.fixes.add(DeviceFix(33.7 + i / 1000, 73.05, 5, base.add(tick)));
        await Future<void>.delayed(Duration.zero);
      }
      expect(backend.sent, 1);
      if (stopFirst) await service.stop();
      if (scenario == 'expired') tick = const Duration(seconds: 40);
      if (scenario == 'failure') {
        pending.completeError(StateError('offline'));
      } else {
        pending.complete('PUBLISHED');
      }
      await Future<void>.delayed(Duration.zero);
      expect(backend.sent, scenario == 'success' ? 2 : 1);
      if (scenario == 'success') {
        expect(backend.publishedFixes.last.at, base.add(tick));
      }
      if (scenario == 'failure') {
        tick += const Duration(seconds: 3);
        source.fixes.add(DeviceFix(33.7, 73.05, 5, base.add(tick)));
        await Future<void>.delayed(Duration.zero);
        expect(backend.sent, 2);
      }
      await service.stop();
      service.onClose();
      await source.close();
    });
  }
  test(
    'one stream, genuine-fix throttle, no synthesized gap updates',
    () async {
      final source = Source();
      final backend = Backend();
      var tick = Duration.zero;
      final service = RiderLocationService(
        source,
        backend,
        now: () => base.add(tick),
        elapsed: () => tick,
      );
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      await service.share(1);
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      expect(source.modes, [false, true]);
      expect(service.sharing.value, true);
      for (var i = 0; i < 6; i++) {
        tick = Duration(seconds: i);
        source.fixes.add(DeviceFix(33.7, 73.05, 5, base.add(tick)));
        await Future<void>.delayed(Duration.zero);
      }
      expect(backend.sent, 2);
      tick += const Duration(seconds: 20);
      await Future<void>.delayed(Duration.zero);
      expect(backend.sent, 2);
      await service.stop();
      service.onClose();
      await Future<void>.delayed(Duration.zero);
      await source.close();
    },
  );
  test('poor accuracy and old fixes never publish', () async {
    final source = Source();
    final backend = Backend();
    final service = RiderLocationService(source, backend, now: () => base);
    await service.reconcile(online: true, activeOrder: 1, foreground: true);
    await service.share(1);
    source.fixes.add(DeviceFix(33.7, 73.05, 101, base));
    source.fixes.add(
      DeviceFix(33.7, 73.05, 5, base.subtract(const Duration(seconds: 31))),
    );
    await Future<void>.delayed(Duration.zero);
    expect(backend.sent, 0);
    expect(service.message.value, contains('accurate'));
    await service.stop();
    service.onClose();
    await Future<void>.delayed(Duration.zero);
    await source.close();
  });
  test('network failure backs off using fresh fixes and recovers', () async {
    final source = Source();
    final backend = Backend()..fail = true;
    var tick = Duration.zero;
    final service = RiderLocationService(
      source,
      backend,
      now: () => base.add(tick),
      elapsed: () => tick,
    );
    await service.reconcile(online: true, activeOrder: 1, foreground: true);
    await service.share(1);
    source.fixes.add(DeviceFix(33.7, 73.05, 5, base));
    await Future<void>.delayed(Duration.zero);
    expect(backend.sent, 1);
    tick = const Duration(seconds: 1);
    source.fixes.add(DeviceFix(33.7, 73.05, 5, base.add(tick)));
    await Future<void>.delayed(Duration.zero);
    expect(backend.sent, 1);
    backend.fail = false;
    tick = const Duration(seconds: 3);
    source.fixes.add(DeviceFix(33.7, 73.05, 5, base.add(tick)));
    await Future<void>.delayed(Duration.zero);
    expect(backend.sent, 2);
    expect(service.message.value, 'Sharing your live location.');
    await service.stop();
    service.onClose();
    await Future<void>.delayed(Duration.zero);
    await source.close();
  });
  for (final reason in [
    'logout',
    'offline',
    'cancelled',
    'delivered',
    'blocked',
  ]) {
    test('$reason ends sharing and prevents more fixes', () async {
      final source = Source();
      final backend = Backend();
      final service = RiderLocationService(source, backend, now: () => base);
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      if (reason == 'logout') backend.accountId = '';
      if (reason == 'blocked') {
        backend.outcome = 'FORBIDDEN';
        source.fixes.add(DeviceFix(33.7, 73.05, 5, base));
        await Future<void>.delayed(Duration.zero);
      } else {
        await service.reconcile(
          online: reason != 'offline' && reason != 'logout',
          activeOrder: reason == 'cancelled' || reason == 'delivered'
              ? null
              : 1,
          foreground: false,
        );
      }
      expect(service.sharing.value, false);
      final sent = backend.sent;
      source.fixes.add(DeviceFix(33.7, 73.05, 5, base));
      await Future<void>.delayed(Duration.zero);
      expect(backend.sent, sent);
      await service.stop();
      service.onClose();
      await Future<void>.delayed(Duration.zero);
      await source.close();
    });
  }
  test(
    'foreground service continues on background; explicit stop cancels',
    () async {
      final source = Source();
      final backend = Backend();
      final service = RiderLocationService(source, backend, now: () => base);
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      await service.reconcile(online: true, activeOrder: 1, foreground: false);
      expect(service.sharing.value, true);
      expect(source.modes, [false, true]);
      await service.stop();
      expect(service.sharing.value, false);
      await service.stop();
      service.onClose();
      await Future<void>.delayed(Duration.zero);
      await source.close();
    },
  );
  test('GPS disabled or source stopped shuts down sharing', () async {
    final source = Source();
    final backend = Backend();
    final service = RiderLocationService(source, backend, now: () => base);
    await service.reconcile(online: true, activeOrder: 1, foreground: true);
    await service.share(1);
    source.services.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(service.sharing.value, false);
    expect(service.message.value, contains('disabled'));
    await service.stop();
    service.onClose();
    await Future<void>.delayed(Duration.zero);
    await source.close();
  });
  test(
    'customer exact stale threshold uses monotonic receive time and recovers',
    () {
      var tick = Duration.zero;
      final state = CustomerLocationState(
        elapsed: () => tick,
        now: () => base.add(tick),
      );
      state.open(1, 2, base);
      expect(state.receive(position()), true);
      tick = const Duration(seconds: 30);
      state.checkFreshness();
      expect(state.stale.value, false);
      tick = const Duration(seconds: 31);
      state.checkFreshness();
      expect(state.stale.value, true);
      expect(state.position.value, isNull);
      expect(state.receive(position(seconds: 31)), true);
      expect(state.stale.value, false);
      expect(
        unavailableRiderLocation,
        'Rider location temporarily unavailable.',
      );
    },
  );
  test('opening stale persisted position never displays an old pin', () {
    final state = CustomerLocationState(
      now: () => base.add(const Duration(seconds: 31)),
    );
    state.open(1, 2, base.add(const Duration(seconds: 31)));
    expect(state.receive(position()), false);
    expect(state.stale.value, true);
    expect(state.position.value, isNull);
  });
  test(
    'customer rejects wrong order, duplicate, malformed and low accuracy',
    () {
      final state = CustomerLocationState(now: () => base);
      state.open(1, 2, base);
      expect(state.receive(position(order: 2)), false);
      expect(state.receive(position(assignment: 3)), false);
      expect(state.receive({...position(), 'latitude': double.nan}), false);
      expect(state.receive({...position(), 'accuracy': 101}), false);
      expect(state.receive(position()), true);
      expect(state.receive(position()), false);
      state.open(2, 3, base);
      expect(state.position.value, isNull);
    },
  );
  testWidgets(
    'customer reconnect revalidates without duplicate subscriptions; disposal closes',
    (tester) async {
      final backend = Tracking(base);
      final session = CustomerTrackingSession(
        1,
        backend,
        state: CustomerLocationState(now: () => base),
      );
      await session.start();
      await session.start();
      expect(backend.joins, 1);
      backend.received!(position());
      expect(session.state.stale.value, false);
      backend.connected!();
      await tester.pump();
      expect(backend.joins, 1);
      expect(backend.reads, 2);
      backend.code = 'ENDED';
      backend.connected!();
      await tester.pump();
      expect(session.state.position.value, isNull);
      expect(backend.leases.single.closed, 1);
      await session.dispose();
      await tester.pump(const Duration(minutes: 1));
      expect(backend.joins, 1);
    },
  );
  testWidgets('bounded reconnect backoff recovers one subscription', (
    tester,
  ) async {
    final backend = Tracking(base)..fail = true;
    final session = CustomerTrackingSession(1, backend);
    await session.start();
    expect(backend.reads, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(backend.reads, 1);
    backend.fail = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(backend.joins, 1);
    backend.topic = 'fr13:1:2:new';
    await session.refresh();
    expect(backend.joins, 2);
    expect(backend.leases.first.closed, 1);
    await session.dispose();
    expect(backend.leases.last.closed, 1);
  });
  testWidgets('stale feed automatically discovers a restarted sharing topic', (
    tester,
  ) async {
    var tick = Duration.zero;
    final backend = Tracking(base);
    final state = CustomerLocationState(
      now: () => base.add(tick),
      elapsed: () => tick,
    );
    final session = CustomerTrackingSession(1, backend, state: state);
    await session.start();
    backend.received!(position());
    tick = const Duration(seconds: 31);
    backend.stamp = base.add(tick);
    backend.topic = 'fr13:1:2:restarted';
    await tester.pump(const Duration(seconds: 1));
    expect(state.stale.value, true);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(backend.joins, 2);
    expect(backend.leases.first.closed, 1);
    backend.received!(position(seconds: 31));
    expect(state.stale.value, false);
    await session.dispose();
  });
  test(
    'stop remains busy until confirmed and prevents an overlapping restart',
    () async {
      final source = Source();
      final backend = Backend();
      final service = RiderLocationService(source, backend, now: () => base);
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      backend.pendingStop = Completer<Map<String, dynamic>>();
      final stop = service.stop();
      await Future<void>.delayed(Duration.zero);
      expect(service.busy.value, true);
      await service.share(1);
      expect(source.modes, [false, true]);
      backend.pendingStop!.complete({'code': 'STOPPED'});
      await stop;
      expect(service.busy.value, false);
      expect(service.sharing.value, false);
      service.onClose();
      await Future<void>.delayed(Duration.zero);
      await source.close();
    },
  );
  test(
    'normal scheduling jitter does not halve the delivery cadence',
    () async {
      final source = Source();
      final backend = Backend();
      var tick = Duration.zero;
      final service = RiderLocationService(
        source,
        backend,
        now: () => base.add(tick),
        elapsed: () => tick,
      );
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      source.fixes.add(DeviceFix(33.7, 73.05, 5, base));
      await Future<void>.delayed(Duration.zero);
      tick = const Duration(milliseconds: 2490);
      source.fixes.add(DeviceFix(33.7, 73.05, 5, base.add(tick)));
      await Future<void>.delayed(Duration.zero);
      expect(backend.sent, 2);
      await service.stop();
      service.onClose();
      await Future<void>.delayed(Duration.zero);
      await source.close();
    },
  );
}
