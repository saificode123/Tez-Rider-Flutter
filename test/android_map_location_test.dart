import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/services/delivery_location_platform.dart';
import 'ios_delivery_location_test.dart' show ApplePlatform;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform original;
  late ApplePlatform platform;
  setUp(() {
    original = GeolocatorPlatform.instance;
    platform = ApplePlatform();
    GeolocatorPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() async {
    GeolocatorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    await platform.close();
  });
  test(
    'GPS off and denied permission fail before starting any stream',
    () async {
      platform.enabled = false;
      expect(
        await AndroidRiderLocationSource().prepare(
          requestPermission: false,
          delivery: true,
        ),
        contains('Enable GPS'),
      );
      platform.enabled = true;
      platform.permission = LocationPermission.denied;
      expect(
        await AndroidRiderLocationSource().prepare(
          requestPermission: false,
          delivery: true,
        ),
        contains('Allow location permission'),
      );
      expect(platform.requests, 0);
      expect(platform.active, 0);
    },
  );
  test(
    'approximate location gives precise-location guidance and no stream',
    () async {
      platform.accuracy = LocationAccuracyStatus.reduced;
      expect(
        await AndroidRiderLocationSource().prepare(
          requestPermission: false,
          delivery: true,
        ),
        contains('Enable precise location'),
      );
      expect(platform.active, 0);
      expect(platform.requests, 0);
    },
  );
  test(
    'precise location and existing permission pass without requesting consent',
    () async {
      expect(
        await AndroidRiderLocationSource().prepare(
          requestPermission: false,
          delivery: true,
        ),
        isNull,
      );
      expect(platform.requests, 0);
      expect(platform.active, 0);
    },
  );
}
