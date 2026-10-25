import 'package:get/get.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/private_photo_service.dart';
import 'private_photo_editor.dart';

class DeliveryPhotoPanel extends StatefulWidget {
  const DeliveryPhotoPanel({super.key, required this.orderId});
  final int orderId;
  @override
  State<DeliveryPhotoPanel> createState() => _DeliveryPhotoPanelState();
}

class _DeliveryPhotoPanelState extends State<DeliveryPhotoPanel> {
  final client = Supabase.instance.client;
  StreamSubscription<AuthState>? auth;
  Map? value;
  bool loading = true;
  int generation = 0;
  String? error;
  late final account = client.auth.currentUser?.id;
  @override
  void initState() {
    super.initState();
    auth = client.auth.onAuthStateChange.listen((_) {
      if (client.auth.currentUser?.id != account) {
        generation++;
        if (mounted) {
          setState(() {
            value = null;
            loading = false;
            error = 'Account changed. Open the order again.';
          });
        }
      }
    });
    load();
  }

  Future<void> load() async {
    final request = ++generation;
    setState(() {
      loading = true;
      value = null;
      error = null;
    });
    try {
      if (account == null || client.auth.currentUser?.id != account) {
        throw StateError('account');
      }
      final result = await client
          .rpc('final2_delivery_photo', params: {'p_order_id': widget.orderId})
          .timeout(const Duration(seconds: 15));
      if (result is! Map ||
          result['can_upload'] is! bool ||
          result['reference'] != null &&
              (result['reference'] is! String ||
                  !isPrivatePhoto(result['reference']))) {
        throw const FormatException('Photo not confirmed.');
      }
      if (mounted && generation == request) setState(() => value = result);
    } catch (_) {
      if (mounted && generation == request) {
        setState(() => error = 'Delivery photo unavailable. Retry.');
      }
    } finally {
      if (mounted && generation == request) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    generation++;
    unawaited(auth?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text("Delivery photo".tr),
            if (loading)
              const LinearProgressIndicator()
            else if (value != null) ...[
              if (value!['reference'] == null && value!['can_upload'] != true)
                Text("No delivery photo has been recorded.".tr),
              PrivatePhotoEditor(
                key: ValueKey(widget.orderId),
                orderId: widget.orderId,
                reference: value!['reference'],
                canUpload: value!['can_upload'],
                onSaved: (ref) =>
                    setState(() => value = {...value!, 'reference': ref}),
              ),
            ] else
              Text(error ?? "Photo unavailable.".tr),
            TextButton(
              onPressed: loading || client.auth.currentUser?.id != account
                  ? null
                  : load,
              child: Text("Refresh delivery photo".tr),
            ),
          ],
        ),
      ),
    );
  }
}
