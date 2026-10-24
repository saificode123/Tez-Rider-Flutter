import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/delivery_location.dart';
import '../services/delivery_location_platform.dart';
import '../services/delivery_route.dart';
import '../widgets/tez_map_tiles.dart';
import '../widgets/rider_identity_card.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.orderId});
  final int? orderId;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _client = Supabase.instance.client;
  final _map = MapController();
  CustomerLocationFeed? _feed;
  DeliveryRouteController? _route;
  Worker? _fixWorker;
  bool _mapReady = false, _centered = false;
  LatLng? _userLocation;
  bool _loading = true;
  int _generation = 0;
  int? _identityOrder;
  double? _fare;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) unawaited(_open());
  }

  Future<void> _open() async {
    final generation = ++_generation;
    _fixWorker?.dispose();
    _route?.onClose();
    _route = null;
    _mapReady = false;
    _centered = false;
    final previous = _feed;
    _feed = null;
    await previous?.dispose();
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = true;
      _identityOrder = null;
      _fare = null;
    });
    try {
      final actor = await _client
          .rpc('fr21_actor')
          .timeout(const Duration(seconds: 8));
      if (actor == null) return;
      final query = _client
          .from('orders')
          .select('id,rider_id,fare,order_status')
          .eq('user_id', actor);
      final order = widget.orderId != null
          ? await query
                .eq('id', widget.orderId!)
                .maybeSingle()
                .timeout(const Duration(seconds: 8))
          : await query
                .eq('order_status', 'on_the_way')
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle()
                .timeout(const Duration(seconds: 8));
      if (!mounted || generation != _generation || order == null) return;
      _fare = (order['fare'] as num?)?.toDouble();
      _identityOrder = order['id'] as int;
      final feed = CustomerLocationFeed(order['id'] as int);
      _feed = feed;
      _route = DeliveryRouteController(order['id'] as int, feed.state, (
        id,
      ) async {
        try {
          final response = await _client.functions.invoke(
            'get-delivery-route',
            body: {'orderId': id},
          );
          return Map<String, dynamic>.from(response.data as Map);
        } on FunctionException catch (e) {
          final details = e.details;
          return details is Map
              ? Map<String, dynamic>.from(details)
              : {
                  'code': e.status == 401
                      ? 'UNAUTHORIZED'
                      : e.status == 403
                      ? 'FORBIDDEN'
                      : 'UNAVAILABLE',
                };
        }
      })..start();
      _fixWorker = ever(feed.state.position, (_) => _centerFirstFix());
      await feed.start();
      if (!mounted || generation != _generation) await feed.dispose();
    } catch (_) {
      /* No old coordinate or simulated fallback pin. */
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _centerFirstFix() {
    final fix = _feed?.state.position.value;
    if (mounted &&
        _mapReady &&
        !_centered &&
        fix != null &&
        _feed?.state.stale.value == false) {
      _centered = true;
      _map.move(LatLng(fix.latitude, fix.longitude), 15);
    }
  }

  Future<void> _myLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('disabled');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('denied');
      }
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() => _userLocation = LatLng(p.latitude, p.longitude));
      _map.move(_userLocation!, 15);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your location is unavailable. Check GPS and location permission.',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _fixWorker?.dispose();
    _route?.onClose();
    unawaited(_feed?.dispose());
    _map.dispose();
    super.dispose();
  }

  Marker _marker(LatLng point, IconData icon, Color color, String label) =>
      Marker(
        point: point,
        width: 48,
        height: 48,
        child: Semantics(
          label: label,
          child: Icon(icon, color: color, size: 44),
        ),
      );
  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1B5E20);
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  // This is a map viewport, never a fabricated rider location.
                  options: MapOptions(
                    initialCenter: _feed?.state.position.value == null
                        ? _userLocation ?? const LatLng(33.6844, 73.0479)
                        : LatLng(
                            _feed!.state.position.value!.latitude,
                            _feed!.state.position.value!.longitude,
                          ),
                    onMapReady: () {
                      _mapReady = true;
                      _centerFirstFix();
                    },
                    initialZoom: 14.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.tezrider',
                      tileProvider: tezMapTiles(),
                    ),
                    if (_feed != null)
                      Obx(() {
                        final route = _route?.route.value;
                        final visible = !_feed!.state.stale.value;
                        return PolylineLayer(
                          polylines: [
                            if (visible &&
                                route != null &&
                                route.points.isNotEmpty)
                              Polyline(
                                points: route.points,
                                strokeWidth: 5,
                                color: green,
                              ),
                          ],
                        );
                      }),
                    if (_feed != null)
                      Obx(() {
                        final fix = _feed!.state.position.value;
                        final stale = _feed!.state.stale.value;
                        return MarkerLayer(
                          markers: [
                            if (fix != null && !stale)
                              _marker(
                                LatLng(fix.latitude, fix.longitude),
                                Icons.delivery_dining,
                                Colors.deepOrange,
                                'Live rider location',
                              ),
                            if (_userLocation != null)
                              _marker(
                                _userLocation!,
                                Icons.person_pin_circle_rounded,
                                green,
                                'Your location',
                              ),
                          ],
                        );
                      })
                    else
                      MarkerLayer(
                        markers: [
                          if (_userLocation != null)
                            _marker(
                              _userLocation!,
                              Icons.person_pin_circle_rounded,
                              green,
                              'Your location',
                            ),
                        ],
                      ),
                  ],
                ),
                const Positioned(
                  bottom: 115,
                  left: 16,
                  child: TezMapAttribution(),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 12),
                      ],
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_identityOrder != null)
                              RiderIdentityCard(
                                key: ValueKey(_identityOrder),
                                orderId: _identityOrder!,
                              ),
                            if (_feed != null)
                              Obx(() {
                                final state = _feed!.state;
                                return Text(
                                  state.stale.value
                                      ? unavailableRiderLocation
                                      : 'Live rider location • accuracy ±${state.position.value!.accuracy.round()} m',
                                  style: const TextStyle(fontSize: 12),
                                );
                              })
                            else
                              const Text(unavailableRiderLocation),
                            if (_route != null)
                              Obx(
                                () => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Chip(
                                      label: Text(
                                        _route!.loading.value &&
                                                _route!.route.value == null &&
                                                !_feed!.state.stale.value
                                            ? 'Calculating ETA…'
                                            : _route!.label.value,
                                      ),
                                    ),
                                    if (_route!.notice.value.isNotEmpty &&
                                        !_feed!.state.stale.value)
                                      Text(
                                        _route!.notice.value,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    if (_route!.route.value?.source ==
                                            'geoapify' &&
                                        !_feed!.state.stale.value)
                                      InkWell(
                                        onTap: () => launchUrl(
                                          Uri.parse(
                                            'https://www.geoapify.com/',
                                          ),
                                        ),
                                        child: const Text(
                                          'Powered by Geoapify | © OpenStreetMap contributors',
                                          style: TextStyle(
                                            fontSize: 10,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 150,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'customer-position',
                        tooltip: 'My location',
                        onPressed: _myLocation,
                        child: const Icon(Icons.my_location),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton.small(
                        heroTag: 'rider-position',
                        tooltip: 'Rider location',
                        onPressed: () {
                          final fix = _feed?.state.position.value;
                          if (fix != null &&
                              _feed?.state.stale.value == false) {
                            _map.move(LatLng(fix.latitude, fix.longitude), 15);
                          }
                        },
                        child: const Icon(Icons.delivery_dining),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _fare == null
                                ? 'Live delivery tracking'
                                : 'Delivery charges: PKR ${_fare!.toStringAsFixed(0)}',
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (_feed == null) {
                              unawaited(_open());
                            } else {
                              unawaited(_feed!.refresh());
                              unawaited(_route?.refreshRoute(retry: true));
                            }
                          },
                          child: const Text('Retry'),
                        ),
                        FilledButton(
                          onPressed: () => Get.back(),
                          child: const Text('Back'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
