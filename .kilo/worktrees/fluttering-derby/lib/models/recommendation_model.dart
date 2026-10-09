class RecommendationModel {
  final String? id;
  final String? productId;
  final String? complementaryProductId;
  final String? categoryTag;
  final int priority;

  RecommendationModel({
    this.id,
    this.productId,
    this.complementaryProductId,
    this.categoryTag,
    this.priority = 1,
  });

  factory RecommendationModel.fromJson(Map<String, dynamic> json) {
    return RecommendationModel(
      id: json['id']?.toString(),
      productId: json['product_id']?.toString(),
      complementaryProductId: json['complementary_product_id']?.toString(),
      categoryTag: json['category_tag'],
      priority: json['priority'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'complementary_product_id': complementaryProductId,
      'category_tag': categoryTag,
      'priority': priority,
    };
  }
}
