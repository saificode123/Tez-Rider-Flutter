import 'package:flutter/foundation.dart';

/// TEST debug stage durations only. Never logs identities, geometry or errors.
void recordRouteMetric(String stage, num milliseconds) {
  if (kDebugMode &&
      const bool.fromEnvironment('FR21_ISOLATED_TEST') &&
      milliseconds.isFinite &&
      milliseconds >= 0 &&
      const {
        'route_rpc_fresh',
        'route_rpc_cached',
        'route_rpc_stale',
        'route_rpc_unavailable',
        'geometry_decode',
        'route_widget_frame',
      }.contains(stage)) {
    debugPrint('FR14_METRIC $stage ${milliseconds.toStringAsFixed(3)}');
  }
}
