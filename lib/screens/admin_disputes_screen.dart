import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../services/admin_dispute_service.dart';
import '../widgets/dispute_evidence_viewer.dart';
import 'customer/dispute_screen.dart' show disputeStatusLabel;

class AdminDisputeQueue extends StatefulWidget {
  const AdminDisputeQueue({
    super.key,
    required this.controller,
    required this.active,
  });
  final AdminController controller;
  final bool active;
  @override
  State<AdminDisputeQueue> createState() => _AdminDisputeQueueState();
}

class _AdminDisputeQueueState extends State<AdminDisputeQueue> {
  AdminController get controller => widget.controller;
  bool detailsOpen = false;
  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(controller.setDisputeTabActive(true));
  }

  @override
  void didUpdateWidget(covariant AdminDisputeQueue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !detailsOpen) {
      unawaited(controller.setDisputeTabActive(true));
    }
    if (!widget.active && oldWidget.active) {
      unawaited(controller.setDisputeTabActive(false));
    }
  }

  @override
  void dispose() {
    controller.closeDisputeQueue();
    super.dispose();
  }

  Future<void> _open(int id) async {
    if (detailsOpen) return;
    detailsOpen = true;
    controller.closeDisputeQueue();
    await Get.to<void>(
      () => AdminDisputeDetails(id: id, controller: controller),
    );
    detailsOpen = false;
    if (mounted && widget.active) await controller.openDisputeQueue();
  }

  @override
  Widget build(BuildContext context) => Obx(
    () => CustomScrollView(
      slivers: [
        const SliverAppBar(
          title: Text('Dispute Resolution'),
          floating: true,
          automaticallyImplyLeading: false,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue:
                      controller.disputeStatuses.contains(
                        controller.disputeFilter.value,
                      )
                      ? controller.disputeFilter.value
                      : 'ALL',
                  decoration: const InputDecoration(labelText: 'Status filter'),
                  items: [
                    const DropdownMenuItem(
                      value: 'ALL',
                      child: Text('All statuses'),
                    ),
                    ...controller.disputeStatuses.map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(disputeStatusLabel(s)),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      controller.filterDisputes(value == 'ALL' ? null : value),
                ),
                if (controller.disputeError.value != null)
                  Text(
                    controller.disputeError.value!,
                    style: const TextStyle(color: Colors.red),
                  ),
                TextButton(
                  onPressed: controller.disputeLoading.value
                      ? null
                      : controller.retryDisputes,
                  child: const Text('Retry / refresh disputes'),
                ),
                if (controller.disputeLoading.value)
                  const LinearProgressIndicator(),
                if (controller.disputes.isEmpty &&
                    !controller.disputeLoading.value &&
                    controller.disputeError.value == null)
                  const Text('No disputes for this filter.'),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((_, i) {
              final d = controller.disputes[i];
              return Card(
                child: ListTile(
                  title: Text(
                    'Dispute #${d['id']} • Order #${d['order_id'] ?? 'Unavailable'}',
                  ),
                  subtitle: Text(
                    '${d['reason']}\n${disputeStatusLabel(d['status'].toString())} • ${d['created_at'] ?? 'Unknown time'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(d['id'] as int),
                ),
              );
            }, childCount: controller.disputes.length),
          ),
        ),
        if (controller.hasMoreDisputes.value)
          SliverToBoxAdapter(
            child: TextButton(
              onPressed: controller.disputeLoading.value
                  ? null
                  : () => controller.refreshDisputes(append: true),
              child: const Text('Load more disputes'),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    ),
  );
}

class AdminDisputeDetails extends StatefulWidget {
  const AdminDisputeDetails({
    super.key,
    required this.id,
    required this.controller,
  });
  final int id;
  final AdminController controller;
  @override
  State<AdminDisputeDetails> createState() => _AdminDisputeDetailsState();
}

class _AdminDisputeDetailsState extends State<AdminDisputeDetails> {
  final note = TextEditingController();
  AdminController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    controller.leaveDisputeDetail();
    if (controller.pendingDisputeId == widget.id) {
      note.text = controller.pendingNote ?? '';
    }
    unawaited(controller.loadDisputeDetail(widget.id));
  }

  @override
  void dispose() {
    note.dispose();
    controller.leaveDisputeDetail();
    super.dispose();
  }

  Future<void> _decision(String decision) async {
    if (controller.decisionBusy.value) return;
    final validation = validateAdminNote(
      note.text,
      controller.noteMinimum,
      controller.noteMaximum,
    );
    if (validation != null) {
      controller.decisionError.value = validation;
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          decision == 'RESOLVED'
              ? 'Resolve this dispute?'
              : 'Reject this dispute?',
        ),
        content: Text(
          decision == 'RESOLVED'
              ? 'Record the final decision and a pending refund action. Money will not be returned by this app.\n\n${note.text.trim()}'
              : 'Record a final rejection and notify the customer. This decision cannot be changed.\n\n${note.text.trim()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm decision'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await controller.submitDisputeDecision(widget.id, decision, note.text);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Dispute #${widget.id}')),
    body: Obx(() {
      final d = controller.disputeDetail.value;
      if (controller.detailLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (d == null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(controller.decisionError.value ?? 'Dispute unavailable.'),
              TextButton(
                onPressed: () => controller.loadDisputeDetail(widget.id),
                child: const Text('Retry details'),
              ),
            ],
          ),
        );
      }
      final eligible = disputeDecisionAllowed(d),
          busy = controller.decisionBusy.value;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            disputeStatusLabel(d['status'].toString()),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('Submitted: ${d['created_at']}'),
          Text(
            'Order #${d['order_id'] ?? 'Unavailable'} • PKR ${d['amount'] ?? 'Unavailable'}',
          ),
          Text(
            'Order: ${d['order_status'] ?? 'Unavailable'} • ${d['payment_method'] ?? 'Unavailable'}',
          ),
          Text(
            'Customer: ${d['customer_name'] ?? 'Unavailable'} (#${d['customer_id'] ?? 'Unavailable'})',
          ),
          if (d['customer_email'] != null) Text(d['customer_email'].toString()),
          for (final v in controller.disputeVendors)
            Text('Vendor: ${v['name']} (#${v['id']})'),
          if (controller.disputeVendors.isEmpty)
            const Text('Vendor: unavailable'),
          if (controller.moreDisputeVendors.value)
            TextButton(
              onPressed: controller.vendorsLoading.value
                  ? null
                  : () => controller.loadMoreDisputeVendors(widget.id),
              child: const Text('Load more vendors'),
            ),
          Text('Rider: ${d['rider_name'] ?? 'Not assigned'}'),
          const SizedBox(height: 16),
          Text(d['reason'].toString()),
          Text(d['description']?.toString() ?? 'No legacy description.'),
          for (var i = 1; i <= (d['evidence_count'] as int); i++)
            TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    DisputeEvidenceViewer(disputeId: widget.id, index: i),
              ),
              icon: const Icon(Icons.image),
              label: Text('View evidence $i'),
            ),
          if (d['decision'] != null) ...[
            Text('Decision: ${d['decision']}'),
            Text('Admin note: ${d['admin_note']}'),
            Text(
              'Administrator: ${d['admin_name'] ?? d['decided_by']} • ${d['decided_at']}',
            ),
          ],
          if (d['refund_pending'] == true)
            Text(
              '$refundInitiated Pending manual processing: PKR ${d['refund_amount']}. Money has not been returned.',
            ),
          if (controller.decisionMessage.value != null)
            Text(
              controller.decisionMessage.value!,
              style: const TextStyle(color: Colors.green),
            ),
          if (controller.decisionError.value != null)
            Text(
              controller.decisionError.value!,
              style: const TextStyle(color: Colors.red),
            ),
          if (eligible) ...[
            TextField(
              controller: note,
              enabled: !busy && !controller.decisionUncertain,
              maxLength: controller.noteMaximum,
              maxLines: 4,
              decoration: InputDecoration(
                labelText:
                    'Required admin note (${controller.noteMinimum}–${controller.noteMaximum} characters)',
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (controller.decisionUncertain) ...[
              const Text(
                'Confirmation is unavailable. Retry the unchanged decision; server state will be checked first.',
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => controller.submitDisputeDecision(
                        widget.id,
                        controller.pendingDecision!,
                        controller.pendingNote!,
                      ),
                child: const Text('Retry unchanged decision'),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : () => _decision('RESOLVED'),
                      child: const Text('Resolve'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => _decision('REJECTED'),
                      child: const Text('Reject'),
                    ),
                  ),
                ],
              ),
          ] else
            const Text('Read-only dispute. No further decision is allowed.'),
          TextButton(
            onPressed: busy
                ? null
                : () => controller.loadDisputeDetail(widget.id),
            child: const Text('Refresh server status'),
          ),
        ],
      );
    }),
  );
}
