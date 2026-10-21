import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../controllers/cart_controller.dart';
import '../controllers/vendor_info_controller.dart';

import '../services/inventory_service.dart';
import '../widgets/stock_indicator.dart';

const _kGreen = Color(0xFF1B5E20);
const _kGreenL = Color(0xFF388E3C);
const _kSaffron = Color(0xFFF59E0B);
const _kPink = Color(0xFFEC4899);
const _kText = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);
const _kBg = Color(0xFFF5F6FA);

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _supabase = Supabase.instance.client;
  final cartCtrl = Get.find<CartController>();
  final vendorInfoCtrl = Get.put(VendorInfoController());

  bool _isFav = false;
  bool _favLoading = false;
  int? _userId;
  late Map<String, dynamic> _currentProduct;
  bool _stockLoading = true;
  String? _stockError;
  double _rating = 0;
  int _reviewCount = 0;

  // Only confirmed backend reviews are displayed.
  List<Map<String, dynamic>> _reviews = [];
  String? _ratingError;

  @override
  void initState() {
    super.initState();
    _currentProduct = Map<String, dynamic>.from(widget.product);
    _refreshStock();
    _loadFavStatus();
    _loadRating();
    final vendorId = widget.product['vendor_id']?.toString() ?? '';
    if (vendorId.isNotEmpty) {
      vendorInfoCtrl.loadVendorInfo([vendorId]);
    }
  }

  Future<void> _refreshStock() async {
    setState(() {
      _stockLoading = true;
      _stockError = null;
    });
    try {
      final id = int.parse(widget.product['id'].toString());
      final rows = await InventoryApi.read([id]);
      if (!mounted) return;
      setState(() {
        _currentProduct = {..._currentProduct, ...?rows.firstOrNull};
        if (rows.isEmpty) _currentProduct['is_available'] = false;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _stockError =
              'Availability could not be refreshed. Retry when connected.',
        );
    } finally {
      if (mounted) setState(() => _stockLoading = false);
    }
  }

  Future<void> _loadRating() async {
    try {
      final vendorId = widget.product['vendor_id'];
      if (vendorId == null) return;
      final rows =
          await _supabase
                  .from('reviews')
                  .select('rating, comment, reviewer_id, created_at')
                  .eq('reviewee_id', vendorId.toString())
              as List;

      if (rows.isEmpty) return;

      final count = rows.length;
      final avg =
          rows.fold<double>(0, (s, r) => s + (r['rating'] as num).toDouble()) /
          count;

      // Resolve reviewer names for real reviews.
      final List<Map<String, dynamic>> enriched = [];
      for (final r in rows) {
        String reviewer = 'Customer';
        try {
          final rec = await _supabase
              .from('users')
              .select('name')
              .eq('id', r['reviewer_id'])
              .maybeSingle();
          reviewer = rec?['name'] ?? 'Customer';
        } catch (_) {}
        final dt = r['created_at'] != null
            ? DateTime.tryParse(r['created_at'].toString())
            : null;
        enriched.add({
          'reviewer': reviewer,
          'avatar': reviewer.isNotEmpty ? reviewer[0].toUpperCase() : 'C',
          'rating': (r['rating'] as num).toInt(),
          'comment': r['comment'] ?? '',
          'date': dt != null
              ? '${dt.day} ${_monthName(dt.month)} ${dt.year}'
              : '',
        });
      }

      if (mounted) {
        setState(() {
          _rating = avg;
          _reviewCount = count;
          _reviews = enriched;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ratingError = 'Reviews are unavailable.');
    }
  }

  String _monthName(int m) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return m >= 1 && m <= 12 ? months[m] : '';
  }

  Future<void> _loadFavStatus() async {
    final pid = int.tryParse(widget.product['id']?.toString() ?? '');
    if (pid == null) return;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final rec = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .maybeSingle();
      if (rec == null) return;
      _userId = rec['id'];
      final fav = await _supabase
          .from('favourite')
          .select('id')
          .eq('user_id', _userId!)
          .eq('product_id', pid)
          .maybeSingle();
      if (mounted) setState(() => _isFav = fav != null);
    } catch (_) {}
  }

  Future<void> _toggleFav() async {
    final pid = int.tryParse(widget.product['id']?.toString() ?? '');
    if (pid == null || _userId == null) {
      Get.snackbar(
        '',
        'Only real products can be saved.',
        backgroundColor: _kGreen,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        borderRadius: 14,
      );
      return;
    }
    setState(() {
      _favLoading = true;
      _isFav = !_isFav;
    });
    HapticFeedback.selectionClick();
    try {
      if (_isFav) {
        await _supabase.from('favourite').insert({
          'user_id': _userId!,
          'product_id': pid,
        });
        Get.snackbar(
          '',
          'Saved to favourites ❤️',
          backgroundColor: _kPink,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          borderRadius: 14,
          duration: const Duration(seconds: 2),
        );
      } else {
        await _supabase
            .from('favourite')
            .delete()
            .eq('user_id', _userId!)
            .eq('product_id', pid);
      }
    } catch (_) {
      setState(() => _isFav = !_isFav);
    } finally {
      if (mounted) setState(() => _favLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _currentProduct;
    final imageUrl = p['image_url'] ?? p['image'] ?? '';
    final name = p['name'] ?? 'Product';
    final price = p['price'];
    final category = p['category'] ?? p['cat'] ?? '';

    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: _kGreen,
            leading: GestureDetector(
              onTap: () => Get.back(),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
            actions: [
              GestureDetector(
                onTap: _toggleFav,
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _favLoading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          _isFav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _isFav ? _kPink : Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: _kGreen.withValues(alpha: 0.08),
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit
                            .contain, // never crops or over-zooms, whatever the window size
                        placeholder: (_, __) => Container(
                          color: _kGreen.withValues(alpha: 0.15),
                          child: const Center(
                            child: CircularProgressIndicator(color: _kGreen),
                          ),
                        ),
                        errorWidget: (_, __, ___) =>
                            _imagePlaceholder(category),
                      )
                    : _imagePlaceholder(category),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Category chip ──
                  if (category.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        category,
                        style: const TextStyle(
                          color: _kGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ── Name ──
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // ── Star rating ──
                  Row(
                    children: [
                      ...List.generate(
                        5,
                        (i) => Icon(
                          i < _rating.floor()
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: _kSaffron,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _kText,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '($_reviewCount reviews)',
                        style: const TextStyle(fontSize: 12, color: _kTextSub),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── Price ──
                  Text(
                    'PKR $price',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: _kSaffron,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Shop name + location map ──
                  Obx(() {
                    final vendorId = p['vendor_id']?.toString() ?? '';
                    final info = vendorId.isNotEmpty
                        ? vendorInfoCtrl.infoFor(vendorId)
                        : null;
                    if (info == null || info.storeName.isEmpty)
                      return const SizedBox.shrink();

                    final pos = vendorInfoCtrl.customerPosition.value;
                    final nearest = info.nearestBranch(
                      pos?.latitude,
                      pos?.longitude,
                    );
                    final mapBranch =
                        nearest?.branch ??
                        (info.branches.isNotEmpty ? info.branches.first : null);
                    final hasCoords =
                        mapBranch?.latitude != null &&
                        mapBranch?.longitude != null;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: _kGreen.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.storefront_rounded,
                                    color: _kGreen,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        info.storeName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: _kText,
                                        ),
                                      ),
                                      if (mapBranch != null &&
                                          mapBranch.address.isNotEmpty)
                                        Text(
                                          nearest != null
                                              ? '${mapBranch.address} • ${nearest.distanceKm.toStringAsFixed(1)} km away'
                                              : mapBranch.address,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: _kTextSub,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (hasCoords)
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(16),
                              ),
                              child: SizedBox(
                                height: 150,
                                child: IgnorePointer(
                                  // small preview map — not meant to be panned/zoomed inline
                                  child: FlutterMap(
                                    options: MapOptions(
                                      initialCenter: LatLng(
                                        mapBranch!.latitude!,
                                        mapBranch.longitude!,
                                      ),
                                      initialZoom: 15,
                                    ),
                                    children: [
                                      TileLayer(
                                        urlTemplate:
                                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                        userAgentPackageName:
                                            'com.example.tezrider',
                                      ),
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: LatLng(
                                              mapBranch.latitude!,
                                              mapBranch.longitude!,
                                            ),
                                            width: 36,
                                            height: 36,
                                            child: const Icon(
                                              Icons.location_on_rounded,
                                              color: _kGreen,
                                              size: 36,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),

                  // ── Description ──
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p['description'] ??
                        p['desc'] ??
                        'No description available.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: _kTextSub,
                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ── Reviews section ──
                  _buildReviewsSection(),

                  const SizedBox(height: 32),

                  StockIndicator(product: p),
                  if (_stockError != null)
                    TextButton(
                      onPressed: _refreshStock,
                      child: Text(_stockError!),
                    ),
                  // ── Add to Cart button ──
                  Obx(() {
                    final inCart = cartCtrl.cartItems.any(
                      (e) => e['name'] == name,
                    );
                    return SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed:
                            !_stockLoading &&
                                _stockError == null &&
                                ProductStock(p).purchasable &&
                                !cartCtrl.checking.contains(p['id'].toString())
                            ? () async {
                                print("========== ADD TO CART ==========");
                                print("Product ID: ${p['id']}");
                                print("Vendor ID: ${p['vendor_id']}");
                                print("Complete Product: $p");

                                final added = await cartCtrl.addItem({
                                  'name': name,
                                  'price': price,
                                  'image_url': imageUrl,
                                  'vendor_id':
                                      p['vendor_id']?.toString() ?? '1',
                                  'product_id': p['id'],
                                });
                                if (!added) {
                                  Get.snackbar(
                                    'Cart',
                                    cartCtrl.lastError.value,
                                  );
                                  return;
                                }
                                HapticFeedback.mediumImpact();
                                Get.snackbar(
                                  '',
                                  '$name added to cart! 🛒',
                                  titleText: const SizedBox.shrink(),
                                  messageText: Text(
                                    '$name added to cart! 🛒',
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
                                  icon: const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                );
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: inCart ? _kGreenL : _kGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              inCart
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.add_shopping_cart_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              inCart ? 'Add Another' : 'Add to Cart',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reviews Section ──────────────────────────────────────────────────────
  Widget _buildReviewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Customer Reviews',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _kText,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kSaffron.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, color: _kSaffron, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${_rating.toStringAsFixed(1)} / 5',
                    style: const TextStyle(
                      color: _kSaffron,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_ratingError != null) Text(_ratingError!),
        if (_ratingError == null && _reviews.isEmpty)
          const Text('No reviews yet.'),
        ..._reviews.take(3).map(_buildReviewCard),
      ],
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final reviewer = review['reviewer'] as String? ?? 'Customer';
    final avatar =
        review['avatar'] as String? ??
        (reviewer.isNotEmpty ? reviewer[0].toUpperCase() : 'C');
    final rating = (review['rating'] as num?)?.toInt() ?? 5;
    final comment = review['comment'] as String? ?? '';
    final date = review['date'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _kGreen.withValues(alpha: 0.12),
                child: Text(
                  avatar,
                  style: const TextStyle(
                    color: _kGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reviewer,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _kText,
                      ),
                    ),
                    Text(
                      date,
                      style: const TextStyle(fontSize: 11, color: _kTextSub),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                    color: _kSaffron,
                    size: 13,
                  ),
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment,
              style: const TextStyle(
                fontSize: 13,
                color: _kTextSub,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _imagePlaceholder(String category) {
    const emojis = {
      'Food': '🍔',
      'Grocery': '🥦',
      'Pharmacy': '💊',
      'Thrift': '👗',
      'Preloved': '♻️',
      'Tailoring': '✂️',
    };
    return Container(
      color: _kGreen.withValues(alpha: 0.10),
      child: Center(
        child: Text(
          emojis[category] ?? '🛍️',
          style: const TextStyle(fontSize: 72),
        ),
      ),
    );
  }
}
