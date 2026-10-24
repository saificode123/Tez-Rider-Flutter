import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/order_detail_service.dart';
import '../../services/order_detail_watch.dart';
import '../../services/cash_ledger_service.dart';
import '../../widgets/order_timeline.dart';
import '../../widgets/order_payment_panel.dart';
import '../../widgets/invoice_button.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.service,
    this.watcher,
  });
  final int orderId;
  final OrderDetailService? service;
  final OrderDetailWatcher? watcher;
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final service = widget.service ?? OrderDetailService();
  OrderDetail? detail;
  String? error;
  DateTime? updated;
  int generation = 0;
  String? account;
  StreamSubscription<void>? authChanges;
  void Function()? stopWatching;
  @override
  void initState() {
    super.initState();
    account = service.account;
    authChanges = service.accountChanges.listen((_) {
      if (service.account != account) {
        account = service.account;
        load();
      }
    });
    stopWatching = (widget.watcher ?? watchOrderDetail)(widget.orderId, load);
    load();
  }

  Future<void> load() async {
    if (!mounted) return;
    final request = ++generation;
    setState(() {
      detail = null;
      error = null;
    });
    try {
      final result = await service.load(widget.orderId);
      if (mounted && request == generation) {
        setState(() {
          detail = result;
          updated = DateTime.now();
        });
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => error =
              'Order details could not be verified. Check your connection and account access, then retry.',
        );
      }
    }
  }

  @override
  void dispose() {
    ++generation;
    stopWatching?.call();
    unawaited(authChanges?.cancel());
    super.dispose();
  }

  String date(dynamic stamp) {
    final value = DateTime.tryParse(stamp?.toString() ?? '');
    return value == null
        ? 'Date unavailable'
        : DateFormat.yMMMd().add_jm().format(value.toLocal());
  }

  String status(dynamic raw) =>
      (raw?.toString() ?? 'unknown').replaceAll('_', ' ');
  Widget section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final current = detail;
    return Scaffold(
      appBar: AppBar(
        title: Text('Order #${widget.orderId} details'),
        actions: [
          IconButton(
            tooltip: 'Refresh order',
            onPressed: load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    TextButton(onPressed: load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : current == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  section('Order status', [
                    Text(
                      status(current.value['status']),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('Placed: ${date(current.value['created_at'])}'),
                    if (current.value['delivered_at'] != null)
                      Text('Delivered: ${date(current.value['delivered_at'])}'),
                    if (current.value['cancelled_at'] != null)
                      Text('Cancelled: ${date(current.value['cancelled_at'])}'),
                    if (updated != null)
                      Text('Updated: ${date(updated!.toIso8601String())}'),
                  ]),
                  section('Items', [
                    if (current.value['item_source'] == 'UNAVAILABLE')
                      const Text(
                        'Itemized records are unavailable for this older order.',
                      ),
                    if (current.value['item_source'] == 'RECORDED_ITEMS')
                      const Text(
                        'Recorded item amounts are shown. Product names reflect the current catalogue.',
                      ),
                    for (final vendorId
                        in current.items
                            .map((i) => i['vendor_id'])
                            .toSet()) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          current.items
                                  .firstWhere(
                                    (i) => i['vendor_id'] == vendorId,
                                  )['vendor']
                                  ?.toString() ??
                              'Vendor name unavailable',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final item in current.items.where(
                        (i) => i['vendor_id'] == vendorId,
                      ))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            item['product']?.toString() ??
                                'Product name unavailable',
                          ),
                          subtitle: Text(
                            '${item['quantity']} × ${historyMoney(historyCents(item['unit_cents']))}',
                          ),
                          trailing: Text(
                            historyMoney(historyCents(item['line_cents'])),
                          ),
                        ),
                    ],
                    const Divider(),
                    Text(
                      'Item subtotal: ${historyMoney(historyCents(current.totals['subtotal_cents']))}',
                    ),
                    Text(
                      'Delivery fee: ${historyMoney(historyCents(current.totals['delivery_cents']))}',
                    ),
                    Text(
                      'Order total: ${historyMoney(historyCents(current.totals['total_cents']))}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (current.totals['state'] == 'REVIEW_REQUIRED')
                      const Text(
                        'These amounts could not be reconciled. Ask an administrator to review the order records.',
                      ),
                  ]),
                  section('Order timeline', [
                    if (current.value['history_limited'] == true)
                      const Text(
                        'Earlier status history is unavailable. Only recorded events and dates are shown.',
                      ),
                    if (current.events.isEmpty)
                      const Text(
                        'No recorded lifecycle events for this older order.',
                      )
                    else
                      OrderTimeline(currentStep: 0, events: current.events),
                  ]),
                  if (current.portions.isNotEmpty)
                    section('Vendor progress', [
                      for (final portion in current.portions)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            portion['vendor']?.toString() ??
                                'Vendor name unavailable',
                          ),
                          subtitle: Text(
                            portion['status'] == 'on_the_way' &&
                                    current.value['status'] != 'on_the_way'
                                ? 'Pickup reserved'
                                : status(portion['status']),
                          ),
                          children: [
                            if ((portion['events'] as List).isEmpty)
                              const Text(
                                'Earlier Vendor status history is unavailable.',
                              )
                            else
                              OrderTimeline(
                                currentStep: 0,
                                events: List<Map<String, dynamic>>.from(
                                  portion['events'],
                                ),
                              ),
                          ],
                        ),
                    ]),
                  section('Payment & refunds', [
                    if (current.value['payment']['code'] == 'REVIEW_REQUIRED')
                      const Text(
                        'Payment records require administrator review.',
                      )
                    else
                      OrderPaymentPanel(
                        orderId: widget.orderId,
                        service: CashLedgerService(
                          reader: (_) async => current.value['payment'],
                        ),
                      ),
                    InvoiceButton(orderId: widget.orderId),
                  ]),
                ],
              ),
            ),
    );
  }
}
