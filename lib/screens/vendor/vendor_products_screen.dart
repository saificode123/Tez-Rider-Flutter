import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../widgets/stock_adjustment_dialog.dart';
import '../../services/inventory_service.dart';
import '../../widgets/stock_indicator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'product_form_screen.dart';

const _kPurple = Color(0xFF1B5E20);
const _kBg = Color(0xFFF8F7FF);

class VendorProductsScreen extends StatefulWidget {
  const VendorProductsScreen({super.key});
  @override
  State<VendorProductsScreen> createState() => _VendorProductsScreenState();
}

class _VendorProductsScreenState extends State<VendorProductsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  int? _vendorId;
  bool _hasMore = false;
  bool _loadingMore = false;
  String? _loadError;
  final Set<int> _deleting = {};

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts({bool more = false}) async {
    if (_loadingMore) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _loadError = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw StateError('Sign in again to view your inventory.');
      }
      final rec = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .maybeSingle();
      if (rec == null) throw StateError('Vendor account was not found.');
      _vendorId = (rec['id'] as num).toInt();
      var query = _supabase
          .from('products')
          .select()
          .eq('vendor_id', _vendorId!);
      if (more && _products.isNotEmpty) {
        query = query.lt('id', _products.last['id']);
      }
      final rows = await query
          .order('id', ascending: false)
          .limit(30)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _products = more
            ? [..._products, ...rows]
            : List<Map<String, dynamic>>.from(rows);
        _hasMore = rows.length == 30;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _loadError = e is StateError
              ? e.message.toString()
              : 'Inventory could not be loaded. Retry when connected.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _adjustStock(Map<String, dynamic> product) async {
    final rows = await InventoryApi.read([(product['id'] as num).toInt()]);
    if (!mounted) return;
    if (rows.length != 1) {
      Get.snackbar('Inventory', 'This product is no longer available.');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockAdjustmentDialog(product: rows.single),
    );
    if (mounted) await _loadProducts();
  }

  Future _toggleAvailability(Map<String, dynamic> p) async {
    try {
      final newVal = !(p['is_available'] ?? true);

      await _supabase
          .from('products')
          .update({'is_available': newVal})
          .eq('id', p['id']);

      await _loadProducts();
    } catch (_) {
      Get.snackbar(
        'Availability not confirmed',
        'Refresh your inventory and retry when connected.',
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final id = (p['id'] as num).toInt();
    if (!_deleting.add(id)) return;
    setState(() {});
    try {
      final removed = await _supabase
          .rpc(
            'final2_delete_product',
            params: {
              'p_product_id': id,
              'p_expected_version': p['stock_version'],
            },
          )
          .timeout(const Duration(seconds: 12));
      if (removed is! Map ||
          removed['code'] != 'DELETED' ||
          removed['product_id'] != id) {
        throw StateError(switch (removed is Map ? removed['code'] : null) {
          'VERSION_CHANGED' =>
            'This product or its stock changed. Refresh before deleting.',
          'PRODUCT_IN_USE' =>
            'This product belongs to an order and cannot be removed. Turn off availability instead.',
          'NOT_FOUND' =>
            'This product is no longer present. Refresh your inventory.',
          _ => 'Deletion was not confirmed. Refresh your inventory.',
        });
      }
      if (!mounted) return;
      setState(() => _products.removeWhere((row) => row['id'] == id));
      Get.snackbar(
        'Deleted',
        '"${p['name']}" removed.',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Deletion not confirmed',
          e is StateError
              ? e.message.toString()
              : 'Access or connectivity changed. Refresh your inventory and retry.',
        );
      }
    } finally {
      _deleting.remove(id);
      if (mounted) setState(() {});
    }
  }

  void _openForm({Map<String, dynamic>? existing}) async {
    await Get.to(
      () => ProductFormScreen(vendorId: _vendorId, existing: existing),
    );
    _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
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
          'My Products',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadProducts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kPurple,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Add Product',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2),
            )
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!),
                  TextButton(
                    onPressed: _loadProducts,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _products.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('📦', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  const Text(
                    'No products yet',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A1340),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap + to add your first product.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: _kPurple,
              onRefresh: _loadProducts,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: _products.length + (_hasMore ? 1 : 0),
                itemBuilder: (_, i) => i == _products.length
                    ? TextButton(
                        onPressed: _loadingMore
                            ? null
                            : () => _loadProducts(more: true),
                        child: Text(_loadingMore ? 'Loading…' : 'Load more'),
                      )
                    : _buildCard(_products[i]),
              ),
            ),
    );
  }

  Widget _buildCard(Map<String, dynamic> p) {
    final available = p['is_available'] ?? true;
    final imageUrl = p['image_url'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
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
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _imgPlaceholder(p['category']),
                    errorWidget: (_, __, ___) => _imgPlaceholder(p['category']),
                  )
                : _imgPlaceholder(p['category']),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['name'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF1A1340),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  StockIndicator(product: p, vendor: true),
                  Text(
                    'PKR ${p['price']}',
                    style: const TextStyle(
                      color: _kPurple,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
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
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Adjust stock',
                icon: const Icon(Icons.inventory_2_outlined),
                onPressed: () async {
                  try {
                    await _adjustStock(p);
                  } catch (_) {
                    Get.snackbar(
                      'Inventory',
                      'Could not refresh this product. Retry when connected.',
                    );
                  }
                },
              ),
              Switch(
                value: available,
                activeThumbColor: Colors.white,
                activeTrackColor: _kPurple,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => _toggleAvailability(p),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: _kPurple,
                    ),
                    onPressed: () => _openForm(existing: p),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                    onPressed: _deleting.contains((p['id'] as num).toInt())
                        ? null
                        : () => showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: const Text(
                                'Delete?',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              content: Text(
                                'Remove "${p['name']}" permanently?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _delete(p);
                                  },
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _imgPlaceholder(String? cat) {
    const map = {
      'Food': '🍔',
      'Grocery': '🥦',
      'Pharmacy': '💊',
      'Thrift': '👗',
      'Tailoring': '✂️',
      'Preloved': '♻️',
    };
    return Container(
      width: 80,
      height: 80,
      color: _kPurple.withValues(alpha: 0.07),
      child: Center(
        child: Text(map[cat] ?? '📦', style: const TextStyle(fontSize: 28)),
      ),
    );
  }
}
