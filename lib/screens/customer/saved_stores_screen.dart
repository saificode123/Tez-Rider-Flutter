import '../../widgets/stock_indicator.dart';
import '../../services/inventory_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../controllers/cart_controller.dart';
import '../product_detail_screen.dart';

const _kPurple = Color(0xFF1B5E20);
const _kBg = Color(0xFFF8F7FF);
const _kCard = Color(0xFFFFFFFF);
const _kText = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw StateError('Sign in required');
      final rec = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .maybeSingle();
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
              as List;
      if (mounted) setState(() => _favourites = data.cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Favourites could not be loaded. Retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(dynamic favId, String name) async {
    try {
    await _supabase.from('favourite').delete().eq('id', favId).select('id').single();
    _load();
    Get.snackbar(
      'Removed',
      '"$name" removed from favourites.',
      backgroundColor: _kPurple,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      borderRadius: 14,
    );
    } catch (_) {
      Get.snackbar('Not removed', 'Removal was not confirmed. Please retry.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Get.find<CartController>();
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
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
        title: const Text(
          'Favourites',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2),
            )
          : _loadError != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_loadError!), TextButton(onPressed: _load, child: const Text('Retry favourites')),
            ]))
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
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('❤️', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 20),
          const Text(
            'No favourites yet',
            style: TextStyle(
              color: _kText,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap ❤️ on any product to save it here.',
            style: TextStyle(color: _kTextSub, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> fav, CartController cart) {
    final p = fav['products'] as Map<String, dynamic>? ?? {};
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
                  ? CachedNetworkImage(
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
                      'PKR $price',
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
                    onPressed: () => _remove(fav['id'], name),
                    tooltip: 'Remove',
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
                                Get.snackbar('Cart', cart.lastError.value);
                                return;
                              }
                              Get.snackbar(
                                '',
                                '$name added! 🛒',
                                titleText: const SizedBox.shrink(),
                                messageText: Text(
                                  '$name added! 🛒',
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
    const map = {
      'Food': '🍔',
      'Grocery': '🥦',
      'Pharmacy': '💊',
      'Thrift': '👗',
      'Preloved': '♻️',
      'Tailoring': '✂️',
    };
    return Container(
      width: 88,
      height: 88,
      color: _kPurple.withValues(alpha: 0.08),
      child: Center(
        child: Text(map[cat] ?? '🛍️', style: const TextStyle(fontSize: 32)),
      ),
    );
  }
}
