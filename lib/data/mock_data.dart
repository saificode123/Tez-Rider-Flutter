import '../models/product_model.dart';
import '../models/user_model.dart';
import '../models/chat_model.dart';

class MockData {
  // ─── PRODUCTS ────────────────────────────────────────────────────────────
  // Realistic products with category-matched Unsplash images.
  static List<ProductModel> get products => [
    // ── Food ──
    ProductModel(
      id: 'mock_f1', vendorId: 'mock_v1',
      name: 'Chicken Biryani',
      description: 'Fragrant basmati rice layered with tender chicken pieces, saffron, and aromatic whole spices. Served with cooling raita and fresh salad.',
      price: 350, category: 'Food',
      imageUrl: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_f2', vendorId: 'mock_v1',
      name: 'Zinger Burger',
      description: 'Crispy fried chicken patty, fresh lettuce, tomato, and creamy zinger sauce in a perfectly toasted sesame bun.',
      price: 450, category: 'Food',
      imageUrl: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_f3', vendorId: 'mock_v1',
      name: 'Tikka Pizza',
      description: 'Desi fusion pizza loaded with marinated chicken tikka, stretchy mozzarella, and tangy tomato sauce on a crispy thin crust.',
      price: 850, category: 'Food',
      imageUrl: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_f4', vendorId: 'mock_v1',
      name: 'Cold Coffee',
      description: 'Chilled blended coffee with a generous scoop of vanilla ice cream and fresh cream. The perfect summer refreshment.',
      price: 250, category: 'Food',
      imageUrl: 'https://images.unsplash.com/photo-1517701550927-30cf4ba1dba5?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_f5', vendorId: 'mock_v1',
      name: 'Mango Shake',
      description: 'Thick and creamy mango shake made with fresh Sindhri mangoes. A seasonal Pakistani favourite — available May to August.',
      price: 200, category: 'Food',
      imageUrl: 'https://images.unsplash.com/photo-1546173159-315724a31696?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_f6', vendorId: 'mock_v1',
      name: 'Mutton Karahi',
      description: 'Slow-cooked tender mutton in a rich, spicy tomato-based gravy with ginger and fresh green chillies. Served with naan.',
      price: 1200, category: 'Food',
      imageUrl: 'https://images.unsplash.com/photo-1574484284002-952d92456975?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_f7', vendorId: 'mock_v1',
      name: 'Chicken Shawarma',
      description: 'Marinated grilled chicken strips wrapped in a soft pita with garlic sauce, pickles, and fresh vegetables.',
      price: 280, category: 'Food',
      imageUrl: 'https://images.unsplash.com/photo-1599487488170-d11ec9c172f0?w=500&fit=crop',
    ),
    // ── Grocery ──
    ProductModel(
      id: 'mock_g1', vendorId: 'mock_v5',
      name: 'Fresh Vegetables Basket',
      description: 'Assorted seasonal vegetables — tomatoes, potatoes, onions, carrots, and leafy greens. Farm-fresh and pesticide-free.',
      price: 250, category: 'Grocery',
      imageUrl: 'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_g2', vendorId: 'mock_v5',
      name: 'Mixed Fruit Basket',
      description: 'Seasonal fruits including apples, bananas, grapes, oranges, and pears. Fresh from local farms daily.',
      price: 350, category: 'Grocery',
      imageUrl: 'https://images.unsplash.com/photo-1610832958506-aa56368176cf?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_g3', vendorId: 'mock_v5',
      name: 'Milk — 1 Litre',
      description: 'Fresh full-cream farm milk, pasteurised and hygienically packed. Rich in protein and calcium.',
      price: 120, category: 'Grocery',
      imageUrl: 'https://images.unsplash.com/photo-1563636619-e9143da7973b?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_g4', vendorId: 'mock_v5',
      name: 'Whole Wheat Bread',
      description: 'Freshly baked artisan whole wheat bread, soft inside with a light crust. No preservatives.',
      price: 80, category: 'Grocery',
      imageUrl: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=500&fit=crop',
    ),
    // ── Pharmacy ──
    ProductModel(
      id: 'mock_m1', vendorId: 'mock_v2',
      name: 'Panadol 500mg — 10 Tabs',
      description: 'Trusted paracetamol tablets for effective pain relief and fever reduction. Suitable for adults and children over 12.',
      price: 50, category: 'Pharmacy',
      imageUrl: 'https://images.unsplash.com/photo-1584308666744-24d5c474f2ae?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_m2', vendorId: 'mock_v2',
      name: 'Cough Syrup — 100ml',
      description: 'Non-drowsy cough syrup that soothes sore throats and suppresses persistent coughs. Honey and lemon flavour.',
      price: 120, category: 'Pharmacy',
      imageUrl: 'https://images.unsplash.com/photo-1587854692152-cbe660dbde88?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_m3', vendorId: 'mock_v2',
      name: 'Vitamin C — 30 Tablets',
      description: '1000mg effervescent Vitamin C tablets. Boosts immunity and fights fatigue. Orange flavour.',
      price: 280, category: 'Pharmacy',
      imageUrl: 'https://images.unsplash.com/photo-1550572017-4fcdbb59cc32?w=500&fit=crop',
    ),
    // ── Thrift ──
    ProductModel(
      id: 'mock_t1', vendorId: 'mock_v3',
      name: 'Vintage Denim Jacket',
      description: 'Classic 90s-style blue denim jacket, size M/L. Lightly worn with no tears or fading. A timeless wardrobe staple.',
      price: 1500, category: 'Thrift',
      imageUrl: 'https://images.unsplash.com/photo-1523205771623-e0faa4d2813d?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_t2', vendorId: 'mock_v3',
      name: 'Floral Summer Dress',
      description: 'Lightweight floral print cotton dress, size S/M. Worn only twice, washed and pressed. Perfect for summer outings.',
      price: 800, category: 'Thrift',
      imageUrl: 'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_t3', vendorId: 'mock_v3',
      name: 'Structured Leather Handbag',
      description: 'Premium faux-leather handbag in caramel brown. Roomy interior with multiple pockets. Excellent condition.',
      price: 1200, category: 'Thrift',
      imageUrl: 'https://images.unsplash.com/photo-1548036328-c9fa89d128fa?w=500&fit=crop',
    ),
    // ── Preloved ──
    ProductModel(
      id: 'mock_p1', vendorId: 'mock_v4',
      name: 'Nike Air Max — Size 42',
      description: 'Gently used Nike Air Max 270 sneakers in grey/white. Minimal wear on sole, no tears. Original box included.',
      price: 3500, category: 'Preloved',
      imageUrl: 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_p2', vendorId: 'mock_v4',
      name: 'Streetwear Graphic Tee — L',
      description: 'Cool limited-edition graphic tee in size Large. Pre-washed and ready to wear. Faded streetwear aesthetic.',
      price: 400, category: 'Preloved',
      imageUrl: 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=500&fit=crop',
    ),
    ProductModel(
      id: 'mock_p3', vendorId: 'mock_v4',
      name: 'Charcoal Formal Suit — M',
      description: 'Sharp charcoal grey two-piece formal suit, size Medium. Dry-cleaned and perfectly pressed. Ideal for interviews.',
      price: 4500, category: 'Preloved',
      imageUrl: 'https://images.unsplash.com/photo-1594938298603-c8148c4b4bc9?w=500&fit=crop',
    ),
  ];

