import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'order_timeline.dart';

class OrderTimeoutSummary extends StatelessWidget {
  const OrderTimeoutSummary({super.key, required this.order});
  final Map<String, dynamic> order;
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final events = List<Map<String, dynamic>>.from(
      order['order_timeline_events'] as List? ?? [],
    );
    final rawRefunds = order['order_refund_actions'];
    final refunds = rawRefunds is Map
        ? [rawRefunds]
        : rawRefunds as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (order['cancellation_reason'] == 'vendor_timeout')
          Text("Order cancelled — vendor unavailable.".tr),
        if (order['timeout_review_reason'] != null)
          Text("This order needs review. Check its latest status.".tr),
        if (refunds.any((r) => r['status'] == 'PENDING'))
          Text(
            "A refund action was recorded. Check payment status for any confirmed cash return."
                .tr,
          ),
        if (events.isNotEmpty)
          ExpansionTile(
            title: Text("Order timeline".tr),
            tilePadding: EdgeInsets.zero,
            children: [OrderTimeline(currentStep: 0, events: events)],
          ),
      ],
    );
  }
}
