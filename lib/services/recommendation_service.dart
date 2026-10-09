import '../models/product_model.dart';

class RecommendationService {
  /// Get recommendations from the same vendor and same category
  Future<List<ProductModel>> getSmartRecommendations(
    ProductModel product,
    List<ProductModel> allProducts,
  ) async {
    try {
      final productCat = product.category.toLowerCase().trim();

      final recommendations = allProducts
          .where((p) =>
              p.id != product.id &&
              p.category.toLowerCase().trim() == productCat)
          .take(5)
          .toList();

      return recommendations;
    } catch (e) {
      print('RecommendationService error: $e');
      return [];
    }
  }
}