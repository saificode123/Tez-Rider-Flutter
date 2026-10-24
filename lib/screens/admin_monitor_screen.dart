import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/admin_monitor_service.dart';
import '../services/order_detail_service.dart' show historyCents, historyMoney;
import '../widgets/role_access_gate.dart';
import '../widgets/tez_map_tiles.dart';
import 'admin_orders_screen.dart';

class AdminMonitorScreen extends StatelessWidget {
  const AdminMonitorScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      RoleAccessGate(role: 'admin', builder: (_) => const AdminMonitorPanel());
}

class AdminMonitorPanel extends StatefulWidget {
  const AdminMonitorPanel({super.key, this.service, this.events});
  final AdminMonitorService? service;
  final Stream<void>? events;
  @override
  State<AdminMonitorPanel> createState() => _AdminMonitorPanelState();
}

class _AdminMonitorPanelState extends State<AdminMonitorPanel> {
  late final AdminMonitorService _service;
  StreamSubscription<void>? _accountSubscription, _events;
  Timer? _refreshTimer, _periodic, _locationExpiry;
  final _orders = <Map<String, dynamic>>[];
  final _assignments = <int, ManualRiderAssignment>{};
  Map<String, dynamic>? _snapshot;
  bool _loading = false, _exporting = false, _dirty = false;
  bool _accountInvalidated = false;
  BuildContext? _assignmentDialog;
  int _generation = 0;
  int? _assigning;
  String? _status, _error, _account;
  DateTimeRange? _dates;
  DateTime? get _from => _dates == null
      ? null
      : DateTime(_dates!.start.year, _dates!.start.month, _dates!.start.day);
  DateTime? get _to => _dates == null
      ? null
      : DateTime(_dates!.end.year, _dates!.end.month, _dates!.end.day + 1);
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminMonitorService();
    _account = _service.account;
    _accountSubscription = _service.accountChanges.listen((_) {
      if (mounted && _account != _service.account) {
        _accountInvalidated = true;
        _closeAssignmentDialog();
        _generation++;
        _account = _service.account;
        _refreshTimer?.cancel();
        _periodic?.cancel();
        _locationExpiry?.cancel();
        unawaited(_events?.cancel());
        setState(() {
          _orders.clear();
          _snapshot = null;
          _assignments.clear();
          _loading = false;
          _error = 'Account changed. Open monitoring again.';
        });
      }
    });
    _events = (widget.events ?? _service.watch()).listen(
      (_) => _scheduleRefresh(),
      onError: (_) => _scheduleRefresh(),
    );
    _periodic = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _scheduleRefresh(),
    );
    unawaited(_load());
  }

  void _scheduleRefresh() {
    if (!mounted || _accountInvalidated || _refreshTimer != null) return;
    _refreshTimer = Timer(const Duration(seconds: 3), () {
      _refreshTimer = null;
      if (_loading) {
        _dirty = true;
      } else {
        unawaited(_load());
      }
    });
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || _accountInvalidated) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await _service.load(
        before: more && _orders.isNotEmpty ? _orders.last['order_id'] : null,
        status: _status,
        from: _from,
        to: _to,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) _orders.clear();
        final ids = _orders.map((r) => r['order_id']).toSet();
        _orders.addAll(
          (value['orders'] as List)
              .where((r) => ids.add(r['order_id']))
              .map((r) => Map<String, dynamic>.from(r)),
        );
        _snapshot = value;
      });
      _expireLocations();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = 'Monitoring could not be refreshed. Please retry.';
          _snapshot = null;
          _orders.clear();
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        if (_dirty) {
          _dirty = false;
          _scheduleRefresh();
        }
      }
    }
  }

  List<Map<String, dynamic>> get _pins {
    final now = DateTime.now().toUtc();
    return ((_snapshot?['rider_locations'] as List?) ?? [])
        .where((p) {
          final age = now.difference(DateTime.parse(p['observed_at']).toUtc());
          return !age.isNegative && age < const Duration(minutes: 2);
        })
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
  }

  void _expireLocations() {
    _locationExpiry?.cancel();
    final now = DateTime.now().toUtc();
    final deadlines =
        _pins
            .map(
              (p) => DateTime.parse(
                p['observed_at'],
              ).toUtc().add(const Duration(minutes: 2)),
            )
            .where((d) => d.isAfter(now))
            .toList()
          ..sort();
    if (deadlines.isNotEmpty) {
      _locationExpiry = Timer(deadlines.first.difference(now), () {
        if (mounted) {
          setState(() {});
          _expireLocations();
        }
      });
    }
  }

  Future<void> _export() async {
    if (_exporting || _accountInvalidated) return;
    final account = _service.account;
    setState(() => _exporting = true);
    try {
      final data = await _service.load(
        status: _status,
        from: _from,
        to: _to,
        export: true,
      );
      if (!mounted || account != _service.account) return;
      await Clipboard.setData(ClipboardData(text: monitorCsv(data)));
      if (mounted && account == _service.account) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Copied all ${data['summary']['total_orders']} filtered orders as CSV.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && account == _service.account) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Export was not confirmed. Retry or narrow the filter to 5000 orders.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _assign(int orderId) async {
    if (_assigning != null || _accountInvalidated) return;
    setState(() => _assigning = orderId);
    try {
      final candidates = await _service.candidates(orderId);
      if (!mounted || _accountInvalidated) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No fresh eligible Riders are available. Refresh after availability changes.',
            ),
          ),
        );
        return;
      }
      final submission = _assignments.putIfAbsent(
        orderId,
        () => ManualRiderAssignment(_service, orderId),
      );
      var selected =
          submission.selectedRider ?? candidates.first['rider_id'] as int;
      var busy = false;
      String? error;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: Text('Assign Rider to order #$orderId?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (dialogContext) {
                      _assignmentDialog = dialogContext;
                      return const SizedBox.shrink();
                    },
                  ),
                  const Text(
                    'This sends a pending request. The Rider must still accept and complete the checklist and OTP.',
                  ),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: candidates.any((r) => r['rider_id'] == selected)
                        ? selected
                        : null,
                    items: candidates
                        .map(
                          (r) => DropdownMenuItem<int>(
                            value: r['rider_id'],
                            child: Text(
                              '${r['name']} • ${((r['distance_m'] as num) / 1000).toStringAsFixed(1)} km',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy || submission.uncertain
                        ? null
                        : (value) {
                            if (value != null) update(() => selected = value);
                          },
                  ),
                  if (error != null) Text(error!),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialog),
                  child: Text(
                    submission.uncertain ? 'Close and check status' : 'Cancel',
                  ),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          update(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            final result = await submission.assign(selected);
                            if (!dialog.mounted) return;
                            if ([
                              'ASSIGNED',
                              'ALREADY_APPLIED',
                              'ORDER_CHANGED',
                              'RIDER_CHANGED',
                              'PICKUP_LOCATION_REQUIRED',
                            ].contains(result['code'])) {
                              Navigator.pop(dialog);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      [
                                            'ASSIGNED',
                                            'ALREADY_APPLIED',
                                          ].contains(result['code'])
                                          ? result['code'] == 'ASSIGNED'
                                                ? 'Assignment confirmed. Rider acceptance is pending.'
                                                : 'Original assignment receipt confirmed. Review the refreshed order status.'
                                          : 'Order or Rider availability changed. Review the refreshed status.',
                                    ),
                                  ),
                                );
                              }
                            } else {
                              update(
                                () => error =
                                    'Assignment is busy. Retry the same request.',
                              );
                            }
                          } catch (_) {
                            if (dialog.mounted) {
                              update(
                                () => error =
                                    'Result not confirmed. Retry uses the same assignment request.',
                              );
                            }
                          } finally {
                            if (dialog.mounted) update(() => busy = false);
                          }
                        },
                  child: Text(
                    submission.uncertain
                        ? 'Retry assignment'
                        : 'Confirm assignment',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Candidates unavailable or order changed. Refresh and retry.',
            ),
          ),
        );
      }
    } finally {
      _assignmentDialog = null;
      if (mounted) {
        setState(() => _assigning = null);
        unawaited(_load());
      }
    }
  }

  @override
  void dispose() {
    _closeAssignmentDialog();
    _generation++;
    _refreshTimer?.cancel();
    _periodic?.cancel();
    _locationExpiry?.cancel();
    unawaited(_accountSubscription?.cancel());
    unawaited(_events?.cancel());
    super.dispose();
  }

  void _closeAssignmentDialog() {
    final dialog = _assignmentDialog;
    _assignmentDialog = null;
    if (dialog == null || !dialog.mounted) return;
    final route = ModalRoute.of(dialog);
    final navigator = Navigator.of(dialog);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && route != null && route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _snapshot?['summary'] as Map?;
    final pins = _pins;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order monitoring'),
        actions: [
          IconButton(
            tooltip: 'Cash records',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminOrdersScreen(),
              ),
            ),
            icon: const Icon(Icons.receipt_long),
          ),
          IconButton(
            tooltip: 'Refresh monitoring',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _status ?? 'all',
                items:
                    [
                          'all',
                          'placed',
                          'pending',
                          'accepted',
                          'preparing',
                          'ready',
                          'on_the_way',
                          'delivered',
                          'cancelled',
                        ]
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(s == 'all' ? 'All statuses' : s),
                          ),
                        )
                        .toList(),
                onChanged: _loading || _exporting
                    ? null
                    : (s) {
                        setState(() => _status = s == 'all' ? null : s);
                        unawaited(_load());
                      },
              ),
              TextButton(
                onPressed: _loading || _exporting
                    ? null
                    : () async {
                        final chosen = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                          initialDateRange: _dates,
                        );
                        if (mounted && chosen != null) {
                          setState(() => _dates = chosen);
                          unawaited(_load());
                        }
                      },
                child: Text(
                  _dates == null
                      ? 'Filter dates'
                      : '${_dates!.start.toString().split(' ').first} – ${_dates!.end.toString().split(' ').first}',
                ),
              ),
              if (_dates != null)
                TextButton(
                  onPressed: _loading || _exporting
                      ? null
                      : () {
                          setState(() => _dates = null);
                          unawaited(_load());
                        },
                  child: const Text('Clear dates'),
                ),
              OutlinedButton.icon(
                onPressed: _exporting || _loading ? null : _export,
                icon: const Icon(Icons.copy),
                label: Text(_exporting ? 'Exporting…' : 'Copy CSV'),
              ),
            ],
          ),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: () => _load(), child: const Text('Retry')),
          ],
          if (summary != null) ...[
            Text(
              'Filtered orders: ${summary['total_orders']} • Active: ${summary['active_orders']} • Delivered: ${summary['delivered_orders']}',
            ),
            Text(
              'Delivered order value: ${historyMoney(historyCents(summary['delivered_value_cents']))}',
            ),
            const Text(
              'Gross order value; not platform profit or Rider earnings.',
            ),
            if (summary['unconfirmed_amounts'] > 0)
              Text('Amounts needing review: ${summary['unconfirmed_amounts']}'),
            Text('Fresh online Riders: ${summary['online_riders']}'),
            const SizedBox(height: 12),
            for (final entry in (summary['status_counts'] as Map).entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${entry.key}: ${entry.value}'),
                    LinearProgressIndicator(
                      value: summary['total_orders'] == 0
                          ? 0
                          : (entry.value as int) / summary['total_orders'],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (pins.isEmpty)
              const Text('No fresh online Rider locations to display.')
            else
              SizedBox(
                height: 260,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(
                      (pins.first['latitude'] as num).toDouble(),
                      (pins.first['longitude'] as num).toDouble(),
                    ),
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.tezrider.app',
                      tileProvider: tezMapTiles(),
                    ),
                    MarkerLayer(
                      markers: pins
                          .map(
                            (p) => Marker(
                              point: LatLng(
                                (p['latitude'] as num).toDouble(),
                                (p['longitude'] as num).toDouble(),
                              ),
                              child: Tooltip(
                                message: 'Rider #${p['rider_id']}',
                                child: const Icon(
                                  Icons.delivery_dining,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const Align(
                      alignment: Alignment.bottomRight,
                      child: TezMapAttribution(),
                    ),
                  ],
                ),
              ),
            if (_snapshot!['locations_truncated'] == true)
              const Text(
                'Map shows the first 200 fresh Riders; the total above includes all.',
              ),
            Text('Snapshot: ${_snapshot!['generated_at']}'),
            const Divider(),
            if (_orders.isEmpty) const Text('No orders match this filter.'),
            for (final row in _orders)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${row['order_id']} • ${row['status'] ?? 'unknown'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Order value: ${historyMoney(historyCents(row['amount_cents']))}',
                      ),
                      Text('Rider: ${row['rider_id'] ?? 'Unassigned'}'),
                      if (row['manual_assignment'] == true) ...[
                        if (row['status'] == 'ready' && row['rider_id'] == null)
                          TextButton(
                            onPressed: _assigning == null
                                ? () => _assign(row['order_id'])
                                : null,
                            child: const Text('Assign Rider'),
                          )
                        else
                          const Text(
                            'Manual assignment is waiting for ready stores.',
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            if (_snapshot!['has_more'] == true)
              TextButton(
                onPressed: _loading ? null : () => _load(more: true),
                child: const Text('Load more orders'),
              ),
          ],
        ],
      ),
    );
  }
}
