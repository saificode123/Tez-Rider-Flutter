import 'dart:async';
import 'package:get/get.dart';
import '../models/product_model.dart';
import '../models/user_model.dart';
import '../services/catalogue_service.dart';
import 'notification_controller.dart';
import 'cart_controller.dart';

class ProductController extends GetxController {
  ProductController({CatalogueService? catalogue})
    : _catalogue = catalogue ?? CatalogueService();
  final CatalogueService _catalogue;
  final products = <ProductModel>[].obs;
  // Retained API; public shop information comes from VendorInfoController,
  // not an unauthorized directory query against private users profiles.
  final vendors = <UserModel>[].obs;
  final isLoading = true.obs;
  final loadingMore = false.obs;
  final hasMore = false.obs;
  final category = 'All'.obs;
  final error = RxnString();
  bool _fetching = false, _refreshPending = false;
  String _activeCategory = 'All';
  int _generation = 0;
  Map<String, dynamic>? _cursor;
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
    _generation++;
    _notificationRefresh?.dispose();
    super.onClose();
  }

  Future<void> selectCategory(String value) async {
    category.value = value;
    await refreshProducts();
  }

  Future<void> refreshProducts({bool loadMore = false}) async {
    if (isClosed) return;
    if (_fetching && _activeCategory == category.value) {
      if (!loadMore) _refreshPending = true;
      return;
    }
    if (loadMore && !hasMore.value) return;
    final generation = loadMore ? _generation : ++_generation;
    final selected = category.value;
    _activeCategory = selected;
    _fetching = true;
    if (loadMore) {
      loadingMore.value = true;
    } else {
      isLoading.value = true;
      products.clear();
      hasMore.value = false;
      _cursor = null;
    }
    error.value = null;
    try {
      final page = await _catalogue.load(
        category: selected == 'All' ? null : selected,
        after: loadMore ? _cursor : null,
      );
      if (isClosed || generation != _generation) return;
      final rows = page.items.map(ProductModel.fromJson).toList();
      if (loadMore) {
        final ids = products.map((p) => p.id).toSet();
        products.addAll(rows.where((p) => ids.add(p.id)));
      } else {
        products.assignAll(rows);
      }
      _cursor = page.cursor;
      hasMore.value = page.hasMore;
    } catch (_) {
      if (!isClosed && generation == _generation) {
        error.value = 'Products could not be refreshed. Retry when connected.';
      }
    } finally {
      if (!isClosed && generation == _generation) {
        _fetching = false;
        isLoading.value = false;
        loadingMore.value = false;
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(refreshProducts());
        }
      }
    }
  }

  List<ProductModel> getProductsForVendor(String vendorId) =>
      products.where((p) => p.vendorId == vendorId).toList();
  List<ProductModel> getProductsByCategory(String value) {
    if (value == 'All') return products;
    return products
        .where(
          (p) => p.category.toLowerCase().trim() == value.toLowerCase().trim(),
        )
        .toList();
  }

  List<ProductModel> getPopularProducts() => products.take(6).toList();
}
