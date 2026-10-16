import 'dart:async';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/user_model.dart';
import 'notification_controller.dart';
import 'cart_controller.dart';

class ProductController extends GetxController {
  final _supabase = Supabase.instance.client;
  final products = <ProductModel>[].obs;
  final vendors = <UserModel>[].obs;
  final isLoading = true.obs;
  final hasMore = false.obs;
  final error = RxnString();
  bool _fetching = false;
  bool _refreshPending = false;
  Worker? _notificationRefresh;
  @override
  void onInit() {
    super.onInit();
    unawaited(refreshProducts());
  }

  @override
  void onReady() {
    super.onReady();
    if (Get.isRegistered<NotificationController>()) {
      _notificationRefresh = ever(
        Get.find<NotificationController>().notifications,
        (_) {
          unawaited(refreshProducts());
          if (Get.isRegistered<CartController>()) {
            unawaited(Get.find<CartController>().refreshAvailability());
          }
        },
      );
    }
  }

  @override
  void onClose() {
    _notificationRefresh?.dispose();
    super.onClose();
  }

  Future<void> refreshProducts({bool loadMore = false}) async {
    if (_fetching) {
      if (!loadMore) _refreshPending = true;
      return;
    }
    _fetching = true;
    if (!loadMore) isLoading.value = true;
    try {
      final offset = loadMore ? products.length : 0;
      final rows = await _supabase
          .from('products')
          .select()
          .order('id')
          .range(offset, offset + 99)
          .timeout(const Duration(seconds: 12));
      final page = rows.map(ProductModel.fromJson).toList();
      if (loadMore) {
        products.addAll(page);
      } else {
        products.assignAll(page);
      }
      hasMore.value = rows.length == 100;
      if (!loadMore) {
        final vendorRows = await _supabase
            .from('users')
            .select('id,name,role,verification_status,profile_image')
            .eq('role', 'vendor')
            .limit(100);
        vendors.assignAll(vendorRows.map(UserModel.fromJson));
      }
      error.value = null;
    } catch (_) {
      error.value = 'Products could not be refreshed. Retry when connected.';
    } finally {
      _fetching = false;
      isLoading.value = false;
      if (_refreshPending && !isClosed) {
        _refreshPending = false;
        unawaited(refreshProducts());
      }
    }
  }

  List<ProductModel> getProductsForVendor(String vendorId) =>
      products.where((p) => p.vendorId == vendorId).toList();
  List<ProductModel> getProductsByCategory(String category) {
    if (category == 'All') return products;
    final cat = category.toLowerCase().trim();
    final exact = products
        .where((p) => p.category.toLowerCase().trim() == cat)
        .toList();
    if (exact.isNotEmpty) return exact;
    return products.where((p) {
      final pc = p.category.toLowerCase().trim();
      return pc.contains(cat) || cat.contains(pc);
    }).toList();
  }

  List<ProductModel> getPopularProducts() => products.take(6).toList();
}
