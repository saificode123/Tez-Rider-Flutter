import 'dart:async';
import 'package:flutter/material.dart';
import '../services/rider_performance_service.dart';

class RiderPerformancePanel extends StatefulWidget {
  const RiderPerformancePanel({super.key, this.service});
  final RiderPerformanceService? service;
  @override
  State<RiderPerformancePanel> createState() => _RiderPerformancePanelState();
}

class _RiderPerformancePanelState extends State<RiderPerformancePanel> {
  late final RiderPerformanceService _service;
  StreamSubscription<void>? _subscription;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _account, _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? RiderPerformanceService();
    _account = _service.account;
    _subscription = _service.accountChanges.listen((_) {
      if (mounted && _account != _service.account) {
        _account = _service.account;
        _generation++;
        setState(() {
          _data = null;
          _loading = false;
          _error = 'Account changed. Open performance again.';
        });
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      final data = await _service.load();
      if (mounted && generation == _generation) setState(() => _data = data);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Performance could not be loaded. Please retry.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Delivery performance',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh performance',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null) ...[
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ] else if (data != null) ...[
              Text(
                'Completed: ${data['completed_deliveries']} / ${data['accepted_assignments']} accepted assignments',
              ),
              Text(
                'Completion rate: ${data['completion_rate'] == null ? 'No accepted assignments' : '${data['completion_rate']}%'}',
              ),
              Text(
                'Average delivery time: ${data['average_duration_seconds'] == null ? 'Unavailable' : '${((data['average_duration_seconds'] as num) / 60).toStringAsFixed(1)} min'}',
              ),
              Text(
                'Timed deliveries: ${data['timed_deliveries']} (acceptance to completion)',
              ),
              Text(
                'Customer rating: ${data['average_rating'] == null ? 'No ratings yet' : '${data['average_rating']} / 5'} (${data['rating_count']})',
              ),
              if (data['legacy_assignments'] > 0 ||
                  data['unlinked_deliveries'] > 0)
                const Text(
                  'Historical timing or assignment records are incomplete. Unknown times are excluded.',
                ),
            ],
          ],
        ),
      ),
    );
  }
}
