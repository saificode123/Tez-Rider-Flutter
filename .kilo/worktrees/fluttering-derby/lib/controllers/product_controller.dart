import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/user_model.dart';
import '../data/mock_data.dart';

class ProductController extends GetxController {
  final _supabase = Supabase.instance.client;

  var products = <ProductModel>[].obs;
  var vendors  = <UserModel>[].obs;
  var isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    _fetchVendorsAndProducts();
  }

  void _fetchVendorsAndProducts() async {
    try {
      final vendorData  = await _supabase.from('users').select().eq('role', 'vendor');
      final productData = await _supabase.from('products').select();

      final realVendors  = vendorData.map((e) => UserModel.fromJson(e)).toList();
      final realProducts = productData.map((e) => ProductModel.fromJson(e)).toList();

      // Mock data always shown first; real backend products append behind them.
      vendors.value  = [...MockData.vendors,   ...realVendors];
      products.value = [...MockData.products, ...realProducts];
    } catch (e) {
      debugPrint('ProductController: backend fetch failed — using mock data only. $e');
      vendors.value  = MockData.vendors;
      products.value = MockData.products;
    } finally {
      isLoading.value = false;
    }
  }

  List<ProductModel> getProductsForVendor(String vendorId) {
    return products.where((p) => p.vendorId == vendorId).toList();
  }

  List<ProductModel> getProductsByCategory(String category) {
    if (category == 'All') return products;
    final cat = category.toLowerCase().trim();
    final exact = products
        .where((p) => p.category.toLowerCase().trim() == cat)
        .toList();
    if (exact.isNotEmpty) return exact;
    // Partial match: handles "Groceries" ↔ "Grocery", "Medicines" ↔ "Pharmacy", etc.
    return products.where((p) {
      final pc = p.category.toLowerCase().trim();
      return pc.contains(cat) || cat.contains(pc);
    }).toList();
  }

  List<ProductModel> getPopularProducts() => products.take(6).toList();
}
