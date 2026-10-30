import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/destination_amendment.dart';
import '../../services/delivery_map_stops.dart';
import '../../services/delivery_location.dart' show DeviceFix;
import '../../widgets/tez_map_tiles.dart';
import '../../theme/app_theme.dart';

class DestinationAmendmentEntry extends StatefulWidget {
  const DestinationAmendmentEntry({super.key, required this.orderId});
  final int orderId;
  @override
  State<DestinationAmendmentEntry> createState() =>
      _DestinationAmendmentEntryState();
}

class _DestinationAmendmentEntryState extends State<DestinationAmendmentEntry> {
  late final flow = DestinationAmendmentFlow(
    widget.orderId,
    SupabaseDestinationAmendmentBackend(),
  );
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final work = flow.load();
    if (mounted) setState(() {});
    await work;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (flow.context == null) {
      return flow.code == 'UNAVAILABLE'
          ? TextButton(
              onPressed: load,
              child: Text('Retry delivery location options'.tr),
            )
          : const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delivery location'.tr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Changing the point keeps the order, delivery charge and frozen Rider pay unchanged.'
                  .tr,
            ),
            if (!flow.canChange) Text(flow.message.tr),
            OutlinedButton.icon(
              onPressed: flow.canChange
                  ? () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChangeDeliveryDestinationScreen(
                            orderId: widget.orderId,
                          ),
                        ),
                      );
                      if (mounted) await load();
                    }
                  : null,
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: Text('Change delivery location'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

class ChangeDeliveryDestinationScreen extends StatefulWidget {
  const ChangeDeliveryDestinationScreen({
    super.key,
    required this.orderId,
    this.backend,
  });
  final int orderId;
  final DestinationAmendmentBackend? backend;
  @override
  State<ChangeDeliveryDestinationScreen> createState() =>
      _ChangeDeliveryDestinationScreenState();
}

class _ChangeDeliveryDestinationScreenState
    extends State<ChangeDeliveryDestinationScreen> {
  late final flow = DestinationAmendmentFlow(
    widget.orderId,
    widget.backend ?? SupabaseDestinationAmendmentBackend(),
  );
  StreamSubscription<AuthState>? auth;
  LatLng? selected;
  @override
  void initState() {
    super.initState();
    if (widget.backend == null) {
      final owner = flow.backend.account;
      auth = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        if (flow.backend.account != owner && mounted) {
          setState(() {
            selected = null;
            flow.accountChanged();
          });
        }
      });
    }
    unawaited(load());
  }

  Future<void> load() async {
    final work = flow.load();
    if (mounted) setState(() {});
    await work;
    if (mounted) setState(() {});
  }

  Future<void> choose() async {
    final initial = DeliveryMapStops.point(
      flow.context?['latitude'],
      flow.context?['longitude'],
    );
    if (initial == null) return;
    final owner = flow.backend.account;
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => DeliveryPinPicker(initial: initial)),
    );
    if (mounted && flow.backend.account == owner && point != null) {
      setState(() => selected = point);
    }
  }

  Future<void> save() async {
    final point = selected;
    if (point == null || flow.busy || flow.uncertain) return;
    final owner = flow.backend.account;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm new delivery point'.tr),
        content: SingleChildScrollView(
          child: Text(
            'Choose a real handover point you can reach. The order status, delivery charge and frozen Rider pay stay unchanged. The Rider must review the new point before going Online again.'
                .tr,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirm destination'.tr),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || owner != flow.backend.account) return;
    final work = flow.submit(point.latitude, point.longitude, confirmed: true);
    setState(() {});
    await work;
    if (mounted) setState(() {});
  }

  Future<void> retry() async {
    final work = flow.retry();
    setState(() {});
    await work;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    flow.dispose();
    unawaited(auth?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !flow.busy && !flow.uncertain,
    child: Scaffold(
      appBar: AppBar(title: Text('Change delivery location'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Select a nearby, real handover point on the map.'.tr),
          const SizedBox(height: 16),
          if (flow.busy) const LinearProgressIndicator(),
          if (flow.code.isNotEmpty) Text(flow.message.tr),
          if (selected != null && flow.code != 'OK')
            Text('New delivery point selected'.tr),
          if (flow.canChange && !flow.uncertain) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: flow.busy ? null : choose,
              icon: const Icon(Icons.map_outlined),
              label: Text('Choose delivery point'.tr),
            ),
            FilledButton(
              onPressed: selected == null || flow.busy ? null : save,
              child: Text('Save delivery location'.tr),
            ),
          ],
          if (flow.uncertain)
            FilledButton(
              onPressed: flow.busy ? null : retry,
              child: Text('Retry destination change'.tr),
            ),
          if (!flow.busy && !flow.uncertain && flow.code != 'OK')
            TextButton(onPressed: load, child: Text('Refresh'.tr)),
          if (flow.code == 'OK')
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Done'.tr),
            ),
        ],
      ),
    ),
  );
}

