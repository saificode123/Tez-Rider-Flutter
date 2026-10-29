import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/stage2_ui_strings.dart';
import '../services/delivery_location_platform.dart';
import '../services/delivery_map_stops.dart';
import '../services/delivery_route.dart';
import '../widgets/delivery_map_view.dart';
import '../widgets/rider_identity_card.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.orderId});
  final int? orderId;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final client = Supabase.instance.client;
  CustomerLocationFeed? feed;
  DeliveryRouteController? route;
  DeliveryMapStops stops = const DeliveryMapStops();
  LatLng? viewer;
  bool loading = true, locating = false;
  String problem = '';
  int generation = 0;
  int? identityOrder;
  double? fare;
  StreamSubscription<AuthState>? auth;
  @override
  void initState() {
    super.initState();
    final owner = client.auth.currentUser?.id;
    auth = client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          event.session?.user.id != owner) {
        generation++;
        route?.onClose();
        route = null;
        unawaited(feed?.dispose());
        if (mounted) {
          setState(() {
            stops = const DeliveryMapStops();
            viewer = null;
            identityOrder = null;
            fare = null;
            loading = false;
            locating = false;
            problem = 'Account changed. Open tracking again.';
          });
        }
      }
    });
    unawaited(open());
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) unawaited(open());
  }

  Future<void> open() async {
    final request = ++generation;
    route?.onClose();
    route = null;
    final old = feed;
    feed = null;
    await old?.dispose();
    if (!mounted || request != generation) return;
    setState(() {
      loading = true;
      identityOrder = null;
      fare = null;
      stops = const DeliveryMapStops();
      viewer = null;
      problem = '';
    });
    try {
      final actor = await client
          .rpc('fr21_actor')
          .timeout(const Duration(seconds: 8));
      if (actor == null) throw StateError('Sign in required');
      final query = client
          .from('orders')
          .select('id,rider_id,fare,order_status')
          .eq('user_id', actor);
      final order = widget.orderId == null
          ? await query
                .eq('order_status', 'on_the_way')
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle()
                .timeout(const Duration(seconds: 8))
          : await query
                .eq('id', widget.orderId!)
                .maybeSingle()
                .timeout(const Duration(seconds: 8));
      if (!mounted || request != generation) return;
      if (order == null) {
        problem = 'No active delivery location';
        return;
      }
      identityOrder = order['id'] as int;
      fare = (order['fare'] as num?)?.toDouble();
      try {
        final nextStops = await DeliveryMapStops.load(client, identityOrder!);
        if (!mounted || request != generation) return;
        stops = nextStops;
      } catch (_) {
        if (!mounted || request != generation) return;
        problem = 'Delivery stops unavailable. Retry when connected.';
      }
      if (!mounted || request != generation) return;
      final next = CustomerLocationFeed(identityOrder!);
      feed = next;
      route = DeliveryRouteController(
        identityOrder!,
        next.state,
        fetchDeliveryRoadRoute,
      )..start();
      await next.start();
      if (!mounted || request != generation) await next.dispose();
    } catch (_) {
      if (mounted && request == generation) {
        problem =
            'Delivery tracking unavailable. Check your connection and retry.';
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> myLocation() async {
    if (locating) return;
    final request = generation;
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('GPS off');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Permission denied');
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));
      if (mounted && request == generation) {
        setState(() => viewer = LatLng(position.latitude, position.longitude));
      }
    } catch (_) {
      if (mounted && request == generation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your location is unavailable. Check GPS and location permission.'
                  .tr,
            ),
          ),
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => locating = false);
    }
  }

  @override
  void dispose() {
    generation++;
    unawaited(auth?.cancel());
    route?.onClose();
    unawaited(feed?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    Widget map() {
      final state = feed?.state;
      final allowed = state?.authorized.value == true;
      final fix = allowed
          ? state?.position.value ?? state?.lastKnown.value
          : null;
      final stale = state?.stale.value ?? true;
      final availability = state?.availability.value;
      final ended = [
        'ENDED',
        'FORBIDDEN',
        'UNAUTHORIZED',
      ].contains(availability);
      final trackingNotice = availability == 'ENDED'
          ? 'Delivery tracking ended.'
          : availability == 'STOPPED'
          ? 'The Rider has stopped sharing location.'
          : '';
      return DeliveryMapView(
        key: ValueKey(identityOrder),
        fix: fix,
        stale: stale,
        stops: ended ? const DeliveryMapStops() : stops,
        viewerLocation: viewer,
        onLocate: locating ? null : myLocation,
        route: allowed ? route?.route.value : null,
        eta: route?.label.value ?? 'ETA unavailable',
        loading: route?.loading.value ?? false,
        notice: trackingNotice.isNotEmpty
            ? trackingNotice
            : problem.isNotEmpty
            ? problem
            : route?.notice.value ?? '',
        onRetry: () => unawaited(open()),
        onBack: () => Get.back(),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fare != null)
              Text(
                'Delivery charges: PKR @slot0end'.uiTr({
                  'slot0end': fare!.toStringAsFixed(0),
                }),
              ),
            if (identityOrder != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Rider details'.tr),
                children: [
                  RiderIdentityCard(
                    key: ValueKey(identityOrder),
                    orderId: identityOrder!,
                  ),
                ],
              ),
          ],
        ),
      );
    }

    return Scaffold(body: feed == null ? map() : Obx(map));
  }
}
