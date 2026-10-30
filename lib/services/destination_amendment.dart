import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'delivery_otp_service.dart' show deliveryRequestId;

abstract class DestinationAmendmentBackend {
  String get account;
  Future<Map<String, dynamic>> context(int order);
  Future<Map<String, dynamic>> change(Map<String, dynamic> arguments);
}

class SupabaseDestinationAmendmentBackend
    implements DestinationAmendmentBackend {
  SupabaseClient get client => Supabase.instance.client;
  @override
  String get account => client.auth.currentUser?.id ?? '';
  @override
  Future<Map<String, dynamic>> context(int order) async =>
      Map<String, dynamic>.from(
        await client
            .rpc(
              'final_delivery_destination_context',
              params: {'p_order_id': order},
            )
            .timeout(const Duration(seconds: 15)),
      );
  @override
  Future<Map<String, dynamic>> change(Map<String, dynamic> arguments) async =>
      Map<String, dynamic>.from(
        await client
            .rpc('final_delivery_change_destination', params: arguments)
            .timeout(const Duration(seconds: 20)),
      );
}

String destinationAmendmentMessage(String code) => switch (code) {
  'OK' =>
    'Delivery location updated. Ask the Rider to review it before sharing again.',
  'RIDER_MUST_PAUSE' =>
    'Ask the Rider to go Offline and stop sharing before changing the destination.',
  'OTP_ACTIVE' =>
    'An active delivery code or pending email must finish or expire before changing the destination.',
  'HANDOVER_STARTED' =>
    'The destination cannot change after delivery proof, cash collection or verification has started.',
  'DESTINATION_CHANGED' =>
    'The destination changed elsewhere. Refresh and review it before trying again.',
  'WRONG_STATE' =>
    'Only an unfinished delivery with a confirmed destination can be changed.',
  'UNSUPPORTED_PAYMENT' =>
    'This change is available for unpaid Cash on Delivery orders only.',
  'NO_CHANGE' => 'Choose a different delivery point.',
  'FORBIDDEN' =>
    'Only this order’s signed-in Customer can change its destination.',
  'INVALID_DESTINATION' => 'Select and confirm a valid delivery point.',
  'REQUEST_CONFLICT' =>
    'This request could not be matched. Refresh the order before continuing.',
  _ => 'The destination change was not confirmed. Retry the same request.',
};

/// One immutable request across uncertain retries; account changes discard it.
class DestinationAmendmentFlow {
  DestinationAmendmentFlow(this.order, this.backend);
  final int order;
  final DestinationAmendmentBackend backend;
  Map<String, dynamic>? context;
  Map<String, dynamic>? _pending;
  String? _account;
  int _generation = 0;
  bool busy = false, uncertain = false, closed = false;
  String code = '';
  bool get canChange =>
      context?['code'] == 'OK' && context?['can_change'] == true;
  String get message => destinationAmendmentMessage(code);

  bool _same(String account, [int? generation]) =>
      !closed &&
      account.isNotEmpty &&
      backend.account == account &&
      (generation == null || generation == _generation);
  void accountChanged() {
    _generation++;
    context = null;
    _pending = null;
    uncertain = false;
    _account = null;
    code = 'FORBIDDEN';
  }

  Future<void> load() async {
    if (closed || busy) return;
    final owner = backend.account;
    if (_account != null && _account != owner) accountChanged();
    if (owner.isEmpty) {
      accountChanged();
      return;
    }
    _account = owner;
    final generation = _generation;
    busy = true;
    try {
      final result = await backend.context(order);
      if (!_same(owner, generation)) {
        accountChanged();
        return;
      }
      if (result['code'] != 'OK') {
        context = null;
        code = 'FORBIDDEN';
        return;
      }
      final revision = result['revision'];
      final lat = result['latitude'], lng = result['longitude'];
      if (result['order_id'] != order ||
          result['can_change'] is! bool ||
          (result['can_change'] == true &&
              (revision is! String ||
                  DateTime.tryParse(revision) == null ||
                  lat is! num ||
                  lng is! num ||
                  !lat.isFinite ||
                  !lng.isFinite ||
                  lat.abs() > 90 ||
                  lng.abs() > 180))) {
        throw const FormatException('Unconfirmed destination');
      }
      context = result;
      code = result['can_change'] == true
          ? ''
          : result['reason']?.toString() ?? 'WRONG_STATE';
    } catch (_) {
      if (_same(owner, generation)) {
        context = null;
        code = 'UNAVAILABLE';
      }
    } finally {
      busy = false;
    }
  }

  Future<void> submit(double lat, double lng, {required bool confirmed}) async {
    if (closed || busy || uncertain) return;
    if (!_same(_account ?? '')) {
      accountChanged();
      return;
    }
    if (!canChange ||
        !confirmed ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      code = 'INVALID_DESTINATION';
      return;
    }
    _pending = {
      'p_order_id': order,
      'p_request_id': deliveryRequestId(),
      'p_expected_revision': context!['revision'],
      'p_lat': lat,
      'p_lng': lng,
      'p_address':
          'Confirmed delivery pin: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      'p_confirmed': true,
    };
    await _send();
  }

  Future<void> retry() async {
    if (uncertain && !busy && !closed) await _send();
  }

  Future<void> _send() async {
    final owner = _account ?? '';
    final generation = _generation;
    if (!_same(owner) || _pending == null) {
      accountChanged();
      return;
    }
    busy = true;
    try {
      final result = await backend.change(Map<String, dynamic>.from(_pending!));
      if (!_same(owner, generation)) {
        accountChanged();
        return;
      }
      if (result['code'] is! String ||
          (result['code'] == 'OK' &&
              (result['order_id'] != order ||
                  result['revision'] is! String ||
                  DateTime.tryParse(result['revision']) == null))) {
        throw const FormatException('Unconfirmed destination change');
      }
      code = result['code'];
      uncertain = false;
      _pending = null;
      context = null;
    } catch (_) {
      if (_same(owner, generation)) {
        uncertain = true;
        code = 'UNAVAILABLE';
      }
    } finally {
      busy = false;
    }
  }

  void dispose() {
    closed = true;
    accountChanged();
  }
}
