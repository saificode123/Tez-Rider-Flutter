class OrderModel {
  final String id;
  final String userId;
  final String? vendorId;
  final String? riderId;
  final double amount;
  final double? fare;
  final String orderStatus;
  final String paymentMethod;
  final String? deliveryAddress;
  
  final bool isGift;
  final String? recipientName;
  final String? recipientPhone;
  final String? giftMessage;
  
  final DateTime? createdAt;

  OrderModel({
    required this.id,
    required this.userId,
    this.vendorId,
    this.riderId,
    required this.amount,
    this.fare,
    required this.orderStatus,
    required this.paymentMethod,
    this.deliveryAddress,
    this.isGift = false,
    this.recipientName,
    this.recipientPhone,
    this.giftMessage,
    this.createdAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      vendorId: json['vendor_id'],
      riderId: json['rider_id'],
      amount: (json['amount'] ?? 0).toDouble(),
      fare: json['fare'] != null ? (json['fare'] as num).toDouble() : null,
      orderStatus: json['order_status'] ?? 'placed',
      paymentMethod: json['payment_method'] ?? 'COD',
      deliveryAddress: json['delivery_address'],
      isGift: json['is_gift'] ?? false,
      recipientName: json['recipient_name'],
      recipientPhone: json['recipient_phone'],
      giftMessage: json['gift_message'],
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'vendor_id': vendorId,
      'rider_id': riderId,
      'amount': amount,
      'fare': fare,
      'order_status': orderStatus,
      'payment_method': paymentMethod,
      'delivery_address': deliveryAddress,
      'is_gift': isGift,
      'recipient_name': recipientName,
      'recipient_phone': recipientPhone,
      'gift_message': giftMessage,
    };
  }
}