import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cash_ledger_service.dart';

typedef OrderDetailReader = Future<dynamic> Function(int orderId);

int? historyCents(dynamic value) {
  if (value == null) return null;
  if (value is! String || !RegExp(r'^[0-9]{1,15}$').hasMatch(value)) {
    throw const FormatException('Order amounts were not confirmed.');
  }
  final cents = int.parse(value);
  if (cents > 100000000000000) {
    throw const FormatException('Order amount exceeds supported bounds.');
  }
  return cents;
}

String historyMoney(int? cents) => cents == null
    ? 'Unavailable'
    : 'PKR ${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

class OrderDetail {
  OrderDetail._(this.value, this.items, this.portions, this.events);
  final Map<String, dynamic> value;
  final List<Map<String, dynamic>> items, portions, events;
  int get orderId => value['order_id'];
  Map<String, dynamic> get totals => Map<String, dynamic>.from(value['totals']);
  factory OrderDetail.parse(dynamic input, int orderId) {
    if (input is! Map ||
        input['code'] != 'OK' ||
        input['order_id'] != orderId ||
        orderId <= 0 ||
        input['status'] is! String ||
        input['status'].isEmpty ||
        input['history_limited'] is! bool ||
        ![
          'CHECKOUT_SNAPSHOT',
          'RECORDED_ITEMS',
          'UNAVAILABLE',
        ].contains(input['item_source']) ||
        input['items'] is! List ||
        input['vendor_orders'] is! List ||
        input['events'] is! List ||
        input['totals'] is! Map ||
        input['payment'] is! Map) {
      throw const FormatException('Owned order detail was not confirmed.');
    }
    for (final key in ['created_at', 'delivered_at', 'cancelled_at']) {
      final stamp = input[key];
      if (stamp != null &&
          (stamp is! String || DateTime.tryParse(stamp) == null)) {
        throw const FormatException('Order timestamp was not confirmed.');
      }
    }
    List<Map<String, dynamic>> rows(dynamic list) => (list as List).map((r) {
      if (r is! Map) {
        throw const FormatException('Order detail rows were not confirmed.');
      }
      return Map<String, dynamic>.from(r);
    }).toList();
    final items = rows(input['items']);
    if (items.length > 100 ||
        (input['item_source'] == 'UNAVAILABLE' && items.isNotEmpty)) {
      throw const FormatException('Item history was not confirmed.');
    }
    final seen = <int>{};
    var itemTotal = 0;
    for (final item in items) {
      final qty = item['quantity'];
      final unit = historyCents(item['unit_cents']);
      final line = historyCents(item['line_cents']);
      if (item['item_id'] is! int ||
          !seen.add(item['item_id']) ||
          item['vendor_id'] is! int ||
          item['vendor_id'] <= 0 ||
          qty is! int ||
          qty <= 0 ||
          qty > 2147483647 ||
          unit == null ||
          line == null ||
          unit > 100000000000000 ~/ qty ||
          qty * unit != line ||
          (item['product'] != null && item['product'] is! String) ||
          (item['vendor'] != null && item['vendor'] is! String)) {
        throw const FormatException(
          'Recorded item quantities and amounts were not confirmed.',
        );
      }
      if (line > 100000000000000 - itemTotal) {
        throw const FormatException('Item total exceeds supported bounds.');
      }
      itemTotal += line;
    }
    final totals = input['totals'] as Map;
    if (totals['currency'] != 'PKR' ||
        !['CONFIRMED', 'REVIEW_REQUIRED'].contains(totals['state'])) {
      throw const FormatException('Order total state was not confirmed.');
    }
    final subtotal = historyCents(totals['subtotal_cents']);
    final delivery = historyCents(totals['delivery_cents']);
    final total = historyCents(totals['total_cents']);
    if (totals['state'] == 'CONFIRMED' &&
        (items.isEmpty ||
            subtotal == null ||
            delivery == null ||
            total == null ||
            subtotal != itemTotal ||
            subtotal + delivery != total)) {
      throw const FormatException(
        'Order totals do not match the recorded items.',
      );
    }
    void validateEvents(List<Map<String, dynamic>> events) {
      final ids = <int>{};
      for (final event in events) {
        if (event['id'] is! int ||
            !ids.add(event['id']) ||
            event['status'] is! String ||
            event['status'].isEmpty ||
            event['created_at'] is! String ||
            DateTime.tryParse(event['created_at']) == null) {
          throw const FormatException(
            'Recorded order history was not confirmed.',
          );
        }
      }
    }

    final events = rows(input['events']);
    validateEvents(events);
    final portions = rows(input['vendor_orders']);
    final portionIds = <int>{};
    for (final portion in portions) {
      if (portion['id'] is! int ||
          !portionIds.add(portion['id']) ||
          portion['vendor_id'] is! int ||
          portion['vendor_id'] <= 0 ||
          portion['status'] is! String ||
          portion['events'] is! List) {
        throw const FormatException('Vendor order history was not confirmed.');
      }
      validateEvents(rows(portion['events']));
    }
    final payment = input['payment'] as Map;
    if (payment['code'] == 'OK') {
      final parsed = PaymentSnapshot.parse(payment);
      if (parsed.orderId != orderId || parsed.orderStatus != input['status']) {
        throw const FormatException(
          'Order payment identity was not confirmed.',
        );
      }
    } else if (payment['code'] != 'REVIEW_REQUIRED') {
      throw const FormatException('Order payment context was not confirmed.');
    }
    return OrderDetail._(
      Map<String, dynamic>.from(input),
      items,
      portions,
      events,
    );
  }
}

class OrderDetailService {
  OrderDetailService({
    OrderDetailReader? reader,
    String? Function()? identity,
    Stream<void>? accountChanges,
  }) : _reader =
           reader ??
           ((id) => Supabase.instance.client
               .rpc('final2_order_detail', params: {'p_order_id': id})
               .timeout(const Duration(seconds: 15))),
       _identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id),
       accountChanges =
           accountChanges ??
           (identity != null
               ? const Stream<void>.empty()
               : Supabase.instance.client.auth.onAuthStateChange.map((_) {}));
  final OrderDetailReader _reader;
  final String? Function() _identity;
  final Stream<void> accountChanges;
  String? get account => _identity();
  Future<OrderDetail> load(int orderId) async {
    final actor = account;
    if (actor == null) throw StateError('Sign in to view your order.');
    final value = await _reader(orderId);
    if (actor != account) {
      throw StateError('Account changed. Open your order again.');
    }
    return OrderDetail.parse(value, orderId);
  }
}
