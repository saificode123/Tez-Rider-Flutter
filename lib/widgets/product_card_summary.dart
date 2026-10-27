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
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
      Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: favouriteLabel,
            onPressed: onFavourite,
            icon: Icon(
              favourite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: AppColors.error,
              size: 20,
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
