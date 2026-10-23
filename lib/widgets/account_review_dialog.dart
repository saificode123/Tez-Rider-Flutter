import 'package:flutter/material.dart';

/// Owns its field until the dialog route is disposed, including exit animation.
class AccountReviewDialog extends StatefulWidget {
  const AccountReviewDialog({
    super.key,
    required this.approved,
    this.requireReason = false,
  });
  final bool approved, requireReason;
  @override
  State<AccountReviewDialog> createState() => _AccountReviewDialogState();
}

class _AccountReviewDialogState extends State<AccountReviewDialog> {
  final _reason = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.approved ? 'Approve this account?' : 'Reject this account?',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'The account status will change only after server confirmation.',
        ),
        if (widget.requireReason)
          TextField(
            controller: _reason,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Rejection reason',
              errorText: _error,
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (widget.requireReason &&
              (_reason.text.trim().isEmpty ||
                  _reason.text.runes.length > 500 ||
                  RegExp(r'[\x00-\x1f\x7f]').hasMatch(_reason.text))) {
            setState(
              () => _error =
                  'Enter a rejection reason (one line, up to 500 characters).',
            );
            return;
          }
          Navigator.pop(context, _reason.text.trim());
        },
        child: const Text('Confirm'),
      ),
    ],
  );
}
