import 'package:supabase_flutter/supabase_flutter.dart';

class RiderPerformanceService {
  RiderPerformanceService({
    Future<dynamic> Function()? read,
    String? Function()? identity,
    Stream<void>? accountChanges,
  }) : _read =
           read ??
           (() => Supabase.instance.client
               .rpc('final2_rider_performance')
               .timeout(const Duration(seconds: 15))),
       _identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id),
       accountChanges =
           accountChanges ??
           (identity != null
               ? const Stream<void>.empty()
               : Supabase.instance.client.auth.onAuthStateChange.map((_) {}));
  final Future<dynamic> Function() _read;
  final String? Function() _identity;
  final Stream<void> accountChanges;
  String? get account => _identity();
  Future<Map<String, dynamic>> load() async {
    final original = account;
    if (original == null) throw StateError('Sign in to view your performance.');
    final value = await _read();
    if (account != original) {
      throw StateError('Account changed. Open performance again.');
    }
    if (value is! Map ||
        value['code'] != 'OK' ||
        value['rider_id'] is! int ||
        value['rider_id'] <= 0) {
      throw const FormatException('Rider performance was not confirmed.');
    }
    for (final key in [
      'accepted_assignments',
      'completed_deliveries',
      'timed_deliveries',
      'rating_count',
      'legacy_assignments',
      'unlinked_deliveries',
    ]) {
      if (value[key] is! int || value[key] < 0) {
        throw const FormatException('Performance count was not confirmed.');
      }
    }
    bool bounded(dynamic number, double minimum, double maximum) =>
        number is num &&
        number.isFinite &&
        number >= minimum &&
        number <= maximum;
    if (value['completed_deliveries'] > value['accepted_assignments'] ||
        value['timed_deliveries'] > value['completed_deliveries'] ||
        (value['accepted_assignments'] == 0
            ? value['completion_rate'] != null
            : !bounded(value['completion_rate'], 0, 100)) ||
        (value['timed_deliveries'] == 0
            ? value['average_duration_seconds'] != null
            : !bounded(
                value['average_duration_seconds'],
                0,
                double.maxFinite,
              )) ||
        (value['rating_count'] == 0
            ? value['average_rating'] != null
            : !bounded(value['average_rating'], 1, 5)) ||
        value['fee_status'] != 'POLICY_REQUIRED' ||
        value['earned_fee_cents'] != null) {
      throw const FormatException('Performance values were not confirmed.');
    }
    return Map<String, dynamic>.from(value);
  }
}