/// Locating only moves the camera. A new point still requires a deliberate tap.
class DeliveryPinPicker extends StatefulWidget {
  const DeliveryPinPicker({super.key, required this.initial});
  final LatLng initial;
  @override
  State<DeliveryPinPicker> createState() => _DeliveryPinPickerState();
}

class _DeliveryPinPickerState extends State<DeliveryPinPicker> {
  final controller = MapController();
  final tiles = tezMapTiles();
  final tileReset = StreamController<void>.broadcast();
  LatLng? selected;
  bool tileFailure = false;
  bool locating = false;
  String problem = '';
  Future<void> locate() async {
    if (locating) return;
    setState(() {
      locating = true;
      problem = '';
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw StateError('GPS');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        throw StateError('Permission');
      }
      final fix = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (!DeviceFix(
        fix.latitude,
        fix.longitude,
        fix.accuracy,
        fix.timestamp,
      ).valid(DateTime.now().toUtc())) {
        throw StateError('Accuracy');
      }
      controller.move(LatLng(fix.latitude, fix.longitude), 17);
    } catch (_) {
      if (mounted) {
        setState(
          () => problem =
              'Current location unavailable. Check GPS and permission, or choose the actual point manually.',
        );
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    unawaited(tileReset.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Select Delivery Location'.tr)),
    body: Column(
      children: [
        Expanded(
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: widget.initial,
              initialZoom: 16,
              onTap: (_, point) {
                if (!tileFailure) setState(() => selected = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.flutter_application_1',
                tileProvider: tiles,
                reset: tileReset.stream,
                errorTileCallback: (_, __, ___) {
                  if (!tileFailure && mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !tileFailure) {
                        setState(() {
                          tileFailure = true;
                          problem =
                              'Map tiles unavailable. Check connection and retry.';
                        });
                      }
                    });
                  }
                },
              ),
              MarkerLayer(
                markers: [
                  if (selected != null)
                    Marker(
                      point: selected!,
                      width: 48,
                      height: 48,
                      child: Semantics(
                        label: 'New delivery point selected'.tr,
                        child: const Icon(
                          Icons.location_pin,
                          size: 44,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const TezMapAttribution(),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Tap the real handover point. Using My location only centers the map.'
                      .tr,
                ),
                if (problem.isNotEmpty) Text(problem.tr),
                if (tileFailure)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        tileFailure = false;
                        problem = '';
                        selected = null;
                      });
                      tileReset.add(null);
                    },
                    child: Text('Retry'.tr),
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: locating ? null : locate,
                      icon: const Icon(Icons.my_location),
                      label: Text('My location'.tr),
                    ),
                    FilledButton(
                      onPressed: selected == null || locating || tileFailure
                          ? null
                          : () => Navigator.pop(context, selected),
                      child: Text('Use selected point'.tr),
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
