class ProductModel {
  final String id;
  final String vendorId;
  final String category;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final bool isAvailable;
  final bool requiresPrescription;

  ProductModel({
    required this.id,
    required this.vendorId,
    required this.category,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    this.isAvailable = true,
    this.requiresPrescription = false,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id:          (json['id']          ?? '').toString(),
      vendorId:    (json['vendor_id']   ?? '').toString(),
      category:    (json['category']    ?? 'General').toString(),
      name:        (json['name']        ?? 'Unknown Product').toString(),
      description: (json['description'] ?? '').toString(),
      price: json['price'] is num
          ? (json['price'] as num).toDouble()
          : double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
      imageUrl: ((json['image_url'] as String?)?.trim().isNotEmpty == true)
          ? (json['image_url'] as String).trim()
          : '',
      isAvailable: json['is_available'] ?? true,
      requiresPrescription: json['requires_prescription'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'vendor_id': vendorId,
      'category': category,
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'is_available': isAvailable,
      'requires_prescription': requiresPrescription,
    };
  }
}
