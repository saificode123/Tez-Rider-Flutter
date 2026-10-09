import 'package:get/get.dart';
import '../models/product_model.dart';
import '../services/recommendation_service.dart';
import '../controllers/product_controller.dart';

class RecommendationController extends GetxController {
  final recommendationService = RecommendationService();
  final productController = Get.find<ProductController>();

  var recommendations = <ProductModel>[].obs;
  var isLoading = false.obs;

  /// Get smart recommendations for a product
  Future<void> fetchRecommendations(ProductModel product) async {
    try {
      isLoading.value = true;
      final recs = await recommendationService.getSmartRecommendations(
        product,
        productController.products,
      );
      recommendations.value = recs;
    } catch (e) {
      print('RecommendationController error: $e');
      recommendations.value = [];
    } finally {
      isLoading.value = false;
    }
  }

  /// Clear recommendations
  void clearRecommendations() {
    recommendations.value = [];
  }
}
