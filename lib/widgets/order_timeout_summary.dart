import 'package:flutter/material.dart';
import 'order_timeline.dart';

class OrderTimeoutSummary extends StatelessWidget {
  const OrderTimeoutSummary({super.key, required this.order});
  final Map<String, dynamic> order;
  @override
  Widget build(BuildContext context) {
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
          const Text('Order cancelled — vendor unavailable.'),
        if (order['timeout_review_reason'] != null)
          const Text('This order needs review. Check its latest status.'),
        if (refunds.any((r) => r['status'] == 'PENDING'))
          const Text(
            'A refund action was recorded. Check payment status for any confirmed cash return.',
          ),
        if (events.isNotEmpty)
          ExpansionTile(
            title: const Text('Order timeline'),
            tilePadding: EdgeInsets.zero,
            children: [OrderTimeline(currentStep: 0, events: events)],
          ),
      ],
    );
  }
}
