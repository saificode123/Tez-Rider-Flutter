import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/stage2_ui_strings.dart';
import '../services/rider_earnings_service.dart';

class RiderEarningsPanel extends StatefulWidget {
  const RiderEarningsPanel({super.key, this.service, this.orderId});
  final RiderEarningsService? service;
  final int? orderId;
  @override
  State<RiderEarningsPanel> createState() => _RiderEarningsPanelState();
}

class _RiderEarningsPanelState extends State<RiderEarningsPanel> {
  late RiderEarningsService _service;
  StreamSubscription<void>? _subscription;
  String? _account;
  Map<String, dynamic>? _data;
  final _entries = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? RiderEarningsService();
    _account = _service.account;
    _subscription = _service.accountChanges.listen((_) {
      if (mounted && _account != _service.account) {
        _account = _service.account;
        ++_generation;
        setState(() {
          _entries.clear();
          _data = null;
          _loading = false;
          _error = 'Account changed. Open earnings again.';
        });
      }
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant RiderEarningsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _entries.clear();
      unawaited(_load());
    }
  }

  Future<void> _load({bool append = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) {
        _data = null;
        _entries.clear();
      }
    });
    try {
      final data = widget.orderId == null
          ? await _service.history(
              before: append ? (_data?['next_before'] as int?) : null,
            )
          : await _service.quote(widget.orderId!);
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        if (data['entries'] is List) {
          final ids = _entries.map((e) => e['id']).toSet();
          _entries.addAll(
            (data['entries'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .where((e) => ids.add(e['id'])),
          );
        }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Earnings could not be loaded. Please retry.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  String _money(dynamic amount) => 'PKR ${(amount as num).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final data = _data;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (widget.orderId == null
                            ? 'Earned delivery fees'
                            : 'Expected delivery earning')
                        .tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh'.tr,
                  onPressed: _loading ? null : () => _load(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text(
              'Earnings records only. This is not a payout confirmation.'.tr,
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(_error!.tr),
              TextButton(
                onPressed: _loading ? null : () => _load(),
                child: Text('Retry'.tr),
              ),
            ],
            if (data != null && widget.orderId != null) ...[
              Text(
                _money(data['expected_amount']),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '@slot0end base + @slot1end per km; minimum @slot2end'.uiTr({
                  'slot0end': _money(data['base_amount']),
                  'slot1end': _money(data['per_km_rate']),
                  'slot2end': _money(data['minimum_amount']),
                }),
              ),
              Text(
                '@slot0end km · @slot1end'.uiTr({
                  'slot0end': (data['distance_km'] as num).toStringAsFixed(2),
                  'slot1end':
                      (data['distance_method'] == 'route'
                              ? 'Road route'
                              : 'Straight-line estimate')
                          .tr,
                }),
              ),
              Text(
                (data['frozen'] == true
                        ? 'Distance frozen at delivery start.'
                        : 'Estimate; distance is frozen when delivery starts.')
                    .tr,
              ),
            ],
            if (data != null && widget.orderId == null) ...[
              Text(
                'Total: @slot0end'.uiTr({
                  'slot0end': _money(data['total_amount']),
                }),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if ((data['historical_unpriced_deliveries'] as int? ?? 0) > 0)
                Text(
                  'Older deliveries have no recorded earning; excluded from this total.'
                      .tr,
                ),
              if (_entries.isEmpty) Text('No earning records yet.'.tr),
              for (final entry in _entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #@slot0end · @slot1end'.uiTr({
                          'slot0end': '${entry['order_id']}',
                          'slot1end': _money(entry['amount']),
                        }),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        DateTime.parse(
                          entry['earned_at'],
                        ).toLocal().toString().split('.').first,
                      ),
                      Text(
                        '@slot0end km · @slot1end'.uiTr({
                          'slot0end': (entry['distance_km'] as num)
                              .toStringAsFixed(2),
                          'slot1end':
                              (entry['distance_method'] == 'route'
                                      ? 'Road route'
                                      : entry['distance_method'] ==
                                            'straight_line'
                                      ? 'Straight-line estimate'
                                      : 'Post-pickup cancellation')
                                  .tr,
                        }),
                      ),
                      Text(
                        '@slot0end base + @slot1end distance'.uiTr({
                          'slot0end': _money(entry['base_amount']),
                          'slot1end': _money(entry['distance_amount']),
                        }),
                      ),
                      if (entry['admin_review_required'] == true)
                        Text(
                          'Flagged for Admin review; no automatic deduction.'
                              .tr,
                        ),
                    ],
                  ),
                ),
              if (data['next_before'] != null)
                TextButton(
                  onPressed: _loading ? null : () => _load(append: true),
                  child: Text('Load more'.tr),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
