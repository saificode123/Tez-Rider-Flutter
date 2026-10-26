import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/post_pickup_cancellation.dart';

class PostPickupCancellationCard extends StatefulWidget {
  const PostPickupCancellationCard({
    super.key,
    required this.orderId,
    this.service,
    this.onChanged,
  });
  final int orderId;
  final PostPickupCancellation? service;
  final VoidCallback? onChanged;
  @override
  State<PostPickupCancellationCard> createState() =>
      _PostPickupCancellationCardState();
}

class _PostPickupCancellationCardState
    extends State<PostPickupCancellationCard> {
  late final _service = widget.service ?? PostPickupCancellation();
  final _reason = TextEditingController();
  StreamSubscription<void>? _subscription;
  bool _busy = false, _changedAccount = false;
  String? _message;
  String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = _service.account;
    _subscription = _service.accountChanges.listen((_) {
      if (mounted && _owner != _service.account)
        setState(() {
          _changedAccount = true;
          _reason.clear();
          _message = null;
        });
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_busy || _changedAccount) return;
    final reason = _service.pendingReason ?? _reason.text.trim();
    if (reason.runes.length < 5 ||
        reason.runes.length > 300 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(reason)) {
      setState(() => _message = 'A reason of 5 to 300 characters is required.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel the whole order?'.tr),
        content: Text(
          'This cancels all vendor portions. If eligible, the Rider receives only the recorded base earning. Collected cash requires Admin review.'
              .tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep order'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirm cancellation'.tr),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _changedAccount) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final code = await _service.cancel(widget.orderId, reason);
      if (!mounted || _changedAccount) return;
      setState(
        () => _message = switch (code) {
          'CANCELLED' || 'ALREADY_CANCELLED' => 'Order cancellation confirmed.',
          'PICKUP_REQUIRED' =>
            'This order is not eligible for post-pickup cancellation.',
          'PAYMENT_REVIEW_REQUIRED' =>
            'Cash or payment records require Admin review before cancellation.',
          _ => 'Cancellation was not confirmed. Retry the same request.',
        },
      );
      if (code == 'CANCELLED' || code == 'ALREADY_CANCELLED')
        widget.onChanged?.call();
    } catch (_) {
      if (mounted && !_changedAccount)
        setState(
          () => _message =
              'Cancellation was not confirmed. Retry the same request.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    if (_changedAccount) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Post-pickup cancellation'.tr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextField(
              controller: _reason,
              enabled: !_busy && !_service.pending,
              maxLength: 300,
              decoration: InputDecoration(labelText: 'Cancellation reason'.tr),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null) Text(_message!.tr),
            TextButton.icon(
              onPressed: _busy ? null : _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: Text(
                (_service.pending ? 'Retry cancellation' : 'Cancel order').tr,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
