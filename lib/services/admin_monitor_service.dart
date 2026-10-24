import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;
import 'order_detail_service.dart' show historyCents;

typedef MonitorRpc = Future<dynamic> Function(String, Map<String, dynamic>);

class AdminMonitorService {
  AdminMonitorService({
    MonitorRpc? rpc,
    String? Function()? identity,
    Stream<void>? accountChanges,
  }) : _rpc =
           rpc ??
           ((name, params) => Supabase.instance.client
               .rpc(name, params: params)
               .timeout(const Duration(seconds: 15))),
       _identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id),
       accountChanges =
           accountChanges ??
           (identity != null
               ? const Stream<void>.empty()
               : Supabase.instance.client.auth.onAuthStateChange.map((_) {}));
  final MonitorRpc _rpc;
  final String? Function() _identity;
  final Stream<void> accountChanges;
  String? get account => _identity();
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> params,
  ) async {
    final original = account;
    if (original == null) throw StateError('Sign in as Administrator.');
    final value = await _rpc(name, params);
    if (account != original) {
      throw StateError('Account changed. Open monitoring again.');
    }
    if (value is! Map) {
      throw const FormatException('Monitoring response was not confirmed.');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>> load({
    int? before,
    String? status,
    DateTime? from,
    DateTime? to,
    bool export = false,
  }) async {
    final value = await call('final2_admin_order_monitor', {
      'p_before': before,
      'p_status': status,
      'p_from': from?.toUtc().toIso8601String(),
      'p_to': to?.toUtc().toIso8601String(),
      'p_limit': 30,
      'p_export': export,
    });
    final summary = value['summary'];
    if (value['code'] != 'OK' ||
        summary is! Map ||
        value['orders'] is! List ||
        value['rider_locations'] is! List ||
        value['has_more'] is! bool ||
        value['export_complete'] != export ||
        value['locations_truncated'] is! bool ||
        value['generated_at'] is! String ||
        DateTime.tryParse(value['generated_at']) == null) {
      throw const FormatException('Monitoring snapshot was not confirmed.');
    }
    for (final key in [
      'total_orders',
      'active_orders',
      'delivered_orders',
      'unconfirmed_amounts',
      'online_riders',
    ]) {
      if (summary[key] is! int || summary[key] < 0) {
        throw const FormatException('Monitoring counts were not confirmed.');
      }
    }
    if (summary['status_counts'] is! Map ||
        historyCents(summary['delivered_value_cents']) == null ||
        summary['active_orders'] > summary['total_orders'] ||
        summary['delivered_orders'] > summary['total_orders']) {
      throw const FormatException('Monitoring totals were not confirmed.');
    }
    var counted = 0;
    for (final count in (summary['status_counts'] as Map).values) {
      if (count is! int || count < 0) {
        throw const FormatException('Status counts were not confirmed.');
      }
      counted += count;
    }
    if (counted != summary['total_orders']) {
      throw const FormatException('Status totals do not reconcile.');
    }
    final ids = <int>{};
    for (final row in value['orders']) {
      if (row is! Map ||
          row['order_id'] is! int ||
          row['order_id'] <= 0 ||
          !ids.add(row['order_id']) ||
          row['manual_assignment'] is! bool ||
          (row['status'] != null && row['status'] is! String) ||
          (row['rider_id'] != null &&
              (row['rider_id'] is! int || row['rider_id'] <= 0))) {
        throw const FormatException('Monitoring order was not confirmed.');
      }
      historyCents(row['amount_cents']);
      if ((status != null && row['status'] != status) ||
          (!export && before != null && row['order_id'] >= before)) {
        throw const FormatException(
          'Filtered order response was not confirmed.',
        );
      }
      for (final key in ['created_at', 'delivered_at']) {
        if (row[key] != null &&
            (row[key] is! String || DateTime.tryParse(row[key]) == null)) {
          throw const FormatException('Order timestamp was not confirmed.');
        }
      }
      final created = row['created_at'] == null
          ? null
          : DateTime.parse(row['created_at']).toUtc();
      if ((from != null &&
              (created == null || created.isBefore(from.toUtc()))) ||
          (to != null && (created == null || !created.isBefore(to.toUtc())))) {
        throw const FormatException('Order date filter was not confirmed.');
      }
    }
    if ((value['orders'] as List).length > (export ? 5000 : 30) ||
        (export &&
            (value['orders'] as List).length != summary['total_orders'])) {
      throw const FormatException('Complete export was not confirmed.');
    }
    for (final pin in value['rider_locations']) {
      if (pin is! Map ||
          pin['rider_id'] is! int ||
          pin['rider_id'] <= 0 ||
          pin['available'] is! bool ||
          pin['latitude'] is! num ||
          !pin['latitude'].isFinite ||
          pin['latitude'] < -90 ||
          pin['latitude'] > 90 ||
          pin['longitude'] is! num ||
          !pin['longitude'].isFinite ||
          pin['longitude'] < -180 ||
          pin['longitude'] > 180 ||
          pin['observed_at'] is! String ||
          DateTime.tryParse(pin['observed_at']) == null) {
        throw const FormatException('Fresh Rider location was not confirmed.');
      }
    }
    return value;
  }

  Future<List<Map<String, dynamic>>> candidates(int orderId) async {
    final value = await call('final2_admin_assignment_candidates', {
      'p_order_id': orderId,
    });
    if (value['code'] != 'OK' ||
        value['order_id'] != orderId ||
        value['candidates'] is! List) {
      throw StateError(
        value['code'] == 'PICKUP_LOCATION_REQUIRED'
            ? 'A valid store pickup location is required.'
            : 'Order is no longer ready for manual assignment. Refresh its status.',
      );
    }
    final ids = <int>{};
    return (value['candidates'] as List).map((row) {
      if (row is! Map ||
          row['rider_id'] is! int ||
          row['rider_id'] <= 0 ||
          !ids.add(row['rider_id']) ||
          row['name'] is! String ||
          row['distance_m'] is! num ||
          !row['distance_m'].isFinite ||
          row['distance_m'] < 0) {
        throw const FormatException('Eligible Rider was not confirmed.');
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  Stream<void> watch() {
    RealtimeChannel? channel;
    late StreamController<void> events;
    events = StreamController<void>(
      onListen: () {
        channel = Supabase.instance.client
            .channel('final2-admin-monitor-${blockRequestId()}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'orders',
              callback: (_) => events.add(null),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'riders',
              callback: (_) => events.add(null),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'users',
              callback: (_) => events.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        if (channel != null) {
          await Supabase.instance.client.removeChannel(channel!);
        }
      },
    );
    return events.stream;
  }
}

class ManualRiderAssignment {
  ManualRiderAssignment(this.service, this.orderId);
  final AdminMonitorService service;
  final int orderId;
  Map<String, dynamic>? _pending;
  String? _account;
  bool busy = false;
  bool get uncertain => _pending != null;
  int? get selectedRider => _pending?['p_rider_id'];
  Future<Map<String, dynamic>> assign(int riderId) async {
    if (busy) throw StateError('Assignment is pending.');
    if (service.account == null) throw StateError('Sign in as Administrator.');
    _account ??= service.account;
    if (_account != service.account) {
      throw StateError('Account changed. Open assignments again.');
    }
    if (riderId <= 0) throw const FormatException('Choose an eligible Rider.');
    _pending ??= {
      'p_order_id': orderId,
      'p_rider_id': riderId,
      'p_request_id': blockRequestId(),
    };
    busy = true;
    try {
      final result = await service.call(
        'final2_admin_assign_rider',
        Map.of(_pending!),
      );
      if (result['order_id'] != orderId ||
          ![
            'ASSIGNED',
            'ALREADY_APPLIED',
            'ORDER_CHANGED',
            'RIDER_CHANGED',
            'PICKUP_LOCATION_REQUIRED',
            'RETRYABLE_CONFLICT',
          ].contains(result['code'])) {
        throw const FormatException('Assignment outcome was not confirmed.');
      }
      if (['ASSIGNED', 'ALREADY_APPLIED'].contains(result['code']) &&
          (result['rider_id'] != _pending!['p_rider_id'] ||
              result['assignment_id'] is! int ||
              result['assignment_id'] <= 0)) {
        throw const FormatException('Assigned Rider was not confirmed.');
      }
      if (result['code'] != 'RETRYABLE_CONFLICT') _pending = null;
      return result;
    } finally {
      busy = false;
    }
  }
}

String monitorCsv(Map<String, dynamic> snapshot) {
  if (snapshot['export_complete'] != true ||
      snapshot['orders'] is! List ||
      snapshot['summary'] is! Map ||
      (snapshot['orders'] as List).length !=
          snapshot['summary']['total_orders']) {
    throw const FormatException('Complete export required.');
  }
  String cell(dynamic input) {
    var value = input?.toString() ?? '';
    if (RegExp(r'^[=+@\-\t\r]').hasMatch(value)) value = "'$value";
    return '"${value.replaceAll('"', '""')}"';
  }

  final rows = <List<dynamic>>[
    [
      'order_id',
      'status',
      'created_at_UTC',
      'delivered_at_UTC',
      'rider_id',
      'gross_order_cents_PKR',
    ],
  ];
  for (final row in snapshot['orders']) {
    rows.add([
      row['order_id'],
      row['status'],
      row['created_at'],
      row['delivered_at'],
      row['rider_id'],
      row['amount_cents'],
    ]);
  }
  return rows.map((row) => row.map(cell).join(',')).join('\r\n');
}