  // ─── VENDORS ─────────────────────────────────────────────────────────────
  static List<UserModel> get vendors => [
    UserModel(
      id: 'mock_v1', name: 'TezFood Express',
      email: 'tezfood@mock.com', role: 'vendor',
      phone: '0300-1234567', profileImage: '',
      verificationStatus: 'approved',
    ),
    UserModel(
      id: 'mock_v2', name: 'City Pharmacy',
      email: 'pharmacy@mock.com', role: 'vendor',
      phone: '0321-2345678', profileImage: '',
      verificationStatus: 'approved',
    ),
    UserModel(
      id: 'mock_v3', name: 'Vintage Thrift Store',
      email: 'vintage@mock.com', role: 'vendor',
      phone: '0333-3456789', profileImage: '',
      verificationStatus: 'approved',
    ),
    UserModel(
      id: 'mock_v4', name: 'Preloved Goods PK',
      email: 'preloved@mock.com', role: 'vendor',
      phone: '0345-4567890', profileImage: '',
      verificationStatus: 'approved',
    ),
    UserModel(
      id: 'mock_v5', name: 'Green Grocers',
      email: 'grocery@mock.com', role: 'vendor',
      phone: '0301-5678901', profileImage: '',
      verificationStatus: 'approved',
    ),
  ];

