import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../services/delivery_location.dart';
import '../core/stage2_ui_strings.dart';
import '../services/delivery_map_stops.dart';
import '../services/delivery_route.dart';
import '../theme/app_theme.dart';
import 'tez_map_tiles.dart';

/// Presentation only: interpolation ends at the latest confirmed GPS fix.
/// No GPS acquisition, route requests, extrapolation or consent changes here.
class DeliveryMapView extends StatefulWidget {
  const DeliveryMapView({
    super.key,
    this.fix,
    this.stale = true,
    this.stops = const DeliveryMapStops(),
    this.route,
    this.eta = 'ETA unavailable',
    this.notice = '',
    this.loading = false,
    this.onRetry,
    this.onBack,
    this.footer,
    this.tileProvider,
    this.viewerLocation,
    this.onLocate,
  });
  final DeviceFix? fix;
  final bool stale, loading;
  final DeliveryMapStops stops;
  final DeliveryRoute? route;
  final String eta, notice;
  final VoidCallback? onRetry, onBack;
  final Widget? footer;
  final TileProvider? tileProvider;
  final LatLng? viewerLocation;
  final VoidCallback? onLocate;
  @override
  State<DeliveryMapView> createState() => _DeliveryMapViewState();
}

class _DeliveryMapViewState extends State<DeliveryMapView>
    with SingleTickerProviderStateMixin {
  final map = MapController();
  late final AnimationController motion;
  late final TileProvider tiles;
  LatLng? from, target;
  bool ready = false, follow = true, centered = false;
  bool tileFailure = false;
  final tileReset = StreamController<void>.broadcast();
  LatLng? get displayed {
    if (target == null || from == null) return target;
    final t = motion.value.clamp(0.0, 1.0);
    return LatLng(
      from!.latitude + (target!.latitude - from!.latitude) * t,
      from!.longitude + (target!.longitude - from!.longitude) * t,
    );
  }

  @override
  void initState() {
    super.initState();
    tiles = widget.tileProvider ?? tezMapTiles();
    motion =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 240),
        )..addListener(() {
          if (ready && follow && !widget.stale && displayed != null) {
            map.move(displayed!, map.camera.zoom);
          }
        });
    target = widget.fix == null
        ? null
        : LatLng(widget.fix!.latitude, widget.fix!.longitude);
    from = target;
    motion.value = 1;
  }

  @override
  void didUpdateWidget(DeliveryMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.fix == null
        ? null
        : LatLng(widget.fix!.latitude, widget.fix!.longitude);
    if (next != target) {
      final start = displayed;
      motion.stop();
      from = start ?? next;
      target = next;
      if (next == null ||
          widget.stale ||
          MediaQuery.disableAnimationsOf(context)) {
        from = next;
        motion.value = 1;
      } else {
        motion.forward(from: 0);
      }
    }
    if (!centered && ready) _initialCamera();
  }

  void _initialCamera() {
    if (target != null) {
      centered = true;
      map.move(target!, 15);
    } else if (widget.stops.pickup != null ||
        widget.stops.destination != null) {
      centered = true;
      _overview();
    }
  }

  void _overview() {
    if (!ready) return;
    final points = <LatLng>[
      if (target != null) target!,
      if (widget.stops.pickup != null) widget.stops.pickup!,
      if (widget.stops.destination != null) widget.stops.destination!,
      ...?widget.route?.points,
    ];
    if (points.isEmpty) return;
    setState(() => follow = false);
    if (points.toSet().length == 1) {
      map.move(points.first, 15);
    } else {
      map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.fromLTRB(48, 90, 72, 50),
          maxZoom: 16,
        ),
      );
    }
  }

  Marker pin(
    LatLng point,
    String label,
    IconData icon,
    Color color, {
    bool muted = false,
  }) => Marker(
    point: point,
    width: 48,
    height: 56,
    child: Semantics(
      label: label.tr,
      image: true,
      child: Tooltip(
        message: label.tr,
        child: Container(
          decoration: BoxDecoration(
            color: muted ? Colors.grey.shade200 : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: muted ? Colors.grey : color, width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0x22000000), blurRadius: 8),
            ],
          ),
          child: Icon(
            icon,
            color: muted ? Colors.grey.shade700 : color,
            size: 25,
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    motion.dispose();
    unawaited(tileReset.close());
    map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final route = widget.route;
    final road = route?.source == 'geoapify' && route!.points.length >= 2;
    final staleRoad =
        widget.stale ||
        (route?.approximate ?? false) ||
        (route != null && DateTime.now().toUtc().isAfter(route.expires));
    return Column(
      children: [
        Expanded(
          child: RepaintBoundary(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: map,
                  options: MapOptions(
                    initialCenter:
                        target ??
                        widget.stops.pickup ??
                        widget.stops.destination ??
                        const LatLng(33.6844, 73.0479),
                    initialZoom: 14.5,
                    onMapReady: () {
                      ready = true;
                      _initialCamera();
                    },
                    onPositionChanged: (_, gesture) {
                      if (gesture && follow) setState(() => follow = false);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.flutter_application_1',
                      tileProvider: tiles,
                      reset: tileReset.stream,
                      errorTileCallback: (_, __, ___) {
                        if (!tileFailure) {
                          tileFailure = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() {});
                          });
                        }
                      },
                    ),
                    if (road)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: route.points,
                            strokeWidth: 9,
                            color: Colors.white.withValues(alpha: .9),
                          ),
                          Polyline(
                            points: route.points,
                            strokeWidth: 5,
                            color: staleRoad ? Colors.grey : AppColors.primary,
                          ),
                        ],
                      ),
                    AnimatedBuilder(
                      animation: motion,
                      builder: (_, __) => MarkerLayer(
                        markers: [
                          if (widget.stops.pickup != null)
                            pin(
                              widget.stops.pickup!,
                              'Pickup point',
                              Icons.storefront_rounded,
                              AppColors.info,
                            ),
                          if (widget.stops.destination != null)
                            pin(
                              widget.stops.destination!,
                              'Delivery destination',
                              Icons.flag_rounded,
                              AppColors.primary,
                            ),
                          if (widget.viewerLocation != null)
                            pin(
                              widget.viewerLocation!,
                              'Your location',
                              Icons.person_pin_circle,
                              AppColors.info,
                            ),
                          if (displayed != null)
                            pin(
                              displayed!,
                              widget.stale
                                  ? 'Last confirmed Rider position'
                                  : 'Confirmed Rider position',
                              Icons.delivery_dining_rounded,
                              AppColors.accent,
                              muted: widget.stale,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                PositionedDirectional(
                  top: 8,
                  start: 12,
                  end: 12,
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        if (widget.onBack != null)
                          _control('Back', Icons.arrow_back, widget.onBack),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                (widget.stale
                                        ? (widget.fix == null
                                              ? 'Location unavailable'
                                              : 'Last known · not live')
                                        : 'Live delivery location')
                                    .tr,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  end: 12,
                  bottom: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onLocate != null) ...[
                        _control(
                          'My location',
                          Icons.person_pin_circle,
                          widget.onLocate,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _control(
                        follow ? 'Following Rider' : 'Recenter and follow',
                        follow ? Icons.gps_fixed : Icons.my_location,
                        target == null
                            ? null
                            : () {
                                setState(() => follow = true);
                                map.move(target!, 15);
                              },
                      ),
                      const SizedBox(width: 8),
                      _control(
                        'Route overview',
                        Icons.zoom_out_map_rounded,
                        _overview,
                      ),
                    ],
                  ),
                ),
                const PositionedDirectional(
                  start: 8,
                  bottom: 6,
                  child: TezMapAttribution(),
                ),
              ],
            ),
          ),
        ),
        Material(
          color: Colors.white,
          elevation: 6,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .34,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.loading)
                    const LinearProgressIndicator(minHeight: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (widget.stops.status.isNotEmpty)
                        Text(
                          ({
                                    'ready': 'Ready for pickup',
                                    'on_the_way': 'On the way',
                                    'accepted': 'Preparing',
                                    'pending': 'Placed',
                                    'delivered': 'Delivered',
                                    'cancelled': 'Cancelled',
                                  }[widget.stops.status] ??
                                  'Active delivery')
                              .tr,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      Text(
                        widget.stale
                            ? 'ETA unavailable'.tr
                            : widget.eta.uiMessage,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      if (road)
                        Text(
                          '${(route.distance / 1000).toStringAsFixed(1)} ${'km'.tr}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      Text(
                        (road
                                ? (staleRoad
                                      ? 'Previous road route'
                                      : route.cacheStatus == 'cached'
                                      ? 'Cached road route'
                                      : 'Road route')
                                : 'Road route unavailable')
                            .tr,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LastLocationUpdate(fix: widget.fix),
                  if (tileFailure)
                    Text(
                      'Map tiles unavailable. Check connection and retry.'.tr,
                    ),
                  if (widget.notice.isNotEmpty)
                    Text(
                      widget.notice.uiMessage,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (road)
                    const Text(
                      'Geoapify · © OpenStreetMap contributors',
                      style: TextStyle(fontSize: 10),
                    ),
                  if (widget.footer != null) widget.footer!,
                  if (widget.onRetry != null)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: widget.loading
                            ? null
                            : () {
                                setState(() => tileFailure = false);
                                tileReset.add(null);
                                widget.onRetry?.call();
                              },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text('Retry'.tr),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _control(String label, IconData icon, VoidCallback? action) =>
      Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(15),
        child: IconButton(
          tooltip: label.tr,
          onPressed: action,
          icon: Icon(icon),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      );
}

class LastLocationUpdate extends StatefulWidget {
  const LastLocationUpdate({super.key, this.fix});
  final DeviceFix? fix;
  @override
  State<LastLocationUpdate> createState() => _LastLocationUpdateState();
}

class _LastLocationUpdateState extends State<LastLocationUpdate> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fix = widget.fix;
    if (fix == null) return Text('Waiting for authorized location'.tr);
    final age = DateTime.now()
        .toUtc()
        .difference(fix.at)
        .inSeconds
        .clamp(0, 864000);
    final stamp = fix.at.toLocal().toString().substring(11, 19);
    return Text(
      '${'Last update'.tr}: $stamp · ${'@seconds seconds ago'.trParams({'seconds': '$age'})} · ±${fix.accuracy.round()} m',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
