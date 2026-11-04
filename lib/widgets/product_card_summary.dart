import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Price and secondary actions flow independently when a card is narrow.
class ProductCardSummary extends StatelessWidget {
  const ProductCardSummary({
    super.key,
    required this.price,
    required this.rating,
    required this.reviewCount,
    required this.favourite,
    required this.favouriteLabel,
    required this.onFavourite,
  });

  final String price, rating, favouriteLabel;
  final int reviewCount;
  final bool favourite;
  final VoidCallback onFavourite;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        price,
        style: const TextStyle(
          color: AppColors.primaryDark,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: -.4,
        ),
      ),
      Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: favouriteLabel,
            style: IconButton.styleFrom(
              backgroundColor: favourite
                  ? AppColors.primarySurface
                  : AppColors.bgLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onFavourite,
            icon: Icon(
              favourite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: favourite ? AppColors.primary : AppColors.textSecondary,
              size: 21,
            ),
          ),
          const Icon(Icons.star_rounded, size: 16, color: AppColors.warning),
          Text(rating, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (reviewCount > 0) Text('($reviewCount)'),
        ],
      ),
    ],
  );
}