  // ─── REVIEWS ─────────────────────────────────────────────────────────────
  // Generic reviews shown on any product when backend has no reviews.
  static List<Map<String, dynamic>> get sampleReviews => [
    {
      'reviewer': 'Sara K.',
      'avatar': 'S',
      'rating': 5,
      'comment': 'Absolutely amazing quality! Exactly as described. Will definitely order again.',
      'date': '12 May 2025',
    },
    {
      'reviewer': 'Ali R.',
      'avatar': 'A',
      'rating': 4,
      'comment': 'Great product, fast delivery. Packaging could be a bit better but overall happy.',
      'date': '8 May 2025',
    },
    {
      'reviewer': 'Zara M.',
      'avatar': 'Z',
      'rating': 5,
      'comment': 'Really pleased with this purchase. Super quick delivery and well-packaged!',
      'date': '2 May 2025',
    },
    {
      'reviewer': 'Ahmed B.',
      'avatar': 'A',
      'rating': 4,
      'comment': 'Good value for money. Recommended to all my friends.',
      'date': '28 Apr 2025',
    },
    {
      'reviewer': 'Hina F.',
      'avatar': 'H',
      'rating': 4,
      'comment': 'Product quality is good. Delivery was a bit slow but customer support helped.',
      'date': '20 Apr 2025',
    },
  ];

  // Pre-computed rating for sample reviews = 4.4
  static const double sampleRating = 4.4;
  static const int sampleReviewCount = 23;

  // ─── CUSTOMER ORDERS ─────────────────────────────────────────────────────
  static List<Map<String, dynamic>> get customerOrders => [
    {
      'id': 'mock_ord_aabb1122',
      'order_status': 'delivered',
      'amount': 800,
      'created_at': DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String(),
      'rider_id': null,
    },
    {
      'id': 'mock_ord_ccdd3344',
      'order_status': 'on_the_way',
      'amount': 1200,
      'created_at': DateTime.now()
          .subtract(const Duration(hours: 3))
          .toIso8601String(),
      'rider_id': null,
    },
    {
      'id': 'mock_ord_eeff5566',
      'order_status': 'accepted',
      'amount': 450,
      'created_at': DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
      'rider_id': null,
    },
    {
      'id': 'mock_ord_gghh7788',
      'order_status': 'delivered',
      'amount': 3500,
      'created_at': DateTime.now()
          .subtract(const Duration(days: 7))
          .toIso8601String(),
      'rider_id': null,
    },
    {
      'id': 'mock_ord_iijj9900',
      'order_status': 'cancelled',
      'amount': 250,
      'created_at': DateTime.now()
          .subtract(const Duration(days: 10))
          .toIso8601String(),
      'rider_id': null,
    },
  ];

  // ─── VENDOR ANALYTICS ────────────────────────────────────────────────────
  static Map<String, dynamic> get vendorAnalytics => {
    'total_revenue': 28450.0,
    'total_orders': 47,
    'pending_count': 3,
    'accepted_count': 5,
    'delivered_count': 35,
    'cancelled_count': 4,
    'top_products': <Map<String, dynamic>>[
      {'name': 'Chicken Biryani', 'category': 'Food', 'total_qty': 28},
      {'name': 'Zinger Burger', 'category': 'Food', 'total_qty': 21},
      {'name': 'Tikka Pizza', 'category': 'Food', 'total_qty': 17},
      {'name': 'Mango Shake', 'category': 'Food', 'total_qty': 14},
      {'name': 'Cold Coffee', 'category': 'Food', 'total_qty': 11},
    ],
  };

  static const String mockVendorEarnings = 'PKR 28,450';
  static const String mockVendorRating = '4.6 ★';

  // ─── VENDOR ACTIVE ORDERS ────────────────────────────────────────────────
  static List<Map<String, dynamic>> get vendorOrders => [
    {
      'id': 'mock_vo_001',
      'status': 'pending',
      'sub_total': 1050,
      'created_at': DateTime.now()
          .subtract(const Duration(minutes: 10))
          .toIso8601String(),
      'customer_name': 'Sara Khan',
      'items_summary': 'Chicken Biryani ×2, Cold Coffee ×1',
    },
    {
      'id': 'mock_vo_002',
      'status': 'accepted',
      'sub_total': 850,
      'created_at': DateTime.now()
          .subtract(const Duration(minutes: 35))
          .toIso8601String(),
      'customer_name': 'Ali Raza',
      'items_summary': 'Tikka Pizza ×1',
    },
    {
      'id': 'mock_vo_003',
      'status': 'pending',
      'sub_total': 450,
      'created_at': DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
      'customer_name': 'Hina Mirza',
      'items_summary': 'Zinger Burger ×1',
    },
  ];

