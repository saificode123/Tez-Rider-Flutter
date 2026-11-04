import '../theme/app_theme.dart';
import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import '../widgets/stock_indicator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../widgets/product_image.dart';
import '../../models/product_model.dart';
import '../../controllers/cart_controller.dart';

class RecommendationCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback? onAddToCart;

  static const _purple = AppColors.primary;

  const RecommendationCard({
    super.key,
    required this.product,
    this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Container(
      width: 168,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider, width: 1),
        boxShadow: AppShadow.soft,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: product.imageUrl.isNotEmpty
                ? ProductImage(
                    imageUrl: product.imageUrl,
                    width: double.infinity,
                    height: 110,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 110,
                      color: AppColors.bgSection,
                      child: const Icon(Icons.image, color: AppColors.textHint),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 110,
                      color: AppColors.bgSection,
                      child: const Icon(
                        Icons.fastfood,
                        color: AppColors.textHint,
                      ),
                    ),
                  )
                : Container(
                    height: 110,
                    color: AppColors.bgSection,
                    child: const Icon(
                      Icons.fastfood,
                      color: AppColors.textHint,
                    ),
                  ),
          ),
          // Product Details
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StockIndicator(product: product.toJson()),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "PKR @slot0end".uiTr({
                    "slot0end": (product.price).toString(),
                  }),
                  style: const TextStyle(
                    color: _purple,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: product.isPurchasable
                        ? () async {
                            final cart = Get.find<CartController>();
                            final added = await cart.addItem({
                              'name': product.name,
                              'price': product.price,
                              'vendor_id': product.vendorId,
                              'product_id': product.id,
                              'image_url': product.imageUrl,
                            });
                            if (!added) {
                              Get.snackbar("Cart".tr, cart.lastError.value);
                              return;
                            }
                            Get.snackbar(
                              "Added to Cart".tr,
                              "@slot0end added successfully!".uiTr({
                                "slot0end": (product.name).toString(),
                              }),
                              snackPosition: SnackPosition.BOTTOM,
                              duration: const Duration(seconds: 2),
                            );
                            onAddToCart?.call();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      "Add".tr,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
