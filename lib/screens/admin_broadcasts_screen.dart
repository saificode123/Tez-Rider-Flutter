import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/admin_broadcast_controller.dart';
import '../services/admin_broadcast_service.dart';

class AdminBroadcastsScreen extends StatefulWidget {
  const AdminBroadcastsScreen({super.key, this.controller});
  final AdminBroadcastController? controller;
  @override
  State<AdminBroadcastsScreen> createState() => _AdminBroadcastsScreenState();
}

class _AdminBroadcastsScreenState extends State<AdminBroadcastsScreen> {
  late final controller = widget.controller ?? AdminBroadcastController();
  final title = TextEditingController(), message = TextEditingController();
  final form = GlobalKey<FormState>();
  bool confirming = false;
  @override
  void initState() {
    super.initState();
    unawaited(controller.refreshEstimate());
    unawaited(controller.loadHistory());
  }

  @override
  void dispose() {
    title.dispose();
    message.dispose();
    if (widget.controller == null) controller.onClose();
    super.dispose();
  }

  Future<void> confirm() async {
    if (confirming ||
        controller.sending.value ||
        controller.estimate.value == null ||
        !form.currentState!.validate()) {
      return;
    }
    setState(() => confirming = true);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Send broadcast?".tr),
        content: Text(
          "@slot0end\nAudience: @slot1end\nEstimated recipients: @slot2end\n\nThe server calculates the final count. This sends an in-app notification."
              .uiTr({
                "slot0end": (title.text.trim()).toString(),
                "slot1end":
                    (broadcastAudiences[controller.audience.value] ??
                            controller.audience.value)
                        .tr,
                "slot2end": (controller.estimate.value).toString(),
              }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel".tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Confirm send".tr),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => confirming = false);
    if (approved != true) return;
    final sent = await controller.send(title.text, message.text);
    if (mounted && sent) {
      title.clear();
      message.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      appBar: AppBar(title: Text("Broadcast notifications".tr)),
      body: Obx(() {
        final locked =
            controller.sending.value ||
            controller.uncertain.value ||
            confirming;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: title,
                    enabled: !locked,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: "Broadcast title".tr,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a title'.tr
                        : null,
                  ),
                  TextFormField(
                    controller: message,
                    enabled: !locked,
                    maxLength: 1000,
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(labelText: "Message".tr),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a message'.tr
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: controller.audience.value,
                    decoration: InputDecoration(labelText: "Audience".tr),
                    items: broadcastAudiences.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value.tr),
                          ),
                        )
                        .toList(),
                    onChanged: locked
                        ? null
                        : (value) => controller.refreshEstimate(value),
                  ),
                  const SizedBox(height: 12),
                  if (controller.estimating.value)
                    Text("Estimating recipients…".tr)
                  else if (controller.estimate.value != null)
                    Text(
                      "Estimated recipients: @slot0end (informational)".uiTr({
                        "slot0end": (controller.estimate.value).toString(),
                      }),
                    ),
                  if (controller.estimateError.value != null)
                    TextButton(
                      onPressed: controller.refreshEstimate,
                      child: Text(controller.estimateError.value!.uiMessage),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        controller.sending.value ||
                            confirming ||
                            controller.estimate.value == null
                        ? null
                        : confirm,
                    child: Text(
                      controller.sending.value
                          ? "Sending…".tr
                          : controller.uncertain.value
                          ? "Retry same broadcast".tr
                          : "Review broadcast".tr,
                    ),
                  ),
                  if (controller.feedback.value != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(controller.feedback.value!.uiMessage),
                    ),
                ],
              ),
            ),
            const Divider(height: 32),
            Text(
              "Broadcast history".tr,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (controller.loading.value) const LinearProgressIndicator(),
            if (controller.historyError.value != null)
              TextButton(
                onPressed: controller.loadHistory,
                child: Text(controller.historyError.value!.uiMessage),
              )
            else if (!controller.loading.value && controller.history.isEmpty)
              Padding(
                padding: EdgeInsets.all(16),
                child: Text("No broadcasts yet".tr),
              ),
            ...controller.history.map(
              (row) => ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text(row['title'] as String),
                subtitle: Text(
                  "@slot0end · @slot1end recipients\n@slot2end · @slot3end"
                      .uiTr({
                        "slot0end":
                            (broadcastAudiences[row['audience']] ??
                                    row['audience']?.toString() ??
                                    'Unknown audience')
                                .tr,
                        "slot1end": (row['recipient_count']).toString(),
                        "slot2end": (DateTime.tryParse(
                          row['created_at'] as String,
                        )?.toLocal()).toString(),
                        "slot3end": (row['status']).toString(),
                      }),
                ),
                isThreeLine: true,
              ),
            ),
            if (controller.hasMore.value)
              TextButton(
                onPressed: controller.loading.value
                    ? null
                    : () => controller.loadHistory(append: true),
                child: Text("Load more broadcasts".tr),
              ),
          ],
        );
      }),
    );
  }
}
