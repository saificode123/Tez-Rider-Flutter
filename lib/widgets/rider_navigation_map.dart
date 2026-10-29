import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/delivery_location.dart';
import '../services/delivery_map_stops.dart';
import '../services/delivery_route.dart';
import 'delivery_map_view.dart';

/// Uses the Rider's existing owned device stream. Never subscribes to another
/// Rider, enables sharing, requests GPS permission or changes fulfillment.
class RiderNavigationMap extends StatefulWidget {
  const RiderNavigationMap({
    super.key,
    required this.orderId,
    required this.status,
    required this.location,
    required this.onBack,
    required this.online,
    this.isDelivery = true,
  });
  final int orderId;
  final String status;
  final RiderLocationService location;
  final VoidCallback onBack;
  final bool isDelivery;
  final bool online;
  @override
  State<RiderNavigationMap> createState() => _RiderNavigationMapState();
}

class _RiderNavigationMapState extends State<RiderNavigationMap> {
  final routeLocation = CustomerLocationState();
  final ownFresh = false.obs;
  DeliveryRouteController? route;
  DeliveryMapStops stops = const DeliveryMapStops();
  Worker? fixWorker;
  Timer? freshness;
  int generation = 0;
  String problem = '';
  bool accountChanged = false;
  StreamSubscription<AuthState>? auth;
  @override
  void initState() {
    super.initState();
    final owner = Supabase.instance.client.auth.currentUser?.id;
    auth = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          event.session?.user.id != owner) {
        generation++;
        accountChanged = true;
        routeLocation.clear();
        route?.onClose();
        if (mounted) {
          setState(() {
            stops = const DeliveryMapStops();
            problem = 'Account changed. Open tracking again.';
          });
        }
      }
    });
    createRoute();
    fixWorker = everAll([
      widget.location.latestFix,
      widget.location.sharing,
    ], (_) => sync());
    freshness = Timer.periodic(const Duration(seconds: 1), (_) => sync());
    sync();
    unawaited(loadStops());
  }

  void createRoute() {
    final pickup = widget.status != 'on_the_way';
    route = DeliveryRouteController(
      widget.orderId,
      routeLocation,
      (id) => fetchDeliveryRoadRoute(id, pickup: pickup),
      target: pickup ? 'pickup' : 'delivery',
    )..start();
  }

  Future<void> loadStops() async {
    if (!widget.isDelivery || accountChanged) return;
    final request = ++generation;
    try {
      final next = await DeliveryMapStops.load(
        Supabase.instance.client,
        widget.orderId,
      );
      if (mounted && request == generation) {
        setState(() {
          stops = next;
          problem = '';
        });
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => problem = 'Delivery stops unavailable. Retry when connected.',
        );
      }
    }
  }

  void sync() {
    if (accountChanged) return;
    final fix = widget.location.latestFix.value;
    ownFresh.value = fix != null && fix.valid(DateTime.now().toUtc());
    final live =
        widget.isDelivery &&
        widget.online &&
        (widget.status == 'ready' ||
            (widget.status == 'on_the_way' && widget.location.sharing.value)) &&
        fix != null &&
        fix.valid(DateTime.now().toUtc());
    if (live) {
      routeLocation.authorized.value = true;
      routeLocation.position.value = fix;
      routeLocation.lastKnown.value = fix;
      routeLocation.stale.value = false;
    } else {
      routeLocation.clear();
    }
  }

  @override
  void didUpdateWidget(RiderNavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      route?.onClose();
      routeLocation.clear();
      createRoute();
      sync();
      unawaited(loadStops());
    }
    if (oldWidget.online != widget.online) sync();
  }

  @override
  void dispose() {
    generation++;
    unawaited(auth?.cancel());
    fixWorker?.dispose();
    freshness?.cancel();
    route?.onClose();
    routeLocation.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final own = widget.location.latestFix.value;
    final fix = accountChanged ? null : own;
    final fresh = ownFresh.value;
    final navigating = widget.status == 'on_the_way';
    final shared = widget.location.sharing.value;
    // Reading stale also causes the one-second freshness tick to repaint only
    // when freshness actually changes, not on every timer tick.
    final stale = routeLocation.stale.value;
    return DeliveryMapView(
      fix: fix,
      stale: !fresh,
      stops: stops,
      route: !stale ? route?.route.value : null,
      eta: route?.label.value ?? 'ETA unavailable',
      loading: route?.loading.value ?? false,
      onBack: widget.onBack,
      onRetry: () {
        unawaited(loadStops());
        unawaited(route?.refreshRoute(retry: true));
      },
      notice: problem.isNotEmpty
          ? problem
          : !navigating
          ? 'Confirm pickup before starting delivery.'
          : !shared
          ? 'Enable sharing to load the authorized road route.'
          : route?.notice.value ?? '',
      footer: Text(
        (navigating ? 'Navigation to customer' : 'Navigation to pickup').tr,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  });
}
