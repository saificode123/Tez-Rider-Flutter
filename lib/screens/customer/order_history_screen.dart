import '../../theme/app_theme.dart';
import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'dart:async';
import '../../widgets/order_timeout_summary.dart';
import 'order_detail_screen.dart';
import '../../widgets/invoice_button.dart';
import '../../widgets/order_payment_panel.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rating_screen.dart';
import '../../services/dispute_service.dart';
import 'dispute_screen.dart';
import '../map_screen.dart';

const _kPurple = AppColors.primaryDark;
const _kBg = AppColors.bgLight;
const _kCard = Color(0xFFFFFFFF);
const _kText = AppColors.textPrimary;
const _kTextSub = AppColors.textSecondary;
const _kGreen = Color(0xFF10B981);
const _kPink = Color(0xFFEC4899);
const _kTeal = Color(0xFF06B6D4);
const _kSaffron = Color(0xFFF59E0B);

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  bool _hasMore = true;
  int _generation = 0;
  String? _account;
  StreamSubscription<AuthState>? _authChanges;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _account = _supabase.auth.currentUser?.id;
    _authChanges = _supabase.auth.onAuthStateChange.listen((state) {
      if (state.session?.user.id != _account) {
        _account = state.session?.user.id;
        ++_generation;
        if (!mounted) return;
        setState(() {
          _orders.clear();
          _loading = false;
          _hasMore = false;
          _error = 'Sign in again to view your orders.';
        });
        if (_account != null) _loadOrders();
      }
    });
    _loadOrders();
  }

  Future<void> _loadOrders({bool more = false}) async {
    if (more && _loading) return;
    final request = ++_generation;
    final account = _supabase.auth.currentUser?.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = List<Map<String, dynamic>>.from(
        await _supabase
                .rpc(
                  'fr25_order_history',
                  params: {
                    'p_before': more && _orders.isNotEmpty
                        ? _orders.last['id']
                        : null,
                  },
                )
                .timeout(const Duration(seconds: 15))
            as List,
      );
      if (mounted &&
          request == _generation &&
          account == _supabase.auth.currentUser?.id) {
        setState(() {
          if (!more) _orders.clear();
          _orders.addAll(data);
          _hasMore = data.length == 30;
        });
      }
    } catch (_) {
      if (mounted &&
          request == _generation &&
          account == _supabase.auth.currentUser?.id) {
        setState(() => _error = 'Orders could not be loaded. Retry.');
      }
    } finally {
      if (mounted &&
          request == _generation &&
          account == _supabase.auth.currentUser?.id) {
        setState(() {
          _loading = false;
          _fadeCtrl.forward(from: 0);
        });
      }
    }
  }

  Animation<double> _itemAnimation(int index) {
    final start = (index * 0.06).clamp(0.0, 0.7);
    final end = (start + 0.4).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _fadeCtrl,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
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
        title: Text(
          "Order History".tr,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loading ? null : () => _loadOrders(),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
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
                    Text(_error!.uiMessage),
                    TextButton(
                      onPressed: () => _loadOrders(),
                      child: Text("Retry".tr),
                    ),
                  ],
                ),
              )
            : _orders.isEmpty
            ? _buildEmpty()
            : RefreshIndicator(
                color: _kPurple,
                onRefresh: () => _loadOrders(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  itemCount: _orders.length + (_hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _orders.length) {
                      return TextButton(
                        onPressed: () => _loadOrders(more: true),
                        child: Text("Load more orders".tr),
                      );
                    }
                    final animation = _itemAnimation(i);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(animation),
                        child: _buildOrderCard(_orders[i]),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset(
            'assets/lottie/delivery_cyclist.json',
            width: 220,
            height: 220,
          ),
          const SizedBox(height: 12),
          Text(
            "No orders yet".tr,
            style: TextStyle(
              color: _kText,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Your order history will appear here.".tr,
            style: TextStyle(color: _kTextSub, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['order_status'] ?? 'placed';
    final amount = order['amount'] ?? 0;
    final rawId = order['id']?.toString() ?? '';
    final id = rawId.isEmpty
        ? '--------'
        : rawId.substring(0, rawId.length < 8 ? rawId.length : 8);
    final createdAt = order['created_at'] != null
        ? DateTime.tryParse(order['created_at'].toString())
        : null;
    final dateStr = createdAt != null
        ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
        : '';

    final statusData = {
      'delivered': {'color': _kGreen, 'icon': '✅', 'label': 'Delivered'},
      'cancelled': {'color': _kPink, 'icon': '❌', 'label': 'Cancelled'},
      'on_the_way': {'color': _kTeal, 'icon': '🏍️', 'label': 'On the Way'},
      'accepted': {'color': _kSaffron, 'icon': '🍳', 'label': 'Preparing'},
      'placed': {'color': _kPurple, 'icon': '⏳', 'label': 'Placed'},
    };
    final sd = statusData[status] ?? statusData['placed']!;
    final col = sd['color'] as Color;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: col.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      sd['icon'] as String,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Order #@slot0end".uiTr({"slot0end": (id).toString()}),
                        style: const TextStyle(
                          color: _kText,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "PKR @slot0end  •  @slot1end".uiTr({
                          "slot0end": (amount).toString(),
                          "slot1end": (dateStr).toString(),
                        }),
                        style: TextStyle(color: _kTextSub, fontSize: 12),
                      ),
                      OrderTimeoutSummary(order: order),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => Get.to(
                    () => OrderDetailScreen(orderId: order['id'] as int),
                  ),
                  child: Text("Order details".tr),
                ),
                InvoiceButton(orderId: order['id'] as int),
                TextButton(
                  onPressed: () =>
                      showOrderPayment(context, order['id'] as int),
                  child: Text("Payment / refunds".tr),
                ),
                if (status == 'on_the_way')
                  TextButton(
                    onPressed: () =>
                        Get.to(() => MapScreen(orderId: order['id'] as int)),
                    child: Text("Track location".tr),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: col.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    sd['label'] as String,
                    style: TextStyle(
                      color: col,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (disputeOrderEligible(order, DateTime.now().toUtc()) &&
                    order['dispute_open'] != true)
                  TextButton(
                    onPressed: () => Get.to(
                      () => DisputeScreen(orderId: order['id'] as int),
                    ),
                    child: Text("Dispute".tr),
                  ),
                if (status == 'delivered') ...[
                  GestureDetector(
                    onTap: () =>
                        Get.to(() => RatingScreen(orderId: order['id'] as int)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _kSaffron.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, color: _kSaffron, size: 12),
                          SizedBox(width: 3),
                          Text(
                            "Rate".tr,
                            style: TextStyle(
                              color: _kSaffron,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_authChanges?.cancel());
    _fadeCtrl.dispose();
    super.dispose();
  }
}
