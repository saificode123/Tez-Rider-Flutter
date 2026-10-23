import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


const _kPurple  = Color(0xFF1B5E20);
const _kBg      = Color(0xFFF8F7FF);
const _kCard    = Color(0xFFFFFFFF);
const _kText    = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);
const _kGreen   = Color(0xFF10B981);
const _kSaffron = Color(0xFFF59E0B);
const _kPink    = Color(0xFFEC4899);
const _kTeal    = Color(0xFF06B6D4);

class VendorAnalyticsScreen extends StatefulWidget {
  const VendorAnalyticsScreen({super.key});
  @override
  State<VendorAnalyticsScreen> createState() => _VendorAnalyticsScreenState();
}

class _VendorAnalyticsScreenState extends State<VendorAnalyticsScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _fetching = false;
  String? _error;
  double _totalRevenue  = 0;
  int    _totalOrders   = 0;
  int    _pendingCount  = 0;
  int    _acceptedCount = 0;
  int    _deliveredCount = 0;
  int    _cancelledCount = 0;
  List<Map<String, dynamic>> _topProducts = [];
  int? _vendorId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_fetching) return;
    _fetching = true;
    setState(() { _loading = true; _error = null; });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw StateError('Sign in required');

      final rec = await _supabase.from('users').select('id').eq('email', user.email!).maybeSingle();
      if (rec == null) throw StateError('Profile unavailable');
      _vendorId = rec['id'];

      final orders = await _supabase
          .from('vendor_orders')
          .select('id, sub_total, status')
          .eq('vendor_id', _vendorId!) as List;

      _totalOrders    = orders.length;
      _totalRevenue   = orders.where((o) => o['status'] == 'delivered').fold(0.0, (s, o) => s + ((o['sub_total'] as num?) ?? 0));
      _pendingCount   = orders.where((o) => o['status'] == 'pending').length;
      _acceptedCount  = orders.where((o) => o['status'] == 'accepted').length;
      _deliveredCount = orders.where((o) => o['status'] == 'delivered').length;
      _cancelledCount = orders.where((o) => o['status'] == 'cancelled').length;

      _topProducts = [];
      final orderIds = orders.map((o) => o['id']).toList();
      if (orderIds.isNotEmpty) {
        final items = await _supabase
            .from('order_items')
            .select('product_id, quantity, products(name, image_url, category)')
            .inFilter('vendor_order_id', orderIds) as List;

        final Map<dynamic, Map<String, dynamic>> agg = {};
        for (final item in items) {
          final pid  = item['product_id'];
          final qty  = (item['quantity'] as num?)?.toInt() ?? 1;
          final prod = item['products'] as Map<String, dynamic>? ?? {};
          if (!agg.containsKey(pid)) {
            agg[pid] = {
              'name': prod['name'] ?? 'Unknown',
              'category': prod['category'] ?? '',
              'total_qty': 0,
            };
          }
          agg[pid]!['total_qty'] = (agg[pid]!['total_qty'] as int) + qty;
        }
        final sorted = agg.values.toList()
          ..sort((a, b) => (b['total_qty'] as int).compareTo(a['total_qty'] as int));
        _topProducts = sorted.take(5).toList();
      }


    } catch (_) {
      _error = 'Analytics could not be loaded. Retry when connected.';
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPurple,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Analytics',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2))
          : _error != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!),
              TextButton(onPressed: _loadData, child: const Text('Retry')),
            ]))
          : RefreshIndicator(
              color: _kPurple,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  Row(children: [
                    _statCard('Total Revenue', 'PKR ${_totalRevenue.toStringAsFixed(0)}',
                        Icons.account_balance_wallet_rounded, _kGreen),
                    const SizedBox(width: 12),
                    _statCard('Total Orders', '$_totalOrders',
                        Icons.shopping_bag_rounded, _kPurple),
                  ]),

                  const SizedBox(height: 20),

                  _sectionTitle('Orders by Status'),
                  const SizedBox(height: 12),
                  _card(child: Column(children: [
                    _statusRow('Pending',   _pendingCount,   _kSaffron, Icons.hourglass_empty_rounded),
                    const Divider(height: 20),
                    _statusRow('Accepted',  _acceptedCount,  _kTeal,    Icons.check_circle_outline_rounded),
                    const Divider(height: 20),
                    _statusRow('Delivered', _deliveredCount, _kGreen,   Icons.local_shipping_rounded),
                    const Divider(height: 20),
                    _statusRow('Cancelled', _cancelledCount, _kPink,    Icons.cancel_outlined),
                  ])),

                  const SizedBox(height: 20),

                  if (_totalOrders > 0) ...[
                    _sectionTitle('Fulfillment Rate'),
                    const SizedBox(height: 12),
                    _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Expanded(child: Text('Orders delivered successfully',
                            style: TextStyle(color: _kTextSub, fontSize: 13))),
                        Text('${(_deliveredCount / _totalOrders * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(color: _kGreen, fontWeight: FontWeight.w900, fontSize: 15)),
                      ]),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _totalOrders > 0 ? _deliveredCount / _totalOrders : 0,
                          minHeight: 10,
                          backgroundColor: _kGreen.withValues(alpha: 0.12),
                          valueColor: const AlwaysStoppedAnimation<Color>(_kGreen),
                        ),
                      ),
                    ])),
                    const SizedBox(height: 20),
                  ],

                  if (_topProducts.isNotEmpty) ...[
                    _sectionTitle('Top Products'),
                    const SizedBox(height: 12),
                    _card(child: Column(
                      children: _topProducts.asMap().entries.map((e) {
                        final i   = e.key;
                        final p   = e.value;
                        final max = (_topProducts.first['total_qty'] as int).toDouble();
                        final qty = (p['total_qty'] as int).toDouble();

                        return Padding(
                          padding: EdgeInsets.only(bottom: i < _topProducts.length - 1 ? 16 : 0),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  color: _kPurple.withValues(alpha: 0.10),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(child: Text('${i + 1}',
                                    style: const TextStyle(color: _kPurple, fontSize: 12, fontWeight: FontWeight.w800))),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(p['name'] as String,
                                  style: const TextStyle(color: _kText, fontWeight: FontWeight.w700, fontSize: 13),
                                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Text('${p['total_qty']} sold',
                                  style: const TextStyle(color: _kTextSub, fontSize: 11, fontWeight: FontWeight.w600)),
                            ]),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: max > 0 ? qty / max : 0,
                                minHeight: 6,
                                backgroundColor: _kPurple.withValues(alpha: 0.08),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  [_kPurple, _kTeal, _kGreen, _kSaffron, _kPink][i % 5],
                                ),
                              ),
                            ),
                          ]),
                        );
                      }).toList(),
                    )),
                    const SizedBox(height: 20),
                  ],

                  if (_totalOrders == 0)
                    Center(child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(children: [
                        const Text('📊', style: TextStyle(fontSize: 60)),
                        const SizedBox(height: 16),
                        const Text('No data yet',
                            style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        const Text('Analytics will appear once you receive orders.',
                            style: TextStyle(color: _kTextSub, fontSize: 14),
                            textAlign: TextAlign.center),
                      ]),
                    )),
                ]),
              ),
            ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 14),
        Text(value,
            style: const TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w900),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        Text(title, style: const TextStyle(color: _kTextSub, fontSize: 12)),
      ]),
    ));
  }

  Widget _statusRow(String label, int count, Color color, IconData icon) {
    return Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700, fontSize: 14))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)),
      ),
    ]);
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(color: _kText, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.2));
  }
}
