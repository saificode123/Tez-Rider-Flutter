import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cash_ledger_service.dart';

Future<void> showOrderPayment(
  BuildContext context,
  int orderId, {
  bool allowCollection = false,
  bool allowRefund = false,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text('Order #$orderId payment'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: OrderPaymentPanel(
          orderId: orderId,
          allowCollection: allowCollection,
          allowRefund: allowRefund,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Close'),
      ),
    ],
  ),
);

class OrderPaymentPanel extends StatefulWidget {
  const OrderPaymentPanel({
    super.key,
    required this.orderId,
    this.allowCollection = false,
    this.allowRefund = false,
    this.service,
  });
  final int orderId;
  final bool allowCollection, allowRefund;
  final CashLedgerService? service;
  @override
  State<OrderPaymentPanel> createState() => _OrderPaymentPanelState();
}

class _OrderPaymentPanelState extends State<OrderPaymentPanel> {
  late CashLedgerService _service;
  PaymentSnapshot? _snapshot;
  bool _loading = true;
  String? _error;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CashLedgerService();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrderPaymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId ||
        oldWidget.service != widget.service) {
      _service = widget.service ?? CashLedgerService();
      _snapshot = null;
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _service.load(widget.orderId);
      if (mounted && request == _request) setState(() => _snapshot = snapshot);
    } catch (_) {
      if (mounted && request == _request) {
        setState(
          () => _error =
              'Payment status could not be verified. Retry or ask an administrator.',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _record(
    String kind,
    double amount, {
    Map<String, dynamic>? refund,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CashAcknowledgementDialog(
        orderId: widget.orderId,
        kind: kind,
        amount: amount,
        refund: refund,
        writer: _service.writer,
      ),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!),
          TextButton(
            onPressed: _load,
            child: const Text('Retry payment status'),
          ),
        ],
      );
    }
    final snapshot = _snapshot!;
    final status = switch (snapshot.state) {
      'CASH_RECORDED' => 'Cash collection recorded',
      'LEGACY_SETTLED' => 'Existing settled payment record',
      'UNPAID' => 'No cash collection is recorded',
      _ => 'Payment is unconfirmed; Admin review required',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${snapshot.method} · $status'),
        if (snapshot.amount != null)
          Text('Order amount: PKR ${snapshot.amount!.toStringAsFixed(2)}'),
        if (snapshot.refunded != null && snapshot.refunded! > 0)
          Text(
            'Confirmed manual return: PKR ${snapshot.refunded!.toStringAsFixed(2)}',
          ),
        const SizedBox(height: 8),
        const Text(
          'Cash acknowledgements are manual records. The app does not transfer money.',
        ),
        if (snapshot.isCod &&
            widget.allowCollection &&
            snapshot.amount != null &&
            snapshot.state == 'UNPAID' &&
            snapshot.orderStatus == 'delivered')
          TextButton(
            onPressed: () => _record('COLLECTED', snapshot.amount!),
            child: const Text('Record cash already received'),
          ),
        for (final refund in snapshot.refunds) ...[
          const Divider(),
          Text(switch (refund['state']) {
            'CONFIRMED' => 'Manual refund confirmed',
            'RETRY_REQUIRED' =>
              'Refund attempt unsuccessful; money return is not confirmed',
            _ => 'Refund pending; money return is not confirmed',
          }),
          if (refund['amount'] is num)
            Text(
              'Refund amount: PKR ${(refund['amount'] as num).toStringAsFixed(2)}',
            ),
          if (snapshot.isCod &&
              widget.allowRefund &&
              refund['state'] != 'CONFIRMED' &&
              refund['amount'] is num) ...[
            TextButton(
              onPressed: () => _record(
                'REFUND_CONFIRMED',
                (refund['amount'] as num).toDouble(),
                refund: refund,
              ),
              child: const Text('Record cash already returned'),
            ),
            TextButton(
              onPressed: () => _record(
                'REFUND_FAILED',
                (refund['amount'] as num).toDouble(),
                refund: refund,
              ),
              child: const Text('Record unsuccessful refund attempt'),
            ),
          ],
        ],
        for (final event in snapshot.events) ...[
          const Divider(),
          Text(
            '${switch (event['event_kind']) {
              'COLLECTED' => 'Cash receipt',
              'REFUND_CONFIRMED' => 'Cash return receipt',
              _ => 'Unsuccessful refund attempt',
            }} · recorded by ${event['actor_role']}',
          ),
          if (event['reference'] is String)
            Text('Reference: ${event['reference']}'),
          if (DateTime.tryParse(event['recorded_at']?.toString() ?? '')
              case final time?)
            Text(time.toLocal().toString()),
        ],
        TextButton(
          onPressed: _load,
          child: const Text('Refresh payment status'),
        ),
      ],
    );
  }
}

class CashAcknowledgementDialog extends StatefulWidget {
  const CashAcknowledgementDialog({
    super.key,
    required this.orderId,
    required this.kind,
    required this.amount,
    required this.writer,
    this.refund,
  });
  final int orderId;
  final String kind;
  final double amount;
  final CashWriter writer;
  final Map<String, dynamic>? refund;
  @override
  State<CashAcknowledgementDialog> createState() =>
      _CashAcknowledgementDialogState();
}

class _CashAcknowledgementDialogState extends State<CashAcknowledgementDialog> {
  final _reference = TextEditingController();
  late final CashWriteFlow _flow;
  bool _confirmed = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _flow = CashWriteFlow(widget.writer);
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _flow.record({
        'p_order_id': widget.orderId,
        'p_event_kind': widget.kind,
        'p_amount': widget.amount,
        'p_confirmed': _confirmed,
        'p_reference': _reference.text,
        'p_refund_kind': widget.refund?['kind'],
        'p_refund_id': widget.refund?['id'],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _flow.uncertain
              ? 'This record is uncertain. Do not repeat the cash transfer. Retry the unchanged receipt to check the server.'
              : e is PostgrestException && e.code == '42501'
              ? 'This account is not authorized for this cash record.'
              : 'The record was not accepted. Review the receipt or close and refresh the order.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final acknowledgement = switch (widget.kind) {
      'COLLECTED' =>
        'I confirm that the exact order cash was already received.',
      'REFUND_CONFIRMED' =>
        'I confirm that this exact cash amount was already returned.',
      _ =>
        'I confirm that this refund attempt was unsuccessful and no cash was returned.',
    };
    return AlertDialog(
      title: const Text('Record a manual cash acknowledgement'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Order #${widget.orderId} · PKR ${widget.amount.toStringAsFixed(2)}',
            ),
            const Text(
              'Record an action already performed. Do not repeat a cash transfer when retrying this record.',
            ),
            TextField(
              controller: _reference,
              enabled: !_busy && !_flow.uncertain,
              maxLength: 120,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Receipt or acknowledgement reference',
                helperText:
                    'Use a real reference. Omit CNIC, credentials and private URLs.',
                helperMaxLines: 3,
              ),
            ),
            CheckboxListTile(
              value: _confirmed,
              title: Text(acknowledgement),
              onChanged: _busy || _flow.uncertain
                  ? null
                  : (value) => setState(() => _confirmed = value == true),
            ),
            if (_error != null) Text(_error!),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _busy || !_confirmed || _reference.text.trim().runes.length < 5
              ? null
              : _submit,
          child: Text(
            _flow.uncertain
                ? 'Retry unchanged record'
                : 'Record acknowledgement',
          ),
        ),
      ],
    );
  }
}
