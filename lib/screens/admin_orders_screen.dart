import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/role_access_gate.dart';
import '../widgets/order_payment_panel.dart';

class AdminOrdersScreen extends StatelessWidget {
  const AdminOrdersScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      RoleAccessGate(role: 'admin', builder: (_) => const _AdminOrdersBody());
}

class _AdminOrdersBody extends StatefulWidget {
  const _AdminOrdersBody();
  @override
  State<_AdminOrdersBody> createState() => _AdminOrdersBodyState();
}

class _AdminOrdersBodyState extends State<_AdminOrdersBody> {
  final _rows = <Map<String, dynamic>>[];
  bool _loading = false, _hasMore = true, _failedMore = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || (more && !_hasMore)) return;
    setState(() {
      _loading = true;
      _error = null;
      _failedMore = more;
    });
    try {
      var query = Supabase.instance.client
          .from('orders')
          .select('id,order_status,amount,payment_method,created_at');
      if (more && _rows.isNotEmpty) query = query.lt('id', _rows.last['id']);
      final rows = await query
          .order('id', ascending: false)
          .limit(30)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        if (!more) _rows.clear();
        final ids = _rows.map((row) => row['id']).toSet();
        _rows.addAll(rows.where((row) => ids.add(row['id'])));
        _hasMore = rows.length == 30;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Orders could not be refreshed. Retry when connected.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Orders and cash records'),
      actions: [
        IconButton(
          onPressed: _loading ? null : () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
            onPressed: _loading ? null : () => _load(more: _failedMore),
            child: const Text('Retry orders'),
          ),
        ],
        if (!_loading && _error == null && _rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No order records.'),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _rows.length + (_hasMore && _rows.isNotEmpty ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _rows.length) {
                return TextButton(
                  onPressed: _loading ? null : () => _load(more: true),
                  child: const Text('Load more orders'),
                );
              }
              final order = _rows[index];
              final amount = order['amount'];
              return ListTile(
                title: Text('Order #${order['id']} · ${order['order_status']}'),
                subtitle: Text(
                  '${order['payment_method'] ?? 'Method unavailable'} · ${amount is num ? 'PKR ${amount.toStringAsFixed(2)}' : 'Amount unavailable'}',
                ),
                trailing: const Icon(Icons.receipt_long),
                onTap: () => showOrderPayment(
                  context,
                  order['id'] as int,
                  allowCollection: true,
                  allowRefund: true,
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
