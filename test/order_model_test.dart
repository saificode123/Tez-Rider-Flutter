import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/order_model.dart';

void main() {
  test('admin order stream accepts actual bigint primary and foreign keys', () {
    final order = OrderModel.fromJson({
      'id': 1049,
      'user_id': 249,
      'vendor_id': 248,
      'rider_id': 15,
      'amount': 25,
      'order_status': 'on_the_way',
    });
    expect(
      [order.id, order.userId, order.vendorId, order.riderId],
      ['1049', '249', '248', '15'],
    );
    expect(order.amount, 25);
    expect(order.orderStatus, 'on_the_way');
  });

  test(
    'legacy string identifiers and nullable assignment remain compatible',
    () {
      final order = OrderModel.fromJson({
        'id': 'legacy-order',
        'user_id': 'legacy-customer',
        'amount': 25.5,
      });
      expect(order.id, 'legacy-order');
      expect(order.userId, 'legacy-customer');
      expect(order.riderId, isNull);
      expect(order.vendorId, isNull);
      expect(order.amount, 25.5);
    },
  );
}
