import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/product_image.dart';
import '../../controllers/cart_controller.dart';
import '../../controllers/recommendation_controller.dart';
import '../../controllers/product_controller.dart';
import '../../controllers/prescription_controller.dart';
import '../../screens/customer/enhanced_checkout_screen.dart';
import '../../widgets/recommendation_card.dart';
import '../../widgets/stock_indicator.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final CartController cart = Get.find<CartController>();
  final ProductController productController = Get.find<ProductController>();
  final _supabase = Supabase.instance.client;

  late RecommendationController recommendationController;
  late PrescriptionController prescriptionController;

  bool _isGift = false;
  String? _selectedProductForRec;

  final TextEditingController _recNameCtrl = TextEditingController();
  final TextEditingController _recPhoneCtrl = TextEditingController();
  final TextEditingController _giftMsgCtrl = TextEditingController();

  static const _purple = Color(0xFF1B5E20);

  @override
  void initState() {
    super.initState();
    cart.refreshAvailability();
    if (Get.isRegistered<RecommendationController>()) {
      recommendationController = Get.find<RecommendationController>();
    } else {
      recommendationController = Get.put(RecommendationController());
    }

    if (Get.isRegistered<PrescriptionController>()) {
      prescriptionController = Get.find<PrescriptionController>();
    } else {
      prescriptionController = Get.put(PrescriptionController());
    }

    if (cart.cartItems.isNotEmpty) {
      _loadRecommendations();
    }
  }

  /// Load recommendations for recently added item
  void _loadRecommendations() async {
    if (cart.cartItems.isEmpty) return;

    final lastItem = cart.cartItems.last;
    final productId = lastItem['product_id']?.toString();

    if (productId != null && productId.isNotEmpty) {
      final product = productController.products.firstWhereOrNull(
        (p) => p.id == productId,
      );

      if (product != null) {
        _selectedProductForRec = productId;
        await recommendationController.fetchRecommendations(product);
      }
    }
  }

  /// Check if cart has items requiring prescription
  bool _hasItemsRequiringPrescription() {
    return cart.cartItems.any((item) {
      final productId = item['product_id']?.toString();
      if (productId == null) return false;
      final product = productController.products.firstWhereOrNull(
        (p) => p.id == productId,
      );
      return product?.requiresPrescription ?? false;
    });
  }

  void _showCheckoutSheet() {
    if (!cart.synchronizationReady) {
      Get.snackbar(
        'Cart synchronization required',
        'Restore or retry your saved cart before checkout.',
      );
      return;
    }
    if (_isGift) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gift delivery is not configured. No gift order was submitted.',
          ),
        ),
      );
      return;
    }
    Get.to(
      () => EnhancedCheckoutScreen(
        cart: cart,
        customerId: _supabase.auth.currentUser?.id ?? 'unknown',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Text(
          'cart'.tr,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A0533),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A0533)),
        centerTitle: true,
      ),
      body: Obx(() {
        if (cart.syncing.value && cart.cartItems.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (cart.lastError.value.isNotEmpty && cart.cartItems.isEmpty) {
          return Center(child: _syncNotice());
        }
        if (cart.cartItems.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 80,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'cart_empty'.tr,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            if (cart.syncing.value) const LinearProgressIndicator(),
            if (cart.lastError.value.isNotEmpty) _syncNotice(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Cart Items
                  ...List.generate(cart.cartItems.length, (i) {
                    final item = cart.cartItems[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: item['image_url'] != null
                                ? ProductImage(
                                    imageUrl: item['image_url'],
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      width: 60,
                                      height: 60,
                                      color: Colors.grey.shade200,
                                      child: const Icon(
                                        Icons.image,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                          width: 60,
                                          height: 60,
                                          color: Colors.grey.shade200,
                                          child: const Icon(
                                            Icons.fastfood,
                                            color: Colors.grey,
                                          ),
                                        ),
                                  )
                                : Container(
                                    width: 60,
                                    height: 60,
                                    color: Colors.grey.shade200,
                                    child: const Icon(
                                      Icons.fastfood,
                                      color: Colors.grey,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                StockIndicator(product: item),
                                const SizedBox(height: 4),
                                Text(
                                  "PKR ${item['price']}",
                                  style: const TextStyle(
                                    color: _purple,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.grey,
                                ),
                                onPressed: () => cart.decrementQty(item),
                              ),
                              Text(
                                '${item['qty'] ?? 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  color: _purple,
                                ),
                                onPressed: cart.canIncrement(item)
                                    ? () async {
                                        if (!await cart.incrementQty(item)) {
                                          Get.snackbar(
                                            'Cart',
                                            cart.lastError.value,
                                          );
                                          return;
                                        }
                                        _loadRecommendations();
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),

                  // Smart Recommendations Section
                  Obx(() {
                    if (recommendationController.recommendations.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'You might also like',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Complementary items from the same vendor',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const SizedBox(width: 8),
                              ...recommendationController.recommendations.map(
                                (product) => RecommendationCard(
                                  product: product,
                                  onAddToCart: _loadRecommendations,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),

                  // Prescription Warning Section
                  if (_hasItemsRequiringPrescription()) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_rounded,
                            color: Colors.amber.shade700,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Prescription Required',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Your order contains medicines. You\'ll need to upload a prescription during checkout.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'send_as_gift'.tr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Perfect for overseas users surprising loved ones.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      value: _isGift,
                      activeThumbColor: _purple,
                      onChanged: (val) => setState(() => _isGift = val),
                    ),
                  ),

                  if (_isGift) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _recNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'recipient_name'.tr,
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _recPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'recipient_phone'.tr,
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _giftMsgCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'gift_message'.tr,
                        prefixIcon: const Icon(Icons.card_giftcard),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'total'.tr,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        'PKR ${cart.totalPrice}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () => _showCheckoutSheet(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Proceed to Checkout',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _syncNotice() => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(cart.lastError.value),
        TextButton(
          onPressed: cart.syncing.value
              ? null
              : () async {
                  if (cart.synchronizationReady) {
                    await cart.refreshAvailability();
                  } else {
                    await cart.retrySync();
                  }
                },
          child: const Text('Retry cart synchronization'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _recNameCtrl.dispose();
    _recPhoneCtrl.dispose();
    _giftMsgCtrl.dispose();
    super.dispose();
  }
}
