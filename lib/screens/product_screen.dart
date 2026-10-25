import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import '../widgets/product_image.dart';
import '../widgets/stock_indicator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/cart_controller.dart';
import '../controllers/product_controller.dart';

class ProductScreen extends StatelessWidget {
  final Map vendor;

  ProductScreen({super.key, required this.vendor});

  final CartController cart = Get.find<CartController>();
  final ProductController productCtrl = Get.find<ProductController>();

  static const _purple = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A0533)),
        title: Text(
          vendor['name'] ?? "Vendor".tr,
          style: const TextStyle(
            color: Color(0xFF1A0533),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Obx(() {
        if (productCtrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator(color: _purple));
        }

        if (productCtrl.error.value != null)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(productCtrl.error.value!),
                TextButton(
                  onPressed: productCtrl.refreshProducts,
                  child: Text("Retry".tr),
                ),
              ],
            ),
          );

        final vendorProducts = productCtrl.getProductsForVendor(
          vendor['id'] ?? '',
        );

        if (vendorProducts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 80,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  "No products available".tr,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "This store hasn't added any items yet.".tr,
                  style: TextStyle(color: Colors.grey),
                ),
                if (productCtrl.hasMore.value)
                  TextButton(
                    onPressed: () =>
                        productCtrl.refreshProducts(loadMore: true),
                    child: Text("Load more products".tr),
                  ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount:
              vendorProducts.length + (productCtrl.hasMore.value ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == vendorProducts.length)
              return TextButton(
                onPressed: () => productCtrl.refreshProducts(loadMore: true),
                child: Text("Load more products".tr),
              );
            final p = vendorProducts[i];

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                    child: ProductImage(
                      imageUrl: p.imageUrl,
                      width: 110,
                      height: 110,
                      fit: BoxFit.cover,
                      errorWidget: (context, error, stackTrace) => Container(
                        width: 110,
                        height: 110,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.fastfood, color: Colors.grey),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StockIndicator(product: p.toJson()),
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            p.description,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "PKR @slot0end".uiTr({
                                  "slot0end": (p.price.toInt()).toString(),
                                }),
                                style: const TextStyle(
                                  color: _purple,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              InkWell(
                                onTap:
                                    p.isPurchasable &&
                                        !cart.checking.contains(p.id)
                                    ? () async {
                                        final added = await cart.addItem(
                                          p.toJson(),
                                        );
                                        if (!added) {
                                          Get.snackbar(
                                            "Cart".tr,
                                            cart.lastError.value,
                                          );
                                          return;
                                        }
                                        Get.snackbar(
                                          "Added to Cart".tr,
                                          "@slot0end added successfully".uiTr({
                                            "slot0end": (p.name).toString(),
                                          }),
                                          backgroundColor: Colors.white,
                                          colorText: const Color(0xFF1A0533),
                                          snackPosition: SnackPosition.BOTTOM,
                                          margin: const EdgeInsets.all(16),
                                        );
                                      }
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _purple,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    "Add".tr,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}
