import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;

typedef CashReader = Future<dynamic> Function(int orderId);
typedef CashWriter = Future<dynamic> Function(Map<String, dynamic> parameters);

class PaymentSnapshot {
  PaymentSnapshot(
    this.orderId,
    this.orderStatus,
    this.method,
    this.state,
    this.amount,
    this.refunded,
    this.refunds,
    this.events,
  );
  final int orderId;
  final String orderStatus, method, state;
  final double? amount, refunded;
  final List<Map<String, dynamic>> refunds, events;
  bool get isCod => method.trim().toLowerCase() == 'cod';
  factory PaymentSnapshot.parse(dynamic value) {
    bool money(dynamic v) => v is num && v.isFinite && v >= 0;
    if (value is! Map ||
        value['code'] != 'OK' ||
        value['order_id'] is! int ||
        value['order_id'] <= 0 ||
        value['order_status'] is! String ||
        value['method'] is! String ||
        ![
          'UNPAID',
          'CASH_RECORDED',
          'LEGACY_SETTLED',
          'UNCONFIRMED',
        ].contains(value['state']) ||
        (value['amount'] != null && !money(value['amount'])) ||
        (value['refunded_amount'] != null &&
            !money(value['refunded_amount'])) ||
        value['refunds'] is! List ||
        value['events'] is! List) {
      throw const FormatException(
        'Payment status requires an authorized refresh or Admin review.',
      );
    }
    final refunds = (value['refunds'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    final events = (value['events'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    for (final row in refunds) {
      if (row['id'] is! int ||
          row['id'] <= 0 ||
          !['ORDER', 'DISPUTE'].contains(row['kind']) ||
          !['PENDING', 'RETRY_REQUIRED', 'CONFIRMED'].contains(row['state']) ||
          (row['amount'] != null && !money(row['amount']))) {
        throw const FormatException('Refund status was not confirmed.');
      }
    }
    for (final row in events) {
      if (row['id'] is! int ||
          row['id'] <= 0 ||
          ![
            'COLLECTED',
            'REFUND_CONFIRMED',
            'REFUND_FAILED',
          ].contains(row['event_kind']) ||
          !['admin', 'rider'].contains(row['actor_role']) ||
          (row['amount'] != null && !money(row['amount']))) {
        throw const FormatException('Cash receipt history was not confirmed.');
      }
    }
    return PaymentSnapshot(
      value['order_id'],
      value['order_status'],
      value['method'],
      value['state'],
      (value['amount'] as num?)?.toDouble(),
      (value['refunded_amount'] as num?)?.toDouble(),
      refunds,
      events,
    );
  }
}

class CashLedgerService {
  CashLedgerService({CashReader? reader, CashWriter? writer})
    : _reader =
          reader ??
          ((id) => Supabase.instance.client
              .rpc('final2_order_payment', params: {'p_order_id': id})
              .timeout(const Duration(seconds: 15))),
      writer =
          writer ??
          ((parameters) => Supabase.instance.client
              .rpc('final2_record_cash', params: parameters)
              .timeout(const Duration(seconds: 15)));
  final CashReader _reader;
  final CashWriter writer;
  Future<PaymentSnapshot> load(int orderId) async {
    final snapshot = PaymentSnapshot.parse(await _reader(orderId));
    if (snapshot.orderId != orderId) {
      throw const FormatException('Payment identity was not confirmed.');
    }
    return snapshot;
  }
}

/// Retries record acknowledgement only. This never sends or returns money.
class CashWriteFlow {
  CashWriteFlow(this.writer);
  final CashWriter writer;
  bool busy = false;
  Map<String, dynamic>? _pending;
  bool get uncertain => _pending != null;
  Future<Map<String, dynamic>> record(Map<String, dynamic> parameters) async {
    if (busy) throw StateError('A cash acknowledgement is already pending.');
    final payload = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(parameters)) as Map,
    );
    final amount = payload['p_amount'];
    final reference = payload['p_reference'];
    if (payload['p_order_id'] is! int ||
        payload['p_order_id'] <= 0 ||
        ![
          'COLLECTED',
          'REFUND_CONFIRMED',
          'REFUND_FAILED',
        ].contains(payload['p_event_kind']) ||
        amount is! num ||
        !amount.isFinite ||
        amount <= 0 ||
        amount > 1000000000000 ||
        (amount * 100 - (amount * 100).round()).abs() > .0001 ||
        payload['p_confirmed'] != true ||
        reference is! String ||
        reference.trim().runes.length < 5 ||
        reference.trim().runes.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(reference)) {
      throw const FormatException(
        'Confirm the exact amount and enter a one-line receipt reference.',
      );
    }
    payload['p_reference'] = reference.trim();
    final collecting = payload['p_event_kind'] == 'COLLECTED';
    if ((collecting &&
            (payload['p_refund_kind'] != null ||
                payload['p_refund_id'] != null)) ||
        (!collecting &&
            (!['ORDER', 'DISPUTE'].contains(payload['p_refund_kind']) ||
                payload['p_refund_id'] is! int ||
                payload['p_refund_id'] <= 0))) {
      throw const FormatException(
        'Refund acknowledgement must identify its approved action.',
      );
    }
    if (_pending != null &&
        jsonEncode(_pending!['payload']) != jsonEncode(payload)) {
      throw StateError(
        'The previous record is uncertain. Retry its unchanged receipt before editing.',
      );
    }
    _pending ??= {'id': blockRequestId(), 'payload': payload};
    busy = true;
    try {
      final value = await writer({...payload, 'p_request_id': _pending!['id']});
      if (value is! Map ||
          ![
            'RECORDED',
            'ALREADY_APPLIED',
            'ALREADY_COLLECTED',
            'ALREADY_REFUNDED',
            'ALREADY_SETTLED',
          ].contains(value['code']) ||
          value['event_kind'] != payload['p_event_kind'] ||
          value['amount'] is! num ||
          (['ALREADY_COLLECTED', 'ALREADY_SETTLED'].contains(value['code']) &&
              payload['p_event_kind'] != 'COLLECTED') ||
          (value['code'] == 'ALREADY_REFUNDED' &&
              payload['p_event_kind'] != 'REFUND_CONFIRMED') ||
          (value['amount'] as num).toDouble() != amount.toDouble() ||
          (value['code'] != 'ALREADY_SETTLED' &&
              (value['event_id'] is! int || value['event_id'] <= 0))) {
        throw const FormatException('Cash acknowledgement was not confirmed.');
      }
      _pending = null;
      return Map<String, dynamic>.from(value);
    } on PostgrestException catch (e) {
      if (['22023', '42501', 'PT409', 'PT422'].contains(e.code)) {
        _pending = null;
      }
      rethrow;
    } finally {
      busy = false;
    }
  }
}
