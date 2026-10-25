import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import '../widgets/stock_indicator.dart';
import '../services/inventory_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:async';
import '../services/catalogue_service.dart';
import '../widgets/product_image.dart';
import '../controllers/cart_controller.dart';
import 'product_detail_screen.dart';

const _kPurple = Color(0xFF1B5E20);
const _kBg = Color(0xFFF8F7FF);
const _kCard = Color(0xFFFFFFFF);
const _kText = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);
const _kSaffron = Color(0xFFF59E0B);
const _kGreen = Color(0xFF10B981);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _catalogue = CatalogueService();
  Timer? _debounce;
  List<Map<String, dynamic>> _categories = [];
  bool _categoriesLoading = true, _categoriesFailed = false;
  String? _category;
  bool _hasMore = false, _loadingMore = false;
  Map<String, dynamic>? _cursor;
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();

  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCategories());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _categoriesLoading = true;
      _categoriesFailed = false;
    });
    try {
      final rows = await _catalogue.categories();
      if (mounted) setState(() => _categories = rows);
    } catch (_) {
      if (mounted) setState(() => _categoriesFailed = true);
    } finally {
      if (mounted) setState(() => _categoriesLoading = false);
    }
  }

  void _queueSearch(String query) {
    _debounce?.cancel();
    _request++;
    if (query.trim().isEmpty) {
      unawaited(_search(query));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query, {bool loadMore = false}) async {
    _debounce?.cancel();
    if (loadMore && (_loading || _loadingMore || !_hasMore)) return;
    final request = loadMore ? _request : ++_request;
    final q = query.trim();
    if (q.isEmpty && _category == null) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
        _loadingMore = false;
        _error = null;
        _hasMore = false;
        _cursor = null;
      });
      return;
    }
    setState(() {
      _loading = !loadMore;
      _loadingMore = loadMore;
      _searched = true;
      _error = null;
      if (!loadMore) {
        _hasMore = false;
        _cursor = null;
      }
    });
    try {
      final page = await _catalogue.load(
        query: q,
        category: _category,
        after: loadMore ? _cursor : null,
      );
      if (!mounted || request != _request) return;
      setState(() {
        if (loadMore) {
          final ids = _results.map((p) => p['id']).toSet();
          _results.addAll(page.items.where((p) => ids.add(p['id'])));
        } else {
          _results = page.items;
        }
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(
        () => _error =
            'Search could not be completed. Use up to 120 characters and retry.',
      );
    } finally {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Widget _buildFilters() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
      children: [
        if (_categoriesLoading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(),
          ),
        if (_categoriesFailed)
          TextButton(
            onPressed: _loadCategories,
            child: Text("Retry categories".tr),
          ),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: _category ?? '',
            items: [
              DropdownMenuItem(value: '', child: Text("All categories".tr)),
              ..._categories.map(
                (row) => DropdownMenuItem(
                  value: row['name'] as String,
                  child: Text(
                    row['name'] as String,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              setState(
                () => _category = value?.isNotEmpty == true ? value : null,
              );
              unawaited(_search(_searchCtrl.text));
            },
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
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
        title: TextField(
          controller: _searchCtrl,
          focusNode: _focusNode,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          cursorColor: Colors.white70,
          decoration: InputDecoration(
            hintText: "Search food, groceries, stores...".tr,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.60),
              fontSize: 14,
            ),
            border: InputBorder.none,
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    onPressed: () {
                      _searchCtrl.clear();
                      _search('');
                    },
                  )
                : null,
          ),
          onChanged: _queueSearch,
          onSubmitted: _search,
        ),
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: _kPurple,
                      strokeWidth: 2,
                    ),
                  )
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: () => _search(_searchCtrl.text),
                          child: Text("Retry".tr),
                        ),
                      ],
                    ),
                  )
                : !_searched
                ? _buildSuggestions()
                : _results.isEmpty
                ? _buildEmpty()
                : _buildResults(cart),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    final chips = _categories.map((row) => row['name'] as String).toList();
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Browse Categories".tr,
            style: TextStyle(
              color: _kText,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: chips
                .map(
                  (c) => GestureDetector(
                    onTap: () {
                      setState(() => _category = c);
                      _searchCtrl.clear();
                      _search('');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _kPurple.withValues(alpha: 0.20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _kPurple.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        c,
                        style: const TextStyle(
                          color: _kPurple,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          Text(
            "No results for \"@slot0end\"".uiTr({
              "slot0end": (_searchCtrl.text).toString(),
            }),
            style: const TextStyle(
              color: _kText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Try a different name or category.".tr,
            style: TextStyle(color: _kTextSub, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(CartController cart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            "@slot0end@slot1end result@slot2end".uiTr({
              "slot0end": (_results.length).toString(),
              "slot1end": (_hasMore ? '+' : '').toString(),
              "slot2end": (_results.length == 1 ? '' : 's').toString(),
            }),
            style: const TextStyle(
              color: _kTextSub,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: _results.length + (_hasMore ? 1 : 0),
            itemBuilder: (_, i) => i == _results.length
                ? TextButton(
                    onPressed: _loadingMore
                        ? null
                        : () => _search(_searchCtrl.text, loadMore: true),
                    child: Text(
                      _loadingMore
                          ? "Loading products...".tr
                          : "Load more products".tr,
                    ),
                  )
                : _buildProductTile(_results[i], cart),
          ),
        ),
      ],
    );
  }

  Widget _buildProductTile(Map<String, dynamic> p, CartController cart) {
    final imageUrl = p['image_url'] as String? ?? '';
    final price = p['price'];

    return GestureDetector(
      onTap: () => Get.to(() => ProductDetailScreen(product: p)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _kPurple.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
              child: imageUrl.isNotEmpty
                  ? ProductImage(
                      imageUrl: imageUrl,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(p['category']),
                      errorWidget: (_, __, ___) => _placeholder(p['category']),
                    )
                  : _placeholder(p['category']),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StockIndicator(product: p),
                    Text(
                      p['name'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: _kText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    if ((p['description'] ?? '').isNotEmpty)
                      Text(
                        p['description'],
                        style: const TextStyle(color: _kTextSub, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          "PKR @slot0end".uiTr({
                            "slot0end": (price).toString(),
                          }),
                          style: const TextStyle(
                            color: _kSaffron,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                            p['category'] ?? '',
                            style: const TextStyle(
                              color: _kPurple,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                color: _kPurple,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: ProductStock(p).purchasable
                      ? () async {
                          final added = await cart.addItem({
                            'product_id': p['id'],
                            'name': p['name'],
                            'price': p['price'],
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
                              "slot0end": (p['name']).toString(),
                            }),
                            titleText: const SizedBox.shrink(),
                            messageText: Text(
                              "@slot0end added! 🛒".uiTr({
                                "slot0end": (p['name']).toString(),
                              }),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: _kGreen,
                            snackPosition: SnackPosition.BOTTOM,
                            margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(String? cat) {
    const map = {
      'Food': '🍔',
      'Grocery': '🥦',
      'Pharmacy': '💊',
      'Thrift': '👗',
      'Preloved': '♻️',
      'Tailoring': '✂️',
    };
    return Container(
      width: 80,
      height: 80,
      color: _kPurple.withValues(alpha: 0.08),
      child: Center(
        child: Text(map[cat] ?? '🛍️', style: const TextStyle(fontSize: 28)),
      ),
    );
  }
}
