import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/prescription_service.dart';
import '../services/optional_media_service.dart';
import 'private_photo.dart';
import 'prescription_upload_widget.dart';

class PrescriptionOrderPanel extends StatefulWidget {
  const PrescriptionOrderPanel({
    super.key,
    required this.orderId,
    required this.portions,
    this.service,
  });
  final int orderId;
  final List<Map<String, dynamic>> portions;
  final PrescriptionService? service;
  @override
  State<PrescriptionOrderPanel> createState() => _PrescriptionOrderPanelState();
}

class _PrescriptionOrderPanelState extends State<PrescriptionOrderPanel> {
  late final service = widget.service ?? PrescriptionService();
  List<Map<String, dynamic>>? rows;
  bool failed = false;
  int generation = 0;
  StreamSubscription<AuthState>? auth;
  @override
  void initState() {
    super.initState();
    if (widget.service == null) {
      auth = Supabase.instance.client.auth.onAuthStateChange.listen(
        (_) => load(),
      );
    }
    load();
  }

  Future<void> load() async {
    if (!mounted) return;
    final request = ++generation;
    setState(() {
      rows = null;
      failed = false;
    });
    try {
      final value = await service.list(orderId: widget.orderId);
      if (mounted && request == generation) setState(() => rows = value);
    } catch (_) {
      if (mounted && request == generation) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    ++generation;
    unawaited(auth?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Card(
        child: Column(
          children: [
            Text('Prescriptions could not be loaded. Retry.'.tr),
            TextButton(onPressed: load, child: Text('Retry'.tr)),
          ],
        ),
      );
    }
    if (rows == null) return const LinearProgressIndicator();
    return Column(
      children: [for (final portion in widget.portions) panel(portion)],
    );
  }

  Widget panel(Map<String, dynamic> portion) {
    final matching = rows!
        .where((r) => r['vendor_order_id'] == portion['id'])
        .toList();
    final current = matching.isEmpty ? null : matching.last;
    final waiting =
        current?['status'] == 'pending' || current?['status'] == 'approved';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          portion['vendor']?.toString() ?? 'Prescription'.tr,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (current != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Prescription status'.tr),
                  Text(current['status'].toString().tr),
                  if (current['vendor_notes'] != null)
                    Text(current['vendor_notes']),
                  if (widget.service == null)
                    PrivatePhoto(
                      imageUrl: current['prescription_image_url'],
                      height: 150,
                      fit: BoxFit.contain,
                      service: OptionalMediaService(),
                      accountChanges: Supabase
                          .instance
                          .client
                          .auth
                          .onAuthStateChange
                          .map((_) {}),
                    ),
                ],
              ),
            ),
          ),
        if (!waiting)
          PrescriptionUploadWidget(
            key: ValueKey('prescription-${portion['id']}'),
            vendorOrderId: portion['id'].toString(),
            customerId: '',
            onUploadSuccess: load,
          ),
      ],
    );
  }
}