  // ─── CHAT ─────────────────────────────────────────────────────────────────
  // Negative IDs are sentinels for mock rooms — never stored in Supabase.
  static const int mockRoom1 = -1;
  static const int mockRoom2 = -2;
  static const int mockRoom3 = -3;

  static List<Map<String, dynamic>> get chatRooms => [
    {
      'room_id': mockRoom1,
      'other_name': 'TezFood Express',
      'last_message': 'Your order is on the way! 🏍️',
      'last_time': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
    },
    {
      'room_id': mockRoom2,
      'other_name': 'TezRider Support',
      'last_message': 'How can we help you today?',
      'last_time': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    },
    {
      'room_id': mockRoom3,
      'other_name': 'City Pharmacy',
      'last_message': 'Your medicines are ready for pickup.',
      'last_time': DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
    },
  ];

  // Returns mock messages for a given mock room.
  // currentUserId is used so "my" messages appear on the right side.
  static List<ChatMessage> messagesForRoom(int roomId, int currentUserId) {
    const int otherId = -999;
    final now = DateTime.now();

    if (roomId == mockRoom1) {
      return [
        ChatMessage(id: 1001, roomId: roomId, senderId: otherId,
            message: 'Hi! Your order #ORD-4281 has been accepted ✅',
            createdAt: now.subtract(const Duration(minutes: 30))),
        ChatMessage(id: 1002, roomId: roomId, senderId: currentUserId,
            message: 'Great! How long will it take?',
            createdAt: now.subtract(const Duration(minutes: 28))),
        ChatMessage(id: 1003, roomId: roomId, senderId: otherId,
            message: 'Around 25-30 minutes. Preparing your food right now 🍳',
            createdAt: now.subtract(const Duration(minutes: 27))),
        ChatMessage(id: 1004, roomId: roomId, senderId: currentUserId,
            message: 'Perfect, thank you!',
            createdAt: now.subtract(const Duration(minutes: 15))),
        ChatMessage(id: 1005, roomId: roomId, senderId: otherId,
            message: 'Your order is on the way! 🏍️',
            createdAt: now.subtract(const Duration(minutes: 5))),
      ];
    } else if (roomId == mockRoom2) {
      return [
        ChatMessage(id: 2001, roomId: roomId, senderId: otherId,
            message: 'Hello! Welcome to TezRider Support 👋 How can we help?',
            createdAt: now.subtract(const Duration(hours: 2, minutes: 30))),
        ChatMessage(id: 2002, roomId: roomId, senderId: currentUserId,
            message: 'Hi, I have a question about my order.',
            createdAt: now.subtract(const Duration(hours: 2, minutes: 10))),
        ChatMessage(id: 2003, roomId: roomId, senderId: otherId,
            message: 'Of course! Please share your order ID and we will look into it immediately.',
            createdAt: now.subtract(const Duration(hours: 2, minutes: 5))),
        ChatMessage(id: 2004, roomId: roomId, senderId: currentUserId,
            message: 'It is ORD-5678. The status says placed but nothing has happened for 20 minutes.',
            createdAt: now.subtract(const Duration(hours: 2, minutes: 3))),
        ChatMessage(id: 2005, roomId: roomId, senderId: otherId,
            message: 'Apologies for the wait! We have escalated this to the vendor. You will receive an update shortly.',
            createdAt: now.subtract(const Duration(hours: 2))),
      ];
    } else {
      return [
        ChatMessage(id: 3001, roomId: roomId, senderId: otherId,
            message: 'Hello! This is City Pharmacy. How may I assist you?',
            createdAt: now.subtract(const Duration(days: 1, hours: 2))),
        ChatMessage(id: 3002, roomId: roomId, senderId: currentUserId,
            message: 'Do you have Panadol 500mg in stock right now?',
            createdAt: now.subtract(const Duration(days: 1, hours: 1, minutes: 55))),
        ChatMessage(id: 3003, roomId: roomId, senderId: otherId,
            message: 'Yes, we have it! Would you like to place an order for delivery?',
            createdAt: now.subtract(const Duration(days: 1, hours: 1, minutes: 50))),
        ChatMessage(id: 3004, roomId: roomId, senderId: currentUserId,
            message: 'Yes please, 2 strips.',
            createdAt: now.subtract(const Duration(days: 1, hours: 1))),
        ChatMessage(id: 3005, roomId: roomId, senderId: otherId,
            message: 'Order placed! Your medicines are ready for pickup at our store.',
            createdAt: now.subtract(const Duration(days: 1))),
      ];
    }
  }
}
