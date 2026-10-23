import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/order_payment_panel.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../../controllers/dispute_controller.dart';
import '../../services/dispute_service.dart';
import '../../widgets/dispute_evidence_viewer.dart';

class DisputeScreen extends StatefulWidget {
  const DisputeScreen({super.key, this.orderId});
  final int? orderId;
  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  late final DisputeController controller;
  final tag = newDisputeRequestId();
  final description = TextEditingController();
  bool picking = false;
  @override
  void initState() {
    super.initState();
    controller = Get.put(DisputeController(), tag: tag);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await controller.initialize(selectedOrder: widget.orderId);
    if (mounted) description.text = controller.description;
  }

  Future<void> _submit() async {
    await controller.submit();
    if (mounted && controller.message.value == disputeSuccess) {
      Navigator.pop(context, true);
      Get.snackbar(
        'Dispute submitted',
        disputeSuccess,
        duration: const Duration(seconds: 6),
      );
    }
  }

  Future<void> _pick(ImageSource source) async {
    if (picking || !controller.editable || controller.images.length >= 3) {
      return;
    }
    setState(() => picking = true);
    try {
      await controller.saveDraft();
      final image = await controller.picker.pick(source);
      if (image != null && mounted) {
        controller.images.add(image);
        await controller.saveDraft();
      }
    } catch (e) {
      controller.error.value = disputeError(e);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  void dispose() {
    description.dispose();
    Get.delete<DisputeController>(tag: tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Submit dispute')),
    body: Obx(
      () => controller.loading.value
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Submit within 24 hours of delivery. Select 1–3 JPEG or PNG images, up to 5 MB each.',
                ),
                const SizedBox(height: 16),
                if (controller.message.value.isNotEmpty)
                  Text(
                    controller.message.value,
                    style: const TextStyle(color: Colors.green),
                  ),
                if (controller.images.isEmpty && controller.paths.isNotEmpty)
                  Text(
                    '${controller.paths.length} evidence images are already uploaded. Retry to confirm submission.',
                  ),
                DropdownButtonFormField<int>(
                  initialValue:
                      controller.orders.any(
                        (o) => o['id'] == controller.orderId,
                      )
                      ? controller.orderId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Delivered order',
                  ),
                  items: controller.orders
                      .map(
                        (o) => DropdownMenuItem(
                          value: o['id'] as int,
                          child: Text('Order #${o['id']} • PKR ${o['amount']}'),
                        ),
                      )
                      .toList(),
                  onChanged: controller.editable
                      ? (value) {
                          controller.orderId = value;
                        }
                      : null,
                ),
                if (controller.orders.isEmpty)
                  const Text(
                    'No eligible delivered orders. Older orders remain in Order History.',
                  ),
                TextButton(
                  onPressed: controller.busy.value
                      ? null
                      : controller.moreOrders,
                  child: const Text('Load more orders'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: controller.reasons.contains(controller.reason)
                      ? controller.reason
                      : null,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: controller.reasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: controller.editable
                      ? (value) {
                          controller.reason = value;
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  enabled: controller.editable,
                  maxLines: 5,
                  maxLength: controller.descriptionLimit,
                  decoration: const InputDecoration(
                    labelText: 'Required description',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    controller.description = value;
                  },
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < controller.images.length; i++)
                      SizedBox(
                        width: 96,
                        child: Column(
                          children: [
                            Image.memory(
                              controller.images[i].bytes,
                              height: 90,
                              fit: BoxFit.cover,
                            ),
                            IconButton(
                              tooltip: 'Remove evidence ${i + 1}',
                              onPressed: controller.editable
                                  ? () {
                                      controller.images.removeAt(i);
                                      unawaited(controller.saveDraft());
                                    }
                                  : null,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed:
                          controller.editable &&
                              !picking &&
                              controller.images.length < 3
                          ? () => _pick(ImageSource.gallery)
                          : null,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                    ),
                    TextButton.icon(
                      onPressed:
                          controller.editable &&
                              !picking &&
                              controller.images.length < 3
                          ? () => _pick(ImageSource.camera)
                          : null,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera'),
                    ),
                  ],
                ),
                if (controller.busy.value) ...[
                  const LinearProgressIndicator(),
                  Text(
                    'Evidence ${controller.completedImages.value}/${controller.images.length > controller.paths.length ? controller.images.length : controller.paths.length} uploaded; confirming submission…',
                  ),
                ],
                if (controller.error.value.isNotEmpty)
                  Text(
                    controller.error.value,
                    style: const TextStyle(color: Colors.red),
                  ),
                if (controller.error.value.isNotEmpty &&
                    controller.requestId == null)
                  TextButton(
                    onPressed: controller.busy.value ? null : _initialize,
                    child: const Text('Retry loading orders'),
                  ),
                if (controller.uncertain.value)
                  const Text(
                    'Keep this submission unchanged while its result is checked.',
                  ),
                FilledButton(
                  onPressed: controller.busy.value || picking ? null : _submit,
                  child: Text(
                    controller.requestId == null
                        ? 'Submit dispute'
                        : 'Retry submission',
                  ),
                ),
                TextButton(
                  onPressed: controller.busy.value
                      ? null
                      : () async {
                          await controller.discard();
                        },
                  child: const Text('Discard unfinished draft'),
                ),
                TextButton(
                  onPressed: () => Get.to(() => const DisputeHistoryScreen()),
                  child: const Text('My disputes'),
                ),
              ],
            ),
    ),
  );
}

class DisputeHistoryScreen extends StatefulWidget {
  const DisputeHistoryScreen({super.key});
  @override
  State<DisputeHistoryScreen> createState() => _DisputeHistoryScreenState();
}

class _DisputeHistoryScreenState extends State<DisputeHistoryScreen> {
  final backend = SupabaseDisputeBackend();
  final rows = <Map<String, dynamic>>[];
  bool loading = false, hasMore = true;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool refresh = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await backend.history(
        before: refresh || rows.isEmpty ? null : rows.last['id'] as int,
      );
      if (mounted) {
        setState(() {
          if (refresh) rows.clear();
          rows.addAll(data);
          hasMore = data.length == 30;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = disputeError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My disputes'),
      actions: [
        IconButton(
          onPressed: loading ? null : () => _load(refresh: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () async {
        await Get.to(() => const DisputeScreen());
        if (mounted) await _load(refresh: true);
      },
      child: const Icon(Icons.add),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (rows.isEmpty && !loading && error == null)
          const Text('No disputes yet.'),
        for (final row in rows)
          Card(
            child: ListTile(
              title: Text('Order #${row['order_id']} • ${row['reason']}'),
              subtitle: Text(disputeStatusLabel(row['status'].toString())),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Get.to(() => DisputeDetailScreen(id: row['id'] as int)),
            ),
          ),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (hasMore || error != null)
          TextButton(
            onPressed: loading ? null : () => _load(),
            child: Text(error == null ? 'Load more' : 'Retry'),
          ),
      ],
    ),
  );
}

String disputeStatusLabel(String status) => status
    .replaceAll('_', ' ')
    .toLowerCase()
    .split(' ')
    .map(
      (word) =>
          word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');

class DisputeDetailScreen extends StatefulWidget {
  const DisputeDetailScreen({super.key, required this.id});
  final int id;
  @override
  State<DisputeDetailScreen> createState() => _DisputeDetailScreenState();
}

class _DisputeDetailScreenState extends State<DisputeDetailScreen> {
  Map<String, dynamic>? detail;
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await SupabaseDisputeBackend().detail(widget.id);
      if (mounted) setState(() => detail = data);
    } catch (e) {
      if (mounted) setState(() => error = disputeError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dispute details')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : detail == null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error ?? 'Dispute unavailable.'),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Order #${detail!['order_id']} • PKR ${detail!['amount']}'),
              Text(
                disputeStatusLabel(detail!['status'].toString()),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('Submitted: ${detail!['created_at']}'),
              const SizedBox(height: 16),
              Text(detail!['reason'].toString()),
              Text(detail!['description'].toString()),
              if (detail!['decision'] != null) ...[
                const SizedBox(height: 16),
                Text('Admin decision: ${detail!['decision']}'),
                Text('Admin note: ${detail!['admin_note']}'),
                Text('Decided: ${detail!['decided_at']}'),
                if (detail!['refund_pending'] == true)
                  const Text(
                    'Refund eligibility was recorded. Check payment status for any confirmed cash return.',
                  ),
              ],
              if (detail!['order_id'] is int)
                TextButton(
                  onPressed: () =>
                      showOrderPayment(context, detail!['order_id'] as int),
                  child: const Text('Payment / refund status'),
                ),
              for (var i = 1; i <= (detail!['evidence_count'] as int); i++)
                TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        DisputeEvidenceViewer(disputeId: widget.id, index: i),
                  ),
                  icon: const Icon(Icons.image),
                  label: Text('View evidence $i'),
                ),
            ],
          ),
  );
}
