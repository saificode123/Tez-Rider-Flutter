import 'package:get/get.dart';
import 'package:flutter/material.dart';

Future<void> confirmVendorOrderRejection(
  BuildContext context,
  Future<void> Function() reject,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text("Reject this order?".tr),
      content: Text(
        "Rejecting cancels the entire customer order, including its other vendor portions. This cannot be undone. Refund eligibility is recorded separately; this does not confirm a cash refund."
            .tr,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text("Keep order".tr),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text("Reject order".tr),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) await reject();
}
