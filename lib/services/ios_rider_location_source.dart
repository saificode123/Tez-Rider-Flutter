import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'delivery_location.dart';

/// Core Location is started in the foreground; iOS controls delivery timing.
/// No Always authorization, background polling or terminated-app relaunch.
class IosRiderLocationSource
    implements RiderLocationSource, RiderLocationGuidance {
  IosRiderLocationSource({
    GeolocatorPlatform? platform,
    bool Function()? foreground,
  }) : _platform = platform ?? GeolocatorPlatform.instance,
       _foreground =
           foreground ??
           (() =>
               WidgetsBinding.instance.lifecycleState ==
               AppLifecycleState.resumed);

  final GeolocatorPlatform _platform;
  final bool Function() _foreground;
  LocationAccuracyStatus? _accuracy;

  @override
  Future<String?> prepare({
    required bool requestPermission,
    bool delivery = false,
  }) async {
    if (!await _platform.isLocationServiceEnabled()) {
      return 'Location Services are off. Enable them in Settings > Privacy & Security > Location Services, then retry.';
    }
    var permission = await _platform.checkPermission();
    if (requestPermission && permission == LocationPermission.denied) {
      if (!_foreground()) {
        return 'Open TezRider to allow location access, then retry.';
      }
      permission = await _platform.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location access is denied. Open Settings > Location and allow While Using the App. Screen Time or device restrictions may need an administrator.';
    }
    // The installed Apple plugin maps restricted and notDetermined to denied.
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return 'Location access is denied or restricted. Allow While Using the App in Settings; check Screen Time or device restrictions if access cannot be changed.';
    }
    _accuracy = await _platform.getLocationAccuracy();
    return null;
  }

  @override
  String? get notice => _accuracy == LocationAccuracyStatus.reduced
      ? 'Approximate Location is enabled. Only fresh fixes within 100 metres are shared. Enable Precise Location in Settings if updates are unavailable.'
      : null;

  @override
  String get waitingForFixMessage =>
      'Waiting for a fresh location within 100 metres. If Precise Location is off, enable it in Settings for more accurate updates.';

  @override
  Future<bool> openSettings() => _platform.openAppSettings();

  @override
  Stream<bool> get serviceEnabled => _platform.getServiceStatusStream().map(
    (status) => status == ServiceStatus.enabled,
  );

  @override
  Stream<DeviceFix> positions({required bool delivery}) => _platform
      .getPositionStream(
        locationSettings: AppleSettings(
          accuracy: delivery ? LocationAccuracy.high : LocationAccuracy.medium,
          distanceFilter: 0,
          activityType: ActivityType.other,
          pauseLocationUpdatesAutomatically: !delivery,
          allowBackgroundLocationUpdates: delivery,
          showBackgroundLocationIndicator: delivery,
        ),
      )
      .map(
        (p) =>
            DeviceFix(p.latitude, p.longitude, p.accuracy, p.timestamp.toUtc()),
      );
}
