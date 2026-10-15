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
        title: const Text('Send broadcast?'),
        content: Text(
          '${title.text.trim()}\nAudience: ${broadcastAudiences[controller.audience.value]}\nEstimated recipients: ${controller.estimate.value}\n\nThe server calculates the final count. This sends an in-app notification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm send'),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Broadcast notifications')),
    body: Obx(() {
      final locked =
          controller.sending.value || controller.uncertain.value || confirming;
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
                  decoration: const InputDecoration(
                    labelText: 'Broadcast title',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a title'
                      : null,
                ),
                TextFormField(
                  controller: message,
                  enabled: !locked,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Message'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a message'
                      : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: controller.audience.value,
                  decoration: const InputDecoration(labelText: 'Audience'),
                  items: broadcastAudiences.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: locked
                      ? null
                      : (value) => controller.refreshEstimate(value),
                ),
                const SizedBox(height: 12),
                if (controller.estimating.value)
                  const Text('Estimating recipients…')
                else if (controller.estimate.value != null)
                  Text(
                    'Estimated recipients: ${controller.estimate.value} (informational)',
                  ),
                if (controller.estimateError.value != null)
                  TextButton(
                    onPressed: controller.refreshEstimate,
                    child: Text(controller.estimateError.value!),
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
                        ? 'Sending…'
                        : controller.uncertain.value
                        ? 'Retry same broadcast'
                        : 'Review broadcast',
                  ),
                ),
                if (controller.feedback.value != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(controller.feedback.value!),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          const Text(
            'Broadcast history',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (controller.loading.value) const LinearProgressIndicator(),
          if (controller.historyError.value != null)
            TextButton(
              onPressed: controller.loadHistory,
              child: Text(controller.historyError.value!),
            )
          else if (!controller.loading.value && controller.history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No broadcasts yet'),
            ),
          ...controller.history.map(
            (row) => ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: Text(row['title'] as String),
              subtitle: Text(
                '${broadcastAudiences[row['audience']]} · ${row['recipient_count']} recipients\n${DateTime.tryParse(row['created_at'] as String)?.toLocal()} · ${row['status']}',
              ),
              isThreeLine: true,
            ),
          ),
          if (controller.hasMore.value)
            TextButton(
              onPressed: controller.loading.value
                  ? null
                  : () => controller.loadHistory(append: true),
              child: const Text('Load more broadcasts'),
            ),
        ],
      );
    }),
  );
}
