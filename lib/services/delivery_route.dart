import 'dart:async';
import 'dart:math' as math;
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'delivery_location.dart';

class DeliveryRoute {
  DeliveryRoute.fromJson(Map<String, dynamic> data)
    : order = data['orderId'] as int,
      distance = (data['distanceMeters'] as num).toDouble(),
      duration = (data['durationSeconds'] as num).toDouble(),
      computed = DateTime.parse(data['computedAt'] as String).toUtc(),
      expires = DateTime.parse(data['expiresAt'] as String).toUtc(),
      approximate = data['isApproximate'] == true || data['isStale'] == true,
      source = data['source'] as String,
      deviation = (data['deviationMeters'] as num?)?.toDouble() ?? 150,
      points = decodeGeometry(data['geometry']) {
    if (!distance.isFinite ||
        !duration.isFinite ||
        distance < 0 ||
        distance > 1000000 ||
        duration < 0 ||
        duration > 86400 ||
        !const ['geoapify', 'straight_line'].contains(source) ||
        (source == 'geoapify' && points.length < 2) ||
        (source == 'straight_line' && (!approximate || points.isNotEmpty))) {
      throw const FormatException('Invalid route');
    }
  }
  final int order;
  final double distance, duration, deviation;
  final DateTime computed, expires;
  final bool approximate;
  final String source;
  final List<LatLng> points;
  late final projector = RouteProjector(points);
  static List<LatLng> decodeGeometry(dynamic geometry) {
    if (geometry == null) return const [];
    if (geometry is! Map ||
        geometry['type'] != 'LineString' ||
        geometry['coordinates'] is! List) {
      throw const FormatException('Invalid geometry');
    }
    final raw = geometry['coordinates'] as List;
    if (raw.length < 2 || raw.length > 20000) {
      throw const FormatException('Invalid geometry');
    }
    return List<LatLng>.unmodifiable(
      raw.map((p) {
        if (p is! List ||
            p.length != 2 ||
            p[0] is! num ||
            p[1] is! num ||
            !(p[0] as num).isFinite ||
            !(p[1] as num).isFinite ||
            (p[0] as num).abs() > 180 ||
            (p[1] as num).abs() > 90) {
          throw const FormatException('Invalid coordinate');
        }
        // GeoJSON is longitude,latitude; flutter_map is latitude,longitude.
        return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
      }),
    );
  }
}

class RouteProjection {
  const RouteProjection(this.along, this.offRoute, this.total);
  final double along, offRoute, total;
}

/// Immutable geometry work is done once per route, not on every GPS/timer tick.
class RouteProjector {
  RouteProjector(List<LatLng> points)
    : points = List<LatLng>.unmodifiable(points) {
    for (var i = 1; i < this.points.length; i++) {
      _lengths.add(
        const Distance().as(
          LengthUnit.Meter,
          this.points[i - 1],
          this.points[i],
        ),
      );
      _total += _lengths.last;
    }
  }
  final List<LatLng> points;
  final List<double> _lengths = [];
  double _total = 0;
  LatLng? _lastFix;
  RouteProjection? _lastProjection;

  RouteProjection project(LatLng fix) {
    if (_lastFix?.latitude == fix.latitude &&
        _lastFix?.longitude == fix.longitude) {
      return _lastProjection!;
    }
    const earth = 6371000.0;
    final cosLat = math.cos(fix.latitude * math.pi / 180);
    double length = 0, best = double.infinity, along = 0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      // Local tangent plane for projection, Haversine lengths for progress.
      final ax = (a.longitude - fix.longitude) * math.pi / 180 * earth * cosLat;
      final ay = (a.latitude - fix.latitude) * math.pi / 180 * earth;
      final bx = (b.longitude - fix.longitude) * math.pi / 180 * earth * cosLat;
      final by = (b.latitude - fix.latitude) * math.pi / 180 * earth;
      final dx = bx - ax, dy = by - ay, squared = dx * dx + dy * dy;
      final t = squared == 0
          ? 0.0
          : (-(ax * dx + ay * dy) / squared).clamp(0.0, 1.0);
      final x = ax + t * dx, y = ay + t * dy;
      final distance = math.sqrt(x * x + y * y);
      final segment = _lengths[i - 1];
      if (distance < best) {
        best = distance;
        along = length + t * segment;
      }
      length += segment;
    }
    _lastFix = fix;
    return _lastProjection = RouteProjection(along, best, _total);
  }
}

RouteProjection projectOnRoute(List<LatLng> points, LatLng fix) =>
    RouteProjector(points).project(fix);

String routeEtaLabel(double? seconds, {bool approximate = false}) {
  if (seconds == null || !seconds.isFinite || seconds < 0) {
    return 'ETA unavailable';
  }
  final minutes = math.max(1, (seconds / 60).ceil());
  return approximate
      ? 'Approximately $minutes min'
      : 'Arriving in $minutes min';
}

typedef FetchDeliveryRoute = Future<Map<String, dynamic>> Function(int order);

