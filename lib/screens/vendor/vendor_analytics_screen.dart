import 'package:flutter/material.dart';
import '../../services/vendor_report_service.dart';
import '../../widgets/role_access_gate.dart';

const _kPurple = Color(0xFF1B5E20);
const _kBg = Color(0xFFF8F7FF);
const _kCard = Color(0xFFFFFFFF);
const _kText = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);
const _kGreen = Color(0xFF10B981);
const _kSaffron = Color(0xFFF59E0B);
const _kPink = Color(0xFFEC4899);
const _kTeal = Color(0xFF06B6D4);

class VendorAnalyticsScreen extends StatelessWidget {
  const VendorAnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context) => RoleAccessGate(
    role: 'vendor',
    builder: (_) => const VendorAnalyticsBody(),
  );
}

class VendorAnalyticsBody extends StatefulWidget {
  const VendorAnalyticsBody({super.key, this.service});
  final VendorReportService? service;
  @override
  State<VendorAnalyticsBody> createState() => _VendorAnalyticsScreenState();
}

class _VendorAnalyticsScreenState extends State<VendorAnalyticsBody> {
  late final _service = widget.service ?? VendorReportService();
  final _transactions = <Map<String, dynamic>>[];
  VendorReport? _report;
  bool _moreFailed = false;
  int _reviewCount = 0;

