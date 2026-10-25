import 'package:get/get.dart';
import 'package:flutter_application_1/core/stage2_ui_strings.dart';
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
    Localizations.localeOf(context);
    final data = _data;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Delivery performance".tr,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: "Refresh performance".tr,
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null) ...[
              Text(_error!.tr),
              TextButton(onPressed: _load, child: Text("Retry".tr)),
            ] else if (data != null) ...[
              Text(
                "Completed: @slot0end / @slot1end accepted assignments".uiTr({
                  "slot0end": (data['completed_deliveries']).toString(),
                  "slot1end": (data['accepted_assignments']).toString(),
                }),
              ),
              Text(
                "Completion rate: @slot0end".uiTr({
                  "slot0end":
                      (data['completion_rate'] == null
                              ? 'No accepted assignments'
                              : '${data['completion_rate']}%')
                          .toString(),
                }),
              ),
              Text(
                "Average delivery time: @slot0end".uiTr({
                  "slot0end":
                      (data['average_duration_seconds'] == null
                              ? 'Unavailable'
                              : '${((data['average_duration_seconds'] as num) / 60).toStringAsFixed(1)} min')
                          .toString(),
                }),
              ),
              Text(
                "Timed deliveries: @slot0end (acceptance to completion)".uiTr({
                  "slot0end": (data['timed_deliveries']).toString(),
                }),
              ),
              Text(
                "Customer rating: @slot0end (@slot1end)".uiTr({
                  "slot0end":
                      (data['average_rating'] == null
                              ? 'No ratings yet'
                              : '${data['average_rating']} / 5')
                          .toString(),
                  "slot1end": (data['rating_count']).toString(),
                }),
              ),
              if (data['legacy_assignments'] > 0 ||
                  data['unlinked_deliveries'] > 0)
                Text(
                  "Historical timing or assignment records are incomplete. Unknown times are excluded."
                      .tr,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
