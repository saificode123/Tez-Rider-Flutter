import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/services/delivery_location.dart';
import 'package:flutter_application_1/services/delivery_location_platform.dart';
import 'package:flutter_application_1/services/ios_rider_location_source.dart';
import 'delivery_location_test.dart' as fixtures;

/// Test double only: no simulated positions are part of application code.
class ApplePlatform extends GeolocatorPlatform {
  bool enabled = true, settingsOpened = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;
  int requests = 0, checks = 0, active = 0, peakActive = 0;
  final settings = <LocationSettings>[];
  late final fixes = StreamController<Position>.broadcast(
    onListen: () {
      active++;
      if (active > peakActive) peakActive = active;
    },
    onCancel: () => active--,
  );
  final statuses = StreamController<ServiceStatus>.broadcast();
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async {
    checks++;
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission = requestedPermission;
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async => accuracy;
  @override
  Future<bool> openAppSettings() async => settingsOpened;
  @override
  Stream<ServiceStatus> getServiceStatusStream() => statuses.stream;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings.add(locationSettings!);
    return fixes.stream;
  }

  void fix(DateTime at, {double accuracy = 5}) => fixes.add(
    Position(
      latitude: 33.7,
      longitude: 73.05,
      timestamp: at,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ),
  );
  Future<void> close() async {
    await fixes.close();
    await statuses.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = DateTime.utc(2026, 10, 19);
  Future<void> drain() => Future<void>.delayed(Duration.zero);

  test('factory selects iOS and preserves the Android source', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(createRiderLocationSource(), isA<IosRiderLocationSource>());
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(createRiderLocationSource(), isA<AndroidRiderLocationSource>());
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'only an explicit foreground request can prompt iOS permission',
    () async {
      final platform = ApplePlatform()..permission = LocationPermission.denied;
      var foreground = false;
      final source = IosRiderLocationSource(
        platform: platform,
        foreground: () => foreground,
      );
      expect(
        await source.prepare(requestPermission: false),
        contains('restricted'),
      );
      expect(
        await source.prepare(requestPermission: true),
        contains('Open TezRider'),
      );
      expect(platform.requests, 0);
      foreground = true;
      expect(await source.prepare(requestPermission: true), isNull);
      expect(platform.requests, 1);
      expect(platform.permission, LocationPermission.whileInUse);
      await platform.close();
    },
  );

  test('permanent denial offers Settings without repeated requests', () async {
    final platform = ApplePlatform()
      ..permission = LocationPermission.deniedForever;
    final source = IosRiderLocationSource(
      platform: platform,
      foreground: () => true,
    );
    expect(
      await source.prepare(requestPermission: true),
      contains('Screen Time'),
    );
    expect(platform.requests, 0);
    expect(await source.openSettings(), true);
    platform.settingsOpened = false;
    expect(await source.openSettings(), false);
    await platform.close();
  });

  test('restricted native status mapped to denied remains blocked', () async {
    final platform = ApplePlatform()
      ..permission = LocationPermission.denied
      ..requestedPermission = LocationPermission.denied;
    final source = IosRiderLocationSource(
      platform: platform,
      foreground: () => true,
    );
    expect(
      await source.prepare(requestPermission: true),
      contains('restrictions'),
    );
    expect(platform.requests, 1);
    expect(platform.settings, isEmpty);
    await platform.close();
  });

  test('disabled Location Services block before permission request', () async {
    final platform = ApplePlatform()..enabled = false;
    final source = IosRiderLocationSource(
      platform: platform,
      foreground: () => true,
    );
    expect(
      await source.prepare(requestPermission: true),
      contains('Location Services are off'),
    );
    expect(platform.checks, 0);
    expect(platform.requests, 0);
    await platform.close();
  });

  for (final accuracy in LocationAccuracyStatus.values) {
    test(
      '$accuracy is handled without requesting Always or upgrading accuracy',
      () async {
        final platform = ApplePlatform()..accuracy = accuracy;
        final source = IosRiderLocationSource(
          platform: platform,
          foreground: () => true,
        );
        expect(
          await source.prepare(requestPermission: true, delivery: true),
          isNull,
        );
        expect(platform.requests, 0);
        expect(
          source.notice,
          accuracy == LocationAccuracyStatus.reduced
              ? contains('Approximate')
              : isNull,
        );
        await platform.close();
      },
    );
  }

  test(
    'only delivery stream enables background and visible indicator',
    () async {
      final platform = ApplePlatform();
      final source = IosRiderLocationSource(platform: platform);
      for (final delivery in [false, true]) {
        final subscription = source
            .positions(delivery: delivery)
            .listen((_) {});
        final settings = platform.settings.last as AppleSettings;
        expect(settings.allowBackgroundLocationUpdates, delivery);
        expect(settings.showBackgroundLocationIndicator, delivery);
        expect(settings.pauseLocationUpdatesAutomatically, !delivery);
        expect(settings.distanceFilter, 0);
        expect(
          settings.accuracy,
          delivery ? LocationAccuracy.high : LocationAccuracy.medium,
        );
        await subscription.cancel();
      }
      expect(platform.active, 0);
      await platform.close();
    },
  );

  for (final code in ['INELIGIBLE', 'FORBIDDEN']) {
    test(
      'server $code prevents iOS background stream/checklist bypass',
      () async {
        final platform = ApplePlatform();
        final backend = fixtures.Backend()..eligibility = code;
        final service = RiderLocationService(
          IosRiderLocationSource(platform: platform),
          backend,
          now: () => base,
        );
        await service.reconcile(online: true, activeOrder: 1, foreground: true);
        await service.share(1);
        expect(service.sharing.value, false);
        expect(
          platform.settings.whereType<AppleSettings>().any(
            (s) => s.allowBackgroundLocationUpdates,
          ),
          false,
        );
        expect(service.message.value, contains('completed checklist'));
        service.onClose();
        await drain();
        await platform.close();
      },
    );
  }

  test(
    'reduced accuracy never bypasses 100m guard and can recover with valid fix',
    () async {
      final platform = ApplePlatform()
        ..accuracy = LocationAccuracyStatus.reduced;
      final backend = fixtures.Backend();
      var tick = Duration.zero;
      final service = RiderLocationService(
        IosRiderLocationSource(platform: platform),
        backend,
        now: () => base.add(tick),
        elapsed: () => tick,
      );
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      platform.fix(base, accuracy: 2500);
      await drain();
      expect(backend.sent, 0);
      expect(service.message.value, contains('Settings'));
      tick = const Duration(seconds: 3);
      platform.fix(base.add(tick), accuracy: 80);
      await drain();
      expect(backend.sent, 1);
      expect(backend.publishedFixes.single.accuracy, 80);
      expect(service.message.value, contains('Approximate'));
      await service.stop();
      service.onClose();
      await drain();
      await platform.close();
    },
  );

  test(
    'iOS active tracking keeps one native stream through background/resume then completes',
    () async {
      final platform = ApplePlatform();
      final backend = fixtures.Backend();
      final service = RiderLocationService(
        IosRiderLocationSource(platform: platform),
        backend,
        now: () => base,
      );
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      await service.share(1);
      final starts = platform.settings.length;
      for (final foreground in [false, false, true]) {
        await service.reconcile(
          online: true,
          activeOrder: 1,
          foreground: foreground,
        );
      }
      expect(platform.settings.length, starts);
      platform.fix(base);
      await drain();
      expect(backend.sent, 1);
      expect(platform.peakActive, 1);
      await service.reconcile(
        online: true,
        activeOrder: null,
        foreground: true,
      );
      expect(service.sharing.value, false);
      expect(
        (platform.settings.last as AppleSettings)
            .allowBackgroundLocationUpdates,
        false,
      );
      await service.reconcile(
        online: false,
        activeOrder: null,
        foreground: true,
      );
      expect(platform.active, 0);
      service.onClose();
      await drain();
      await platform.close();
    },
  );

  test(
    'iOS idle stream stops in background and logout stops active stream',
    () async {
      final platform = ApplePlatform();
      final backend = fixtures.Backend();
      final service = RiderLocationService(
        IosRiderLocationSource(platform: platform),
        backend,
        now: () => base,
      );
      await service.reconcile(
        online: true,
        activeOrder: null,
        foreground: true,
      );
      await service.reconcile(
        online: true,
        activeOrder: null,
        foreground: false,
      );
      expect(platform.active, 0);
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      backend.accountId = '';
      await service.reconcile(
        online: false,
        activeOrder: null,
        foreground: true,
      );
      expect(platform.active, 0);
      expect(service.sharing.value, false);
      service.onClose();
      await drain();
      await platform.close();
    },
  );

  test(
    'iOS Location Services interruption stops native subscription',
    () async {
      final platform = ApplePlatform();
      final service = RiderLocationService(
        IosRiderLocationSource(platform: platform),
        fixtures.Backend(),
        now: () => base,
      );
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      platform.statuses.add(ServiceStatus.disabled);
      await drain();
      await drain();
      expect(service.sharing.value, false);
      expect(platform.active, 0);
      expect(service.message.value, contains('disabled'));
      await service.openSettings();
      service.onClose();
      await drain();
      await platform.close();
    },
  );

  test(
    'iOS network failure retries fresh fixes, preserving native subscription',
    () async {
      final platform = ApplePlatform();
      final backend = fixtures.Backend()..fail = true;
      var tick = Duration.zero;
      final service = RiderLocationService(
        IosRiderLocationSource(platform: platform),
        backend,
        now: () => base.add(tick),
        elapsed: () => tick,
      );
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      platform.fix(base);
      await drain();
      expect(backend.sent, 1);
      backend.fail = false;
      tick = const Duration(seconds: 3);
      platform.fix(base.add(tick));
      await drain();
      expect(backend.sent, 2);
      expect(platform.active, 1);
      expect(platform.peakActive, 1);
      await service.stop();
      service.onClose();
      await drain();
      await platform.close();
    },
  );

  for (final change in ['denied', 'services-off', 'precise']) {
    test('iOS resume rechecks $change without another native stream', () async {
      final platform = ApplePlatform()
        ..accuracy = LocationAccuracyStatus.reduced;
      final service = RiderLocationService(
        IosRiderLocationSource(platform: platform),
        fixtures.Backend(),
        now: () => base,
      );
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      await service.share(1);
      expect(service.message.value, contains('Approximate'));
      final starts = platform.settings.length;
      await service.reconcile(online: true, activeOrder: 1, foreground: false);
      if (change == 'denied') {
        platform.permission = LocationPermission.deniedForever;
      }
      if (change == 'services-off') platform.enabled = false;
      if (change == 'precise') {
        platform.accuracy = LocationAccuracyStatus.precise;
      }
      await service.reconcile(online: true, activeOrder: 1, foreground: true);
      expect(platform.settings.length, starts);
      expect(platform.requests, 0);
      expect(service.sharing.value, change == 'precise');
      expect(platform.active, change == 'precise' ? 1 : 0);
      if (change == 'precise') {
        expect(service.message.value, isNot(contains('Approximate')));
      }
      await service.stop();
      service.onClose();
      await drain();
      await platform.close();
    });
  }

  test(
    'Android settings still use accepted cadence/notification configuration',
    () async {
      final original = GeolocatorPlatform.instance;
      final platform = ApplePlatform();
      GeolocatorPlatform.instance = platform;
      try {
        for (final delivery in [false, true]) {
          final subscription = AndroidRiderLocationSource()
              .positions(delivery: delivery)
              .listen((_) {});
          final settings = platform.settings.last as AndroidSettings;
          expect(
            settings.intervalDuration,
            delivery
                ? const Duration(milliseconds: 2500)
                : const Duration(minutes: 1),
          );
          expect(settings.distanceFilter, 0);
          expect(settings.foregroundNotificationConfig != null, delivery);
          if (delivery) {
            expect(settings.foregroundNotificationConfig!.enableWakeLock, true);
            expect(settings.foregroundNotificationConfig!.setOngoing, true);
          }
          await subscription.cancel();
        }
      } finally {
        GeolocatorPlatform.instance = original;
        await platform.close();
      }
    },
  );
}
