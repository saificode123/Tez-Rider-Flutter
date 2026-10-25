import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/store_settings_service.dart';
import '../../widgets/role_access_gate.dart';

class StoreSettingsScreen extends StatelessWidget {
  const StoreSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => RoleAccessGate(
    role: 'vendor',
    builder: (_) => const StoreSettingsPanel(),
  );
}

class StoreSettingsPanel extends StatefulWidget {
  const StoreSettingsPanel({super.key, this.service, this.locate});
  final StoreSettingsService? service;
  final Future<({double lat, double lng})> Function()? locate;
  @override
  State<StoreSettingsPanel> createState() => _StoreSettingsPanelState();
}

class _StoreSettingsPanelState extends State<StoreSettingsPanel> {
  late final service = widget.service ?? StoreSettingsService();
  late final String? owner;
  final name = TextEditingController(), address = TextEditingController();
  StreamSubscription<void>? auth;
  bool loading = true, saving = false, locating = false, changed = false;
  int? version;
  int generation = 0;
  double? lat, lng;
  String? error, notice;
  bool active = false;
  bool get locked =>
      loading || saving || locating || changed || service.pending;
  @override
  void initState() {
    super.initState();
    owner = service.identity();
    auth = service.accountChanges.listen((_) {
      if (!mounted || service.identity() == owner) return;
      generation++;
      name.clear();
      address.clear();
      setState(() {
        changed = true;
        version = null;
        lat = null;
        lng = null;
        notice = null;
        error = 'Account changed. Open store settings again.';
      });
    });
    load();
  }

  void apply(Map store) {
    name.text = store['store_name'] ?? '';
    address.text = store['address'] ?? '';
    version = store['version'];
    lat = (store['latitude'] as num?)?.toDouble();
    lng = (store['longitude'] as num?)?.toDouble();
    active = store['is_active'];
  }

  Future<void> load() async {
    if (changed || saving || locating || service.pending) return;
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
      notice = null;
    });
    try {
      final store = await service.load();
      if (mounted && request == generation) setState(() => apply(store));
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = 'Store details unavailable. Retry loading.');
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (changed || saving || loading || locating || version == null) return;
    final validation = StoreSettingsService.validate(
      name.text,
      address.text,
      lat,
      lng,
    );
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    final request = generation;
    setState(() {
      saving = true;
      error = null;
      notice = null;
    });
    try {
      final result = await service.save(
        version: version!,
        name: name.text,
        address: address.text,
        lat: lat,
        lng: lng,
      );
      if (!mounted || request != generation) return;
      setState(() {
        apply(result['store']);
        notice = result['code'] == 'ALREADY_APPLIED'
            ? 'Original save confirmed. Current store details loaded.'
            : 'Store details saved.';
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => error = service.pending
              ? 'Save not confirmed. Retry the original details.'
              : 'Store could not be saved. Reload before editing.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> locate() async {
    if (locked) return;
    final request = generation;
    setState(() {
      locating = true;
      error = null;
      notice = null;
    });
    try {
      final ({double lat, double lng}) fix;
      if (widget.locate != null) {
        fix = await widget.locate!();
      } else {
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
        final position = await Geolocator.getCurrentPosition().timeout(
          const Duration(seconds: 20),
        );
        fix = (lat: position.latitude, lng: position.longitude);
      }
      if (!fix.lat.isFinite ||
          !fix.lng.isFinite ||
          fix.lat.abs() > 90 ||
          fix.lng.abs() > 180) {
        throw StateError('invalid');
      }
      if (mounted && request == generation) {
        setState(() {
          lat = fix.lat;
          lng = fix.lng;
        });
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => error =
              'Pickup location unavailable. Check location permission and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  void dispose() {
    generation++;
    unawaited(auth?.cancel());
    name.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      appBar: AppBar(title: Text('Store Settings'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (loading || saving || locating) const LinearProgressIndicator(),
          if (error != null)
            Semantics(liveRegion: true, child: Text(error!.tr)),
          if (notice != null)
            Semantics(liveRegion: true, child: Text(notice!.tr)),
          TextField(
            controller: name,
            enabled: !locked && version != null,
            maxLength: 200,
            decoration: InputDecoration(labelText: 'Shop / Store Name'.tr),
          ),
          TextField(
            controller: address,
            enabled: !locked && version != null,
            maxLength: 500,
            decoration: InputDecoration(labelText: 'Store Address'.tr),
          ),
          if (!changed && version != null)
            Text((active ? 'Store active' : 'Store inactive').tr),
          Text(
            lat == null || lng == null
                ? 'Pickup location not set.'.tr
                : 'Pickup location: @lat, @lng'.trParams({
                    'lat': lat!.toStringAsFixed(5),
                    'lng': lng!.toStringAsFixed(5),
                  }),
          ),
          OutlinedButton(
            onPressed: locked || version == null ? null : locate,
            child: Text('Use my current pickup location'.tr),
          ),
          FilledButton(
            onPressed:
                changed || loading || saving || locating || version == null
                ? null
                : save,
            child: Text(
              (service.pending ? 'Retry original save' : 'Save store details')
                  .tr,
            ),
          ),
          TextButton(
            onPressed:
                loading || saving || locating || changed || service.pending
                ? null
                : load,
            child: Text('Reload store details'.tr),
          ),
        ],
      ),
    );
  }
}
