import 'package:get/get.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final supabase = Supabase.instance.client;
  final MapController _mapController = MapController();

  LatLng? _userLocation;
  LatLng _riderPosition = const LatLng(33.6844, 73.0479);
  LatLng? _nearestRider;
  final List<LatLng> _routePoints = [];
  StreamSubscription? _riderSub;
  Timer? _simTimer;
  bool _loading = true;
  String _statusText = 'Finding your location...';
  String _riderName = 'Your Rider';
  String? _riderId;
  double? _deliveryFare;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _getUserLocation();
    await _findNearestRider();
    await _loadRiderInfo();
    _listenToRider();
    _simulateRider();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRiderInfo() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final userRec = await supabase.from('users').select('id').eq('email', user.email!).maybeSingle();
      if (userRec == null) return;
      final uid = userRec['id'];
      final order = await supabase.from('orders').select('rider_id, fare').eq('user_id', uid).eq('order_status', 'on_the_way').maybeSingle();
      if (order == null || order['rider_id'] == null) return;
      _riderId = order['rider_id'].toString();
      if (mounted) {
        setState(() {
          final f = order['fare'];
          _deliveryFare = f != null ? (f as num).toDouble() : null;
        });
      }
      final riderRec = await supabase.from('users').select('name').eq('id', _riderId!).maybeSingle();
      if (riderRec != null && mounted) {
        setState(() => _riderName = riderRec['name']?.toString() ?? 'Your Rider');
      }
    } catch (_) {}
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _statusText = 'Enable location services');
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() => _statusText = 'Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _userLocation = LatLng(pos.latitude, pos.longitude);
        _statusText = 'Location found';
      });
    } catch (e) {
      setState(() => _statusText = 'Could not get location');
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Future<void> _findNearestRider() async {
    if (_userLocation == null) return;
    try {
      final riders = await supabase
          .from('riders')
          .select()
          .eq('is_available', true) as List;

      double minDist = double.infinity;
      Map? nearest;

      for (final r in riders) {
        final lat = (r['latitude'] as num?)?.toDouble();
        final lng = (r['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        final d = _haversine(_userLocation!.latitude, _userLocation!.longitude, lat, lng);
        if (d < minDist) { minDist = d; nearest = r; }
      }

      if (nearest != null && mounted) {
        final rider = nearest;
        setState(() {
          _nearestRider = LatLng(
            (rider['latitude'] as num).toDouble(),
            (rider['longitude'] as num).toDouble(),
          );
          _statusText = 'Rider found — ${minDist.toStringAsFixed(1)} km away';
        });
      }
    } catch (_) {}
  }

  void _listenToRider() {
    _riderSub = supabase
        .from('gps_locations')
        .stream(primaryKey: ['id'])
        .eq('rider_id', _riderId ?? 'rider_1')
        .listen((data) {
      if (data.isEmpty) return;
      final latest = data.last;
      final lat = (latest['latitude'] as num?)?.toDouble();
      final lng = (latest['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      if (mounted) {
        setState(() {
          _riderPosition = LatLng(lat, lng);
          _routePoints.add(_riderPosition);
          if (_routePoints.length > 50) _routePoints.removeAt(0);
        });
      }
    });
  }

  void _simulateRider() {
    double lat = 33.6844, lng = 73.0479;
    _simTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      lat += 0.0004;
      lng += 0.0003;
      try {
        await supabase.from('gps_locations').upsert({
          'rider_id': _riderId ?? 'rider_1',
          'latitude': lat,
          'longitude': lng,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    });
  }

  String get _etaText {
    if (_userLocation == null) return '—';
    final km = _haversine(_userLocation!.latitude, _userLocation!.longitude,
        _riderPosition.latitude, _riderPosition.longitude);
    // Assume ~25 km/h average city delivery speed.
    final mins = (km / 25 * 60).clamp(2, 90).round();
    return '~$mins min';
  }

  void _centerOnUser() {
    if (_userLocation != null) {
      _mapController.move(_userLocation!, 15);
    }
  }

  void _centerOnRider() {
    _mapController.move(_riderPosition, 15);
  }

  @override
  void dispose() {
    _riderSub?.cancel();
    _simTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF1B5E20)),
                  SizedBox(height: 16),
                  Text('Getting your location...'),
                ],
              ),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _userLocation ?? _riderPosition,
                    initialZoom: 14.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.tezrider',
                    ),
                    if (_routePoints.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(points: _routePoints,
                            color: const Color(0xFF1B5E20), strokeWidth: 4),
                      ]),
                    MarkerLayer(markers: [
                      _marker(_riderPosition, Colors.deepOrange, Icons.delivery_dining, 44),
                      if (_userLocation != null)
                        _marker(_userLocation!, const Color(0xFF1B5E20),
                            Icons.person_pin_circle_rounded, 48),
                      if (_nearestRider != null)
                        _marker(_nearestRider!, Colors.green, Icons.two_wheeler_rounded, 40),
                    ]),
                  ],
                ),

                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16, right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.delivery_dining, color: Color(0xFF1B5E20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_riderName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(_statusText,
                                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE7F6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('On the way',
                              style: TextStyle(color: Color(0xFF1B5E20),
                                  fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),

                Positioned(
                  right: 16,
                  bottom: 200,
                  child: Column(
                    children: [
                      _fab(Icons.my_location_rounded, _centerOnUser, tooltip: 'My location'),
                      const SizedBox(height: 10),
                      _fab(Icons.delivery_dining, _centerOnRider, tooltip: 'Rider location'),
                    ],
                  ),
                ),

                Positioned(
                  bottom: 20, left: 16, right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _legendItem(Colors.deepOrange, Icons.delivery_dining, 'Your rider'),
                            _legendItem(const Color(0xFF1B5E20), Icons.person_pin_circle_rounded, 'You'),
                            _legendItem(Colors.green, Icons.two_wheeler_rounded, 'Available rider'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Points tracked',
                                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  Text('${_routePoints.length}',
                                      style: const TextStyle(fontWeight: FontWeight.bold,
                                          fontSize: 18, color: Color(0xFF1B5E20))),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Est. arrival',
                                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  Text(_etaText,
                                      style: const TextStyle(fontWeight: FontWeight.bold,
                                          fontSize: 18, color: Color(0xFF1B5E20))),
                                ],
                              ),
                            ),
                            if (_deliveryFare != null)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Delivery charges',
                                        style: TextStyle(color: Colors.grey, fontSize: 11)),
                                    Text('PKR ${_deliveryFare!.toStringAsFixed(0)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold,
                                            fontSize: 18, color: Color(0xFF1B5E20))),
                                  ],
                                ),
                              ),
                            ElevatedButton(
                              onPressed: () => Get.back(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B5E20),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              child: const Text('Back', style: TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Marker _marker(LatLng point, Color color, IconData icon, double size) {
    return Marker(
      point: point,
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: size * 0.6),
      ),
    );
  }

  Widget _fab(IconData icon, VoidCallback onTap, {String? tooltip}) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip ?? '',
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child: Icon(icon, color: const Color(0xFF1B5E20), size: 22),
        ),
      ),
    );
  }

  Widget _legendItem(Color color, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}