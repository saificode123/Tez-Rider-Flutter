import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Result of a routing request: the road-following path plus the total
/// distance and estimated travel time for that path.
class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final double durationMin;

  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });
}

/// Thin wrapper around OSRM (Open Source Routing Machine) — the free,
/// open-source routing engine for OpenStreetMap data.
///
/// This uses OSRM's public demo server (`router.project-osrm.org`), which
/// is free and needs no API key, but it is a shared, best-effort service
/// meant for evaluation/demo use — no uptime or rate guarantees. For a
/// real production deployment, self-host OSRM (it's free, open-source
/// software) or use a paid routing provider.
class RoutingService {
  RoutingService._();

  static const _baseUrl = 'https://router.project-osrm.org/route/v1/driving';

  /// Fetches a driving route between [origin] and [destination].
  ///
  /// Returns `null` on any network error, timeout, or if OSRM could not
  /// find a route (e.g. points in the ocean, disconnected road network).
  /// Callers should fall back to a straight-line estimate when this
  /// returns `null`.
  static Future<RouteResult?> fetchRoute(
    LatLng origin,
    LatLng destination,
  ) async {
    // OSRM (like all GeoJSON tools) expects "lng,lat" order — the
    // opposite of LatLng's lat/lng order. Easy to get backwards.
    final url = Uri.parse(
      '$_baseUrl/${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return null;

      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final coords = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      return RouteResult(
        points: coords,
        distanceKm: (route['distance'] as num).toDouble() / 1000,
        durationMin: (route['duration'] as num).toDouble() / 60,
      );
    } catch (_) {
      return null;
    }
  }
}