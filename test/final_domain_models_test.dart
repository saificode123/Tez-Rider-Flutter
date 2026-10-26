import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/chat_model.dart';
import 'package:flutter_application_1/models/order_model.dart';
import 'package:flutter_application_1/models/prescription_model.dart';
import 'package:flutter_application_1/models/product_model.dart';
import 'package:flutter_application_1/models/recommendation_model.dart';
import 'package:flutter_application_1/models/review_model.dart';
import 'package:flutter_application_1/models/user_model.dart';
import 'package:flutter_application_1/services/cart_persistence.dart';

void main() {
  test(
    'profile edits preserve verification and use masked CNIC projection',
    () {
      final user = UserModel.fromJson({
        'id': 27,
        'name': 'Rider',
        'email': 'rider@example.test',
        'phone': '03001234567',
        'role': 'rider',
        'verification_status': 'approved',
        'profile_image': 'tezphoto:profile',
        'cnic': '3520212345671',
        'cnic_masked': '3***2-*******-*',
        'cnic_image_url': 'private-document',
        'document_valid': true,
      });
      final edited = user.copyWith(name: 'Updated', phone: '03007654321');
      expect(edited.name, 'Updated');
      expect(edited.phone, '03007654321');
      expect(edited.id, '27');
      expect(edited.documentValid, isTrue);
      expect(edited.verificationStatus, 'approved');
      expect(edited.cnic, '3***2-*******-*');
      expect(edited.toJson().values, isNot(contains('3520212345671')));
      expect(user.name, 'Rider');
      final unchanged = user.copyWith();
      expect(unchanged.toJson(), user.toJson());
    },
  );

  test('missing profile fields grant no approval or valid document', () {
    final user = UserModel.fromJson({});
    expect(user.role, 'customer');
    expect(user.verificationStatus, 'pending');
    expect(user.documentValid, isFalse);
    expect(user.cnic, isNull);
    expect(user.email, isEmpty);
    expect(user.id, isEmpty);
  });

  test('profile copy explicitly replaces editable and moderation fields', () {
    final changed = UserModel.fromJson({}).copyWith(
      id: '42',
      name: 'Vendor',
      email: 'vendor@example.test',
      phone: '123',
      role: 'vendor',
      verificationStatus: 'rejected',
      profileImage: 'photo',
      cnic: 'masked',
      cnicImageUrl: 'private',
      rejectionReason: 'Unreadable',
    );
    expect(changed.toJson(), {
      'id': '42',
      'name': 'Vendor',
      'email': 'vendor@example.test',
      'phone': '123',
      'role': 'vendor',
      'verification_status': 'rejected',
      'profile_image': 'photo',
      'cnic': 'masked',
      'cnic_image_url': 'private',
      'rejection_reason': 'Unreadable',
    });
    expect(changed.documentValid, isFalse);
  });

  test('prescription review retains ownership and private image reference', () {
    final pending = PrescriptionModel.fromJson({
      'id': 12,
      'vendor_order_id': 31,
      'customer_id': 22,
      'prescription_image_url': 'tezphoto:prescription',
      'uploaded_at': '2026-10-26T10:00:00Z',
    });
    expect(pending.isPending, isTrue);
    final approved = pending.copyWith(
      status: 'approved',
      vendorNotes: 'Verified',
      reviewedAt: DateTime.utc(2026, 10, 26, 11),
      reviewedBy: '45',
    );
    final restored = PrescriptionModel.fromJson(approved.toJson());
    expect(restored.isApproved, isTrue);
    expect(restored.isPending, isFalse);
    expect(restored.isRejected, isFalse);
    expect(restored.customerId, '22');
    expect(restored.vendorOrderId, '31');
    expect(restored.prescriptionImageUrl, 'tezphoto:prescription');
    expect(restored.uploadedAt, pending.uploadedAt);
    expect(restored.reviewedAt, DateTime.utc(2026, 10, 26, 11));
    expect(restored.reviewedBy, '45');
    expect(restored.vendorNotes, 'Verified');
    expect(pending.copyWith().toJson(), pending.toJson());
    expect(pending.isPending, isTrue);
    expect(pending.copyWith(status: 'rejected').isRejected, isTrue);
  });

  test(
    'prescription replacement and unreviewed serialization stay explicit',
    () {
      final original = PrescriptionModel.fromJson({});
      expect(original.toJson()['reviewed_at'], isNull);
      final uploaded = original.copyWith(
        id: '1',
        vendorOrderId: '2',
        customerId: '3',
        prescriptionImageUrl: 'tezphoto:replacement',
        uploadedAt: DateTime.utc(2026),
      );
      expect(
        PrescriptionModel.fromJson(uploaded.toJson()).toJson(),
        uploaded.toJson(),
      );
      expect(uploaded.isApproved, isFalse);
    },
  );

  test(
    'order persistence retains assignment, COD amount and recipient details',
    () {
      final row = {
        'id': 81,
        'user_id': 9,
        'vendor_id': 15,
        'rider_id': 23,
        'amount': 1234.75,
        'fare': 80,
        'order_status': 'delivered',
        'payment_method': 'COD',
        'delivery_address': 'House 4',
        'is_gift': true,
        'recipient_name': 'Recipient',
        'recipient_phone': '03001234567',
        'gift_message': 'Thank you',
        'created_at': '2026-10-26T09:00:00Z',
      };
      final order = OrderModel.fromJson(row);
      final restored = OrderModel.fromJson(order.toJson());
      expect(restored.toJson(), order.toJson());
      expect(restored.amount, 1234.75);
      expect(restored.fare, 80.0);
      expect(restored.riderId, '23');
      expect(restored.recipientPhone, '03001234567');
      expect(order.createdAt, DateTime.utc(2026, 10, 26, 9));
      expect(OrderModel.fromJson({'created_at': 'corrupt'}).createdAt, isNull);
    },
  );

  test(
    'chat send payload excludes server identity, timestamp and read receipt',
    () {
      final message = ChatMessage.fromJson({
        'id': 8,
        'room_id': 4,
        'sender_id': 12,
        'image_url': 'tezphoto:chat',
        'is_read': true,
        'created_at': '2026-10-26T09:00:00Z',
      });
      expect(message.message, isEmpty);
      expect(message.isRead, isTrue);
      expect(message.createdAt.toUtc(), DateTime.utc(2026, 10, 26, 9));
      expect(message.toJson(), {
        'room_id': 4,
        'sender_id': 12,
        'message': '',
        'image_url': 'tezphoto:chat',
      });
      expect(
        () => ChatMessage.fromJson({
          'id': 8,
          'room_id': 4,
          'sender_id': 12,
          'created_at': 'corrupt',
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'review send payload preserves rating but excludes generated metadata',
    () {
      final review = ReviewModel.fromJson({
        'id': 'review',
        'order_id': 'order',
        'reviewer_id': 'customer',
        'reviewee_id': 'rider',
        'rating': 2,
        'comment': 'Late',
        'created_at': '2026-10-26T10:00:00Z',
      });
      expect(review.createdAt, DateTime.utc(2026, 10, 26, 10));
      expect(review.toJson(), {
        'order_id': 'order',
        'reviewer_id': 'customer',
        'reviewee_id': 'rider',
        'rating': 2,
        'comment': 'Late',
      });
      expect(ReviewModel.fromJson({'created_at': 'invalid'}).createdAt, isNull);
    },
  );

  test(
    'optional recommendation relation preserves numeric database identifiers',
    () {
      final relation = RecommendationModel.fromJson({
        'id': 4,
        'product_id': 9,
        'complementary_product_id': 12,
        'category_tag': 'Food',
        'priority': 3,
      });
      expect(relation.toJson(), {
        'id': '4',
        'product_id': '9',
        'complementary_product_id': '12',
        'category_tag': 'Food',
        'priority': 3,
      });
      expect(RecommendationModel.fromJson({}).priority, 1);
    },
  );

  test(
    'unconfirmed inventory never becomes purchasable through serialization',
    () {
      final product = ProductModel.fromJson({
        'id': 1,
        'vendor_id': 2,
        'stock_qty': 8,
        'price': '45.75',
        'image_url': '  photo  ',
      });
      expect(product.price, 45.75);
      expect(product.imageUrl, 'photo');
      expect(product.isPurchasable, isFalse);
      expect(ProductModel.fromJson(product.toJson()).isPurchasable, isFalse);
      expect(
        ProductModel.fromJson({'price': 'invalid', 'image_url': '  '}).price,
        0,
      );
    },
  );

  group('persisted cart trust boundary', () {
    Map<String, dynamic> cart(List<Map<String, dynamic>> items) => {
      'code': 'OK',
      'revision': 1,
      'items': items,
    };
    const item = {'product_id': 1, 'qty': 1, 'price': 25.5};
    test('rejects duplicate products, invalid counts and nonfinite prices', () {
      for (final items in [
        [item, item],
        [
          {...item, 'product_id': 0},
        ],
        [
          {...item, 'qty': 0},
        ],
        [
          {...item, 'qty': 101},
        ],
        [
          {...item, 'qty': 1.5},
        ],
        [
          {...item, 'price': double.nan},
        ],
        [
          {...item, 'price': double.infinity},
        ],
        [
          {...item, 'price': -1},
        ],
      ]) {
        expect(() => SavedCart.parse(cart(items)), throwsFormatException);
      }
    });
    test(
      'keeps authoritative conflict cart and rejects unconfirmed envelopes',
      () {
        final saved = SavedCart.parse({
          ...cart([item]),
          'code': 'CART_CHANGED',
        });
        expect(saved.code, 'CART_CHANGED');
        expect(saved.items.single['price'], 25.5);
        for (final response in [
          null,
          {...cart([]), 'revision': -1},
          {...cart([]), 'code': 'SUCCESS'},
          {...cart([]), 'items': null},
        ]) {
          expect(() => SavedCart.parse(response), throwsFormatException);
        }
      },
    );
  });
}