  bool _loading = true;
  bool _fetching = false;
  String? _error;
  double _totalRevenue = 0;
  int _totalOrders = 0;
  int _pendingCount = 0;
  int _acceptedCount = 0;
  int _deliveredCount = 0;
  int _cancelledCount = 0;
  List<Map<String, dynamic>> _topProducts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_fetching) return;
    _fetching = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await _service.load();
      if (!mounted) return;
      _report = report;
      _transactions
        ..clear()
        ..addAll(report.items);
      _totalOrders = report.summary['total_orders'];
      _totalRevenue = (report.summary['delivered_sales'] as num).toDouble();
      _deliveredCount = report.summary['delivered_orders'];
      _reviewCount = report.summary['amounts_requiring_review'];
      final counts = report.summary['status_counts'] as Map;
      _pendingCount = counts['pending'] ?? 0;
      _acceptedCount = counts['accepted'] ?? 0;
      _cancelledCount = (counts['cancelled'] ?? 0) + (counts['rejected'] ?? 0);
      _topProducts = report.products
          .map((p) => {...p, 'total_qty': p['quantity']})
          .toList();
      _moreFailed = false;
    } catch (_) {
      _error = 'Analytics could not be loaded. Retry when connected.';
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_fetching || _report?.cursor == null) return;
    setState(() {
      _fetching = true;
      _moreFailed = false;
    });
    try {
      final report = await _service.load(_report!.cursor);
      if (!mounted) return;
      if (report.vendorId != _report!.vendorId) {
        throw StateError('Account changed');
      }
      final keys = _transactions
          .map((r) => '${r['order_id']}:${r['vendor_order_id']}')
          .toSet();
      setState(() {
        _transactions.addAll(
          report.items.where(
            (r) => keys.add('${r['order_id']}:${r['vendor_order_id']}'),
          ),
        );
        _report = report;
      });
    } catch (_) {
      if (mounted) setState(() => _moreFailed = true);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  String _money(dynamic value) => value is num
      ? 'PKR ${value.toStringAsFixed(2)}'
      : 'Amount requires review';

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
          'Analytics',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _fetching ? null : _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: _fetching ? null : _loadData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: _kPurple,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statCard(
                          'Delivered sales',
                          'PKR ${_totalRevenue.toStringAsFixed(2)}',
                          Icons.account_balance_wallet_rounded,
                          _kGreen,
                        ),
                        const SizedBox(width: 12),
                        _statCard(
                          'Total Orders',
                          '$_totalOrders',
                          Icons.shopping_bag_rounded,
                          _kPurple,
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      'Gross delivered item sales, not net profit or a cash payout. Shared refunds have no recorded vendor allocation.',
                    ),
                    if (_reviewCount > 0)
                      Text('$_reviewCount amounts require Admin review.'),
                    _sectionTitle('Orders by Status'),
                    const SizedBox(height: 12),
                    _card(
                      child: Column(
                        children: [
                          _statusRow(
                            'Pending',
                            _pendingCount,
                            _kSaffron,
                            Icons.hourglass_empty_rounded,
                          ),
                          const Divider(height: 20),
                          _statusRow(
                            'Accepted',
                            _acceptedCount,
                            _kTeal,
                            Icons.check_circle_outline_rounded,
                          ),
                          const Divider(height: 20),
                          _statusRow(
                            'Delivered',
                            _deliveredCount,
                            _kGreen,
                            Icons.local_shipping_rounded,
                          ),
                          const Divider(height: 20),
                          _statusRow(
                            'Cancelled',
                            _cancelledCount,
                            _kPink,
                            Icons.cancel_outlined,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    if (_totalOrders > 0) ...[
                      _sectionTitle('Fulfillment Rate'),
                      const SizedBox(height: 12),
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Orders delivered successfully',
                                    style: TextStyle(
                                      color: _kTextSub,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${(_deliveredCount / _totalOrders * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    color: _kGreen,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: _totalOrders > 0
                                    ? _deliveredCount / _totalOrders
                                    : 0,
                                minHeight: 10,
                                backgroundColor: _kGreen.withValues(
                                  alpha: 0.12,
                                ),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  _kGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (_topProducts.isNotEmpty) ...[
                      _sectionTitle('Top Delivered Products'),
                      const SizedBox(height: 12),
                      _card(
                        child: Column(
                          children: _topProducts.asMap().entries.map((e) {
                            final i = e.key;
                            final p = e.value;
                            final max = (_topProducts.first['total_qty'] as int)
                                .toDouble();
                            final qty = (p['total_qty'] as int).toDouble();

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: i < _topProducts.length - 1 ? 16 : 0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: _kPurple.withValues(
                                            alpha: 0.10,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${i + 1}',
                                            style: const TextStyle(
                                              color: _kPurple,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          p['name'] as String,
                                          style: const TextStyle(
                                            color: _kText,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '${p['total_qty']} sold',
                                        style: const TextStyle(
                                          color: _kTextSub,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: max > 0 ? qty / max : 0,
                                      minHeight: 6,
                                      backgroundColor: _kPurple.withValues(
                                        alpha: 0.08,
                                      ),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        [
                                          _kPurple,
                                          _kTeal,
                                          _kGreen,
                                          _kSaffron,
                                          _kPink,
                                        ][i % 5],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    _sectionTitle('Per-order breakdown'),
                    for (final row in _transactions)
                      Card(
                        child: ExpansionTile(
                          key: ValueKey(
                            'report-${row['order_id']}-${row['vendor_order_id']}',
                          ),
                          title: Text('Order #${row['order_id']}'),
                          subtitle: Text(
                            '${row['portion_status']} / ${row['order_status']} — ${_money(row['subtotal'])}${row['delivered'] ? ' (delivered sales)' : ' (excluded from delivered sales)'}',
                          ),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          childrenPadding: const EdgeInsets.all(12),
                          children: [
                            Text('${row['created_at'] ?? 'Date unavailable'}'),
                            if (row['source'] == 'legacy_order')
                              const Text(
                                'Legacy direct order; item breakdown may be unavailable.',
                              ),
                            for (final item in row['items'] as List)
                              Text(
                                '${item['name']} × ${item['quantity']} at ${_money(item['unit_price'])}',
                              ),
                            if (row['items_require_review'] == true)
                              const Text(
                                'Historical item count requires Admin review.',
                              ),
                            Text(
                              'Payment: ${(row['payment'] as Map)['state'] ?? 'Requires Admin review'}',
                            ),
                            for (final refund
                                in ((row['payment'] as Map)['refunds']
                                        as List? ??
                                    []))
                              Text(
                                'Whole-order refund: ${refund['state']} (vendor allocation not recorded)',
                              ),
                          ],
                        ),
                      ),
                    if (_moreFailed)
                      const Text('More orders could not be loaded.'),
                    if (_report?.cursor != null)
                      TextButton(
                        onPressed: _fetching ? null : _loadMore,
                        child: Text(
                          _moreFailed
                              ? 'Retry more orders'
                              : 'Load more orders',
                        ),
                      ),
                    if (_fetching && !_loading)
                      const Center(child: CircularProgressIndicator()),

                    if (_totalOrders == 0)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Column(
                            children: [
                              const Text('📊', style: TextStyle(fontSize: 60)),
                              const SizedBox(height: 16),
                              const Text(
                                'No data yet',
                                style: TextStyle(
                                  color: _kText,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Analytics will appear once you receive orders.',
                                style: TextStyle(
                                  color: _kTextSub,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _kPurple.withValues(alpha: 0.07),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(
                color: _kText,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(title, style: const TextStyle(color: _kTextSub, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, int count, Color color, IconData icon) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: _kText,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _kText,
        fontSize: 17,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.2,
      ),
    );
  }
}
