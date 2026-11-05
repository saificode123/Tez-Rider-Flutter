import '../search_screen.dart';
import '../../widgets/spatial_surface.dart';
import '../../theme/app_theme.dart';

import 'package:flutter_application_1/core/stage2_ui_strings.dart';

import '../../widgets/stock_indicator.dart';
import '../../services/inventory_service.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/product_image.dart';
import '../../widgets/related_favorites.dart';
import '../../controllers/cart_controller.dart';
import '../product_detail_screen.dart';

const _kPurple = AppColors.primaryDark;
const _kBg = AppColors.bgLight;
const _kCard = Color(0xFFFFFFFF);
const _kText = AppColors.textPrimary;
const _kTextSub = AppColors.textSecondary;
const _kPink = Color(0xFFEC4899);
const _kSaffron = Color(0xFFF59E0B);
const _kGreen = Color(0xFF10B981);

class SavedStoresScreen extends StatefulWidget {
  const SavedStoresScreen({super.key});
  @override
  State<SavedStoresScreen> createState() => _SavedStoresScreenState();
}

class _SavedStoresScreenState extends State<SavedStoresScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _favourites = [];
  bool _loading = true;
  String? _loadError;
  int? _userId;
  bool _loadBusy = false;
  bool _related = false;
  int _relatedRevision = 0;
  final Set<dynamic> _removing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loadBusy || !mounted) return;
    _loadBusy = true;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw StateError('Sign in required');
      final rec = await _supabase
          .from('users')
          .select('id')
          .eq('auth_user_id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));
      if (rec == null) throw StateError('Account unavailable');
      _userId = rec['id'];

      final data =
          await _supabase
                  .from('favourite')
                  .select(
                    'id, product_id, products(id, name, description, price, image_url, category, vendor_id, is_available, stock_qty, stock_confirmed, stock_version, low_stock_threshold)',
                  )
                  .eq('user_id', _userId!)
                  .order('created_at', ascending: false)
                  .timeout(const Duration(seconds: 12))
              as List;
      if (mounted) {
        setState(() => _favourites = data.cast<Map<String, dynamic>>());
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _loadError = error.code == '42501'
              ? 'Favorites are unavailable for this account. Please contact support.'
              : 'Favorites could not be loaded. Please retry.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError =
              'Favorites could not be loaded. Check your connection and retry.',
        );
      }
    } finally {
      _loadBusy = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(dynamic favId, String name) async {
    if (_userId == null || _removing.contains(favId)) return;
    setState(() => _removing.add(favId));
    try {
      await _supabase
          .from('favourite')
          .delete()
          .eq('id', favId)
          .eq('user_id', _userId!)
          .select('id')
          .single()
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() => _favourites.removeWhere((row) => row['id'] == favId));
      Get.snackbar(
        "Removed".tr,
        "\"@slot0end\" removed from favourites.".uiTr({
          "slot0end": (name).toString(),
        }),
        backgroundColor: _kPurple,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        borderRadius: 14,
      );
    } catch (_) {
      if (mounted) {
        Get.snackbar(
          "Not removed".tr,
          "Removal was not confirmed. Please retry.".tr,
        );
      }
    } finally {
      if (mounted) setState(() => _removing.remove(favId));
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final cart = Get.find<CartController>();
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        toolbarHeight: 64,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        backgroundColor: _kPurple,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Favourites".tr,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _related
                ? () => setState(() => _relatedRevision++)
                : _loading
                ? null
                : _load,
            tooltip: 'Refresh favorites'.tr,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text('Products'.tr),
                  selected: !_related,
                  onSelected: (_) => setState(() => _related = false),
                ),
                ChoiceChip(
                  label: Text('Vendors & Riders'.tr),
                  selected: _related,
                  onSelected: (_) => setState(() => _related = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: _related
                ? SingleChildScrollView(
                    child: RelatedFavorites(key: ValueKey(_relatedRevision)),
                  )
                : _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: _kPurple,
                      strokeWidth: 2,
                    ),
                  )
                : _loadError != null
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: SpatialSurface(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              color: _kPurple,
                              size: 40,
                            ),
                            const SizedBox(height: 16),
                            Text(_loadError!.tr, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text("Retry favourites".tr),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _favourites.isEmpty
                ? _buildEmpty()
                : RefreshIndicator(
                    color: _kPurple,
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      itemCount: _favourites.length,
                      itemBuilder: (_, i) => _buildCard(_favourites[i], cart),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SpatialSurface(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: AppColors.primarySurface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite_border_rounded,
                    size: 48,
                    color: _kPurple,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'No Favorites'.tr,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Save products you love using the heart on a product.'.tr,
                  style: const TextStyle(color: _kTextSub, height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    await Get.to(() => const SearchScreen());
                    if (mounted) await _load();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text('Add to Favorites'.tr),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> fav, CartController cart) {
    final p = fav['products'] as Map<String, dynamic>?;
    if (p == null) {
      return SpatialSurface(
        margin: const EdgeInsets.only(bottom: 14),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_outlined, color: _kPurple),
          title: Text('Product unavailable'.tr),
          subtitle: Text('This saved product is no longer available.'.tr),
          trailing: IconButton(
            tooltip: 'Remove'.tr,
            onPressed: _removing.contains(fav['id'])
                ? null
                : () => _remove(fav['id'], 'Product'.tr),
            icon: const Icon(Icons.favorite_rounded, color: _kPurple),
          ),
        ),
      );
    }
    final name = p['name'] ?? 'Product';
    final price = p['price'] ?? 0;
    final imageUrl = p['image_url'] as String? ?? '';
    final category = p['category'] as String? ?? '';

    return GestureDetector(
      onTap: () => Get.to(() => ProductDetailScreen(product: p)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _kPurple.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(18),
              ),
              child: imageUrl.isNotEmpty
                  ? ProductImage(
                      imageUrl: imageUrl,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(category),
                      errorWidget: (_, __, ___) => _placeholder(category),
                    )
                  : _placeholder(category),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StockIndicator(product: p),
                    Text(
                      name,
                      style: const TextStyle(
                        color: _kText,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kPurple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                            color: _kPurple,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      "PKR @slot0end".uiTr({"slot0end": (price).toString()}),
                      style: const TextStyle(
                        color: _kSaffron,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.favorite_rounded,
                      color: _kPink,
                      size: 22,
                    ),
                    onPressed: _removing.contains(fav['id'])
                        ? null
                        : () => _remove(fav['id'], name),
                    tooltip: "Remove".tr,
                  ),
                  Material(
                    color: _kPurple,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: ProductStock(p).purchasable
                          ? () async {
                              final added = await cart.addItem({
                                'product_id': p['id'],
                                'name': name,
                                'price': price,
                                'image_url': imageUrl,
                                'vendor_id': p['vendor_id'],
                              });
                              if (!added) {
                                Get.snackbar("Cart".tr, cart.lastError.value);
                                return;
                              }
                              Get.snackbar(
                                '',
                                "@slot0end added! 🛒".uiTr({
                                  "slot0end": (name).toString(),
                                }),
                                titleText: const SizedBox.shrink(),
                                messageText: Text(
                                  "@slot0end added! 🛒".uiTr({
                                    "slot0end": (name).toString(),
                                  }),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                backgroundColor: _kGreen,
                                snackPosition: SnackPosition.BOTTOM,
                                margin: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  24,
                                ),
                                borderRadius: 16,
                                duration: const Duration(seconds: 2),
                              );
                            }
                          : null,
                      child: const SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(String cat) {
    final icon = switch (cat.toLowerCase().trim()) {
      'food' => Icons.restaurant_rounded,
      'grocery' || 'groceries' => Icons.local_grocery_store_rounded,
      'pharmacy' => Icons.local_pharmacy_rounded,
      'thrift' => Icons.checkroom_rounded,
      'preloved' => Icons.recycling_rounded,
      'tailoring' => Icons.content_cut_rounded,
      _ => Icons.shopping_bag_outlined,
    };
    return Container(
      width: 88,
      height: 88,
      color: _kPurple.withValues(alpha: 0.08),
      child: Center(child: Icon(icon, size: 32, color: _kPurple)),
    );
  }
}
