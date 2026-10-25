import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/pre_delivery_checklist_service.dart';

class PreDeliveryChecklistCard extends StatelessWidget {
  const PreDeliveryChecklistCard({
    super.key,
    required this.flow,
    required this.onAccept,
    required this.onStart,
  });
  final PreDeliveryChecklistFlow flow;
  final VoidCallback onAccept;
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Pickup checklist".tr,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          if (flow.busy.value) const LinearProgressIndicator(),
          if (flow.error.value != null) ...[
            Text(flow.error.value!.tr, key: const Key('checklist-error')),
            TextButton(
              onPressed: flow.busy.value ? null : flow.refresh,
              child: Text("Retry checklist".tr),
            ),
          ],
          if (flow.completed.value)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                "Checklist completed".tr,
                key: Key('checklist-completed'),
              ),
            )
          else
            for (final item in flow.items)
              CheckboxListTile(
                key: ValueKey('checklist-${item['id']}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text((item['label'] as String).tr),
                value: flow.selected.contains(item['id']),
                onChanged: flow.busy.value
                    ? null
                    : (value) =>
                          flow.choose(item['id'] as String, value == true),
              ),
          if (flow.loaded.value && flow.orderStatus.value != 'ready')
            Text("Waiting for every vendor to be ready for pickup.".tr),
          if (flow.assignmentStatus.value == 'Pending' &&
              flow.orderStatus.value == 'ready')
            FilledButton(
              onPressed: flow.busy.value ? null : onAccept,
              child: Text("Accept pickup".tr),
            ),
          if (!flow.completed.value)
            FilledButton(
              key: const Key('checklist-submit'),
              onPressed: flow.canSubmit ? flow.submit : null,
              child: Text(
                flow.busy.value ? "Confirming…".tr : "Submit checklist".tr,
              ),
            ),
          FilledButton(
            key: const Key('checklist-start'),
            onPressed: flow.canStart ? onStart : null,
            child: Text("Start Delivery".tr),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
