import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/order_payment_panel.dart';
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
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Obx(
      () => CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text("Dispute Resolution".tr),
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
                    decoration: InputDecoration(labelText: "Status filter".tr),
                    items: [
                      DropdownMenuItem(
                        value: 'ALL',
                        child: Text("All statuses".tr),
                      ),
                      ...controller.disputeStatuses.map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(disputeStatusLabel(s)),
                        ),
                      ),
                    ],
                    onChanged: (value) => controller.filterDisputes(
                      value == 'ALL' ? null : value,
                    ),
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
                    child: Text("Retry / refresh disputes".tr),
                  ),
                  if (controller.disputeLoading.value)
                    const LinearProgressIndicator(),
                  if (controller.disputes.isEmpty &&
                      !controller.disputeLoading.value &&
                      controller.disputeError.value == null)
                    Text("No disputes for this filter.".tr),
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
                      "Dispute #@slot0end • Order #@slot1end".uiTr({
                        "slot0end": (d['id']).toString(),
                        "slot1end": (d['order_id'] ?? 'Unavailable').toString(),
                      }),
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
                child: Text("Load more disputes".tr),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
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
              ? "Resolve this dispute?".tr
              : "Reject this dispute?".tr,
        ),
        content: Text(
          decision == 'RESOLVED'
              ? "Record the final decision and a pending refund action. Money will not be returned by this app.\n\n@slot0end"
                    .uiTr({"slot0end": (note.text.trim()).toString()})
              : "Record a final rejection and notify the customer. This decision cannot be changed.\n\n@slot0end"
                    .uiTr({"slot0end": (note.text.trim()).toString()}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel".tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Confirm decision".tr),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await controller.submitDisputeDecision(widget.id, decision, note.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Dispute #@slot0end".uiTr({"slot0end": (widget.id).toString()}),
        ),
      ),
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
                Text(
                  controller.decisionError.value ?? "Dispute unavailable.".tr,
                ),
                TextButton(
                  onPressed: () => controller.loadDisputeDetail(widget.id),
                  child: Text("Retry details".tr),
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
            Text(
              "Submitted: @slot0end".uiTr({
                "slot0end": (d['created_at']).toString(),
              }),
            ),
            Text(
              "Order #@slot0end • PKR @slot1end".uiTr({
                "slot0end": (d['order_id'] ?? 'Unavailable').toString(),
                "slot1end": (d['amount'] ?? 'Unavailable').toString(),
              }),
            ),
            Text(
              "Order: @slot0end • @slot1end".uiTr({
                "slot0end": (d['order_status'] ?? 'Unavailable').toString(),
                "slot1end": (d['payment_method'] ?? 'Unavailable').toString(),
              }),
            ),
            Text(
              "Customer: @slot0end (#@slot1end)".uiTr({
                "slot0end": (d['customer_name'] ?? 'Unavailable').toString(),
                "slot1end": (d['customer_id'] ?? 'Unavailable').toString(),
              }),
            ),
            if (d['customer_email'] != null)
              Text(d['customer_email'].toString()),
            for (final v in controller.disputeVendors)
              Text(
                "Vendor: @slot0end (#@slot1end)".uiTr({
                  "slot0end": (v['name']).toString(),
                  "slot1end": (v['id']).toString(),
                }),
              ),
            if (controller.disputeVendors.isEmpty)
              Text("Vendor: unavailable".tr),
            if (controller.moreDisputeVendors.value)
              TextButton(
                onPressed: controller.vendorsLoading.value
                    ? null
                    : () => controller.loadMoreDisputeVendors(widget.id),
                child: Text("Load more vendors".tr),
              ),
            Text(
              "Rider: @slot0end".uiTr({
                "slot0end": (d['rider_name'] ?? 'Not assigned').toString(),
              }),
            ),
            const SizedBox(height: 16),
            Text(d['reason'].toString()),
            Text(d['description']?.toString() ?? "No legacy description.".tr),
            for (var i = 1; i <= (d['evidence_count'] as int); i++)
              TextButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      DisputeEvidenceViewer(disputeId: widget.id, index: i),
                ),
                icon: const Icon(Icons.image),
                label: Text(
                  "View evidence @slot0end".uiTr({"slot0end": (i).toString()}),
                ),
              ),
            if (d['decision'] != null) ...[
              Text(
                "Decision: @slot0end".uiTr({
                  "slot0end": (d['decision']).toString(),
                }),
              ),
              Text(
                "Admin note: @slot0end".uiTr({
                  "slot0end": (d['admin_note']).toString(),
                }),
              ),
              Text(
                "Administrator: @slot0end • @slot1end".uiTr({
                  "slot0end": (d['admin_name'] ?? d['decided_by']).toString(),
                  "slot1end": (d['decided_at']).toString(),
                }),
              ),
            ],
            if (d['refund_pending'] == true)
              Text(
                "Refund eligibility recorded: PKR @slot0end. Check the current cash/refund status below."
                    .uiTr({"slot0end": (d['refund_amount']).toString()}),
              ),
            if (d['order_id'] is int)
              OrderPaymentPanel(
                key: ValueKey(
                  'payment-${d['order_id']}-${d['decision']}-${d['refund_pending']}',
                ),
                orderId: d['order_id'] as int,
                allowCollection: true,
                allowRefund: true,
              ),
            if (controller.decisionMessage.value != null)
              Text(
                d['refund_pending'] == true
                    ? "Decision recorded. Current settlement status is shown above."
                          .tr
                    : controller.decisionMessage.value!,
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
                      "Required admin note (@slot0end–@slot1end characters)"
                          .uiTr({
                            "slot0end": (controller.noteMinimum).toString(),
                            "slot1end": (controller.noteMaximum).toString(),
                          }),
                ),
              ),
              if (busy) const LinearProgressIndicator(),
              if (controller.decisionUncertain) ...[
                Text(
                  "Confirmation is unavailable. Retry the unchanged decision; server state will be checked first."
                      .tr,
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => controller.submitDisputeDecision(
                          widget.id,
                          controller.pendingDecision!,
                          controller.pendingNote!,
                        ),
                  child: Text("Retry unchanged decision".tr),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : () => _decision('RESOLVED'),
                        child: Text("Resolve".tr),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : () => _decision('REJECTED'),
                        child: Text("Reject".tr),
                      ),
                    ),
                  ],
                ),
            ] else
              Text("Read-only dispute. No further decision is allowed.".tr),
            TextButton(
              onPressed: busy
                  ? null
                  : () => controller.loadDisputeDetail(widget.id),
              child: Text("Refresh server status".tr),
            ),
          ],
        );
      }),
    );
  }
}
