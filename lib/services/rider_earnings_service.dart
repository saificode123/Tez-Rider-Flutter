import 'package:supabase_flutter/supabase_flutter.dart';

typedef EarningsRead = Future<dynamic> Function(String, Map<String, dynamic>);

class RiderEarningsService {
  RiderEarningsService({
    EarningsRead? read,
    String? Function()? identity,
    Stream<void>? accountChanges,
  }) : _read =
           read ??
           ((name, args) => Supabase.instance.client
               .rpc(name, params: args)
               .timeout(const Duration(seconds: 15))),
       _identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id),
       accountChanges =
           accountChanges ??
           (identity != null
               ? const Stream<void>.empty()
               : Supabase.instance.client.auth.onAuthStateChange.map((_) {}));

  final EarningsRead _read;
  final String? Function() _identity;
  final Stream<void> accountChanges;
  String? get account => _identity();

  Future<Map<String, dynamic>> _request(
    String name,
    Map<String, dynamic> args,
  ) async {
    final owner = account;
    if (owner == null) throw StateError('Sign in required');
    final value = await _read(name, args);
    if (account != owner) throw StateError('Account changed');
    if (value is! Map ||
        value['code'] != 'OK' ||
        value['rider_id'] is! int ||
        value['rider_id'] <= 0 ||
        value['earnings_only'] != true) {
      throw const FormatException('Earnings were not confirmed');
    }
    return Map<String, dynamic>.from(value);
  }

  static bool _amount(dynamic value) =>
      value is num && value.isFinite && value >= 0;

  Future<Map<String, dynamic>> quote(int order) async {
    if (order <= 0) throw const FormatException('Invalid order');
    final result = await _request('final_delivery_rider_quote', {
      'p_order_id': order,
    });
    if (result['order_id'] != order ||
        result['currency'] != 'PKR' ||
        result['frozen'] is! bool ||
        !['route', 'straight_line'].contains(result['distance_method']) ||
        ![
          'distance_km',
          'base_amount',
          'per_km_rate',
          'minimum_amount',
          'expected_amount',
        ].every((key) => _amount(result[key]))) {
      throw const FormatException('Expected earning was not confirmed');
    }
    return result;
  }

  Future<Map<String, dynamic>> history({int? before}) async {
    final result = await _request('final_delivery_rider_earnings', {
      'p_limit': 25,
      'p_before': before,
    });
    final entries = result['entries'];
    if (!_amount(result['total_amount']) ||
        result['record_count'] is! int ||
        result['record_count'] < 0 ||
        entries is! List ||
        entries.length > result['record_count'] ||
        entries.length > 25 ||
        (result['historical_unpriced_deliveries'] != null &&
            (result['historical_unpriced_deliveries'] is! int ||
                result['historical_unpriced_deliveries'] < 0)) ||
        (result['next_before'] != null &&
            (result['next_before'] is! int || result['next_before'] <= 0))) {
      throw const FormatException('Earnings history was not confirmed');
    }
    final ids = <int>{};
    for (final row in entries) {
      if (row is! Map ||
          row['id'] is! int ||
          row['id'] <= 0 ||
          !ids.add(row['id']) ||
          row['order_id'] is! int ||
          row['order_id'] <= 0 ||
          row['earned_at'] is! String ||
          DateTime.tryParse(row['earned_at']) == null ||
          ![
            'route',
            'straight_line',
            'not_applicable',
          ].contains(row['distance_method']) ||
          !['delivery', 'post_pickup_cancellation'].contains(row['kind']) ||
          row['admin_review_required'] is! bool ||
          ![
            'distance_km',
            'base_amount',
            'per_km_rate',
            'distance_amount',
            'amount',
          ].every((key) => _amount(row[key]))) {
        throw const FormatException('An earning record was not confirmed');
      }
    }
    return result;
  }
}