/// Uses the existing FR13 state; never opens a second GPS subscription.
class DeliveryRouteController extends GetxController {
  DeliveryRouteController(
    this.order,
    this.location,
    this.fetch, {
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final int order;
  final CustomerLocationState location;
  final FetchDeliveryRoute fetch;
  final DateTime Function() now;
  final route = Rxn<DeliveryRoute>();
  final label = 'ETA unavailable'.obs;
  final loading = false.obs;
  final notice = ''.obs;
  Worker? _fix, _stale;
  Timer? _timer;
  bool _closed = false, _inFlight = false, _denied = false;
  DateTime? _lastRequest, _lastFixAt;
  LatLng? _lastFix;
  double? _progress;
  bool _adjusted = false;
  int _generation = 0;
  void start() {
    _fix = ever(location.position, (_) => consider());
    _stale = ever(location.stale, (_) => consider());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => consider());
    consider();
  }

  bool get fresh => !location.stale.value && location.position.value != null;
  void consider() {
    if (_closed) return;
    if (!fresh) {
      label.value = 'ETA unavailable';
      return;
    }
    final current = route.value, fix = location.position.value!;
    final point = LatLng(fix.latitude, fix.longitude);
    var offRoute = false;
    if (current != null && current.points.length >= 2) {
      final projected = current.projector.project(point);
      offRoute = projected.offRoute > current.deviation;
      if (!offRoute &&
          fix.accuracy <= 50 &&
          projected.total > 0 &&
          (_lastFixAt == null || fix.at.isAfter(_lastFixAt!))) {
        final moved = _lastFix == null
            ? 0.0
            : const Distance().as(LengthUnit.Meter, _lastFix!, point);
        if (_progress == null) {
          _progress = projected.along;
          _adjusted = projected.along > math.max(20, fix.accuracy);
        } else if (moved > math.max(10, fix.accuracy) &&
            projected.along >= _progress! - 40 &&
            projected.along <= _progress! + moved * 2 + 100) {
          // Ignore small backwards noise and implausible forward jumps at loops.
          _progress = math.max(_progress!, projected.along);
          _adjusted = true;
        }
        // Do not move the reference point for sub-accuracy noise; slow real
        // movement accumulates until it exceeds the accuracy threshold.
        if (_lastFix == null || moved > math.max(10, fix.accuracy)) {
          _lastFix = point;
        }
        _lastFixAt = fix.at;
      }
      final remaining = _progress == null
          ? current.duration
          : current.duration *
                (1 - _progress! / projected.total).clamp(0.0, 1.0);
      label.value = routeEtaLabel(
        remaining,
        approximate:
            current.approximate ||
            _adjusted ||
            fix.accuracy > 50 ||
            offRoute ||
            now().toUtc().isAfter(current.expires),
      );
    } else if (current != null) {
      label.value = now().toUtc().isAfter(current.expires)
          ? 'ETA unavailable'
          : routeEtaLabel(current.duration, approximate: true);
    }
    if (!_denied &&
        (current == null ||
            now().toUtc().isAfter(current.expires) ||
            offRoute)) {
      unawaited(refreshRoute());
    }
  }

  Future<void> refreshRoute({bool retry = false}) async {
    if (_closed || _inFlight || !fresh) return;
    final stamp = now().toUtc();
    if (_lastRequest != null &&
        stamp.difference(_lastRequest!) < const Duration(seconds: 60)) {
      return;
    }
    if (retry) _denied = false;
    if (_denied) return;
    _lastRequest = stamp;
    _inFlight = true;
    loading.value = true;
    final generation = _generation;
    try {
      final response = await fetch(order).timeout(const Duration(seconds: 20));
      if (_closed || generation != _generation) return;
      if (const [
        'FORBIDDEN',
        'UNAUTHORIZED',
        'FR28_ACCOUNT_BLOCKED',
        'FR28_SESSION_REVOKED',
      ].contains(response['code'])) {
        _denied = true;
        route.value = null;
        label.value = 'ETA unavailable';
        notice.value = 'Delivery tracking is unavailable for this account.';
        return;
      }
      final data = response['route'];
      if (data is! Map) {
        if (response['code'] == 'DESTINATION_UNCONFIRMED') _denied = true;
        route.value = null;
        label.value = 'ETA unavailable';
        notice.value = response['code'] == 'DESTINATION_UNCONFIRMED'
            ? 'Delivery destination has not been confirmed.'
            : '';
        return;
      }
      final next = DeliveryRoute.fromJson(Map<String, dynamic>.from(data));
      if (next.order != order) throw const FormatException('Wrong order');
      final changed = route.value?.computed != next.computed;
      route.value = next;
      notice.value = next.source == 'straight_line'
          ? 'Straight-line estimate; roads, traffic and stops are not included.'
          : next.approximate
          ? 'Using a previous route estimate.'
          : '';
      if (changed) {
        _progress = null;
        _lastFix = null;
        _lastFixAt = null;
        _adjusted = false;
      }
      // _inFlight remains true during consider: no recursive fetch.
      consider();
    } catch (_) {
      if (!_closed && generation == _generation) {
        // A failed authorization/network recheck cannot leave old private data visible.
        route.value = null;
        label.value = 'ETA unavailable';
        notice.value = 'Route unavailable. Retrying when connected.';
      }
    } finally {
      _inFlight = false;
      if (!_closed) loading.value = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    _generation++;
    _fix?.dispose();
    _stale?.dispose();
    _timer?.cancel();
    route.value = null;
    label.value = 'ETA unavailable';
    super.onClose();
  }
}
