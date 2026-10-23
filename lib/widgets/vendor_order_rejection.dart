import 'package:flutter/material.dart';

Future<void> confirmVendorOrderRejection(
  BuildContext context,
  Future<void> Function() reject,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Reject this order?'),
      content: const Text(
        'Rejecting cancels the entire customer order, including its other vendor portions. This cannot be undone. Refund eligibility is recorded separately; this does not confirm a cash refund.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Keep order'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Reject order'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) await reject();
}
