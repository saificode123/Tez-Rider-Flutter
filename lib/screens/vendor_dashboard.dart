import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:geolocator/geolocator.dart';
import '../controllers/auth_controller.dart';
import '../controllers/vendor_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/vendor_order_rejection.dart';
import 'vendor/vendor_products_screen.dart';
import 'vendor/vendor_analytics_screen.dart';
import 'splash_screen.dart';
import 'customer/help_center_screen.dart';
import 'chat_rooms_screen.dart';
import 'customer/notifications_screen.dart';

/// Safely shortens an id string for display — never crashes on short ids.
String _shortId(dynamic id, [int len = 6]) {
  final s = id?.toString() ?? '------';
  return s.length < len ? s : s.substring(0, len);
}

class VendorDashboard extends StatefulWidget {
  const VendorDashboard({super.key});
  @override
  State<VendorDashboard> createState() => _VendorDashboardState();
}

class _VendorDashboardState extends State<VendorDashboard> {
  int _tab = 0;
  final _supabase = Supabase.instance.client;
  final AuthController authController = Get.find<AuthController>();
  final VendorController vendorCtrl = Get.put(VendorController());
  final RxBool _showOrderHistory = false.obs;
  String _storeName = 'My Store';

  Future<void> _loadStoreName() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user?.email == null) return;
      final rec = await _supabase
          .from('users')
          .select('id')
          .eq('email', user!.email!)
          .maybeSingle();
      if (rec == null) return;
      final v = await _supabase
          .from('vendors')
          .select('store_name')
          .eq('user_id', rec['id'])
          .maybeSingle();
      final name = v?['store_name']?.toString();
      if (name != null && name.isNotEmpty && mounted) {
        setState(() => _storeName = name);
      }
    } catch (_) {
      /* keep the default */
    }
  }

  @override
  void initState() {
    super.initState();
    _loadStoreName();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Get.snackbar(
            'Welcome back! 🏪',
            'Let\'s manage some orders!',
            duration: const Duration(seconds: 2),
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.white,
            colorText: AppColors.textPrimary,
            margin: const EdgeInsets.all(16),
            borderRadius: 16,
            boxShadows: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
            icon: const Icon(Icons.store_rounded, color: AppColors.primary),
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: IndexedStack(
        index: _tab,
        children: [_dashTab(), _ordersTab(), _tailoringTab(), _profileTab()],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(
                0,
                Icons.dashboard_rounded,
                Icons.dashboard_outlined,
                'Dashboard',
              ),
              _navItem(
                1,
                Icons.shopping_bag_rounded,
                Icons.shopping_bag_outlined,
                'Orders',
              ),
              _navItem(
                2,
                Icons.dry_cleaning_rounded,
                Icons.dry_cleaning_outlined,
                'Tailoring',
              ),
              _navItem(
                3,
                Icons.person_rounded,
                Icons.person_outline_rounded,
                'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    int index,
    IconData activeIcon,
    IconData defaultIcon,
    String label,
  ) {
    final isSel = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSel ? AppColors.primarySurface : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              isSel ? activeIcon : defaultIcon,
              color: isSel ? AppColors.primary : AppColors.textHint,
              size: 22,
            ),
            if (isSel) ...[
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dashTab() {
    final user = _supabase.auth.currentUser;
    final email = user?.email ?? 'Vendor';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'V';

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.bgLight,
            elevation: 0,
            floating: true,
            snap: true,
            automaticallyImplyLeading: false,
            title: const Text(
              'Store Dashboard',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: AppColors.textPrimary,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Get.to(() => NotificationsScreen()),
              ),
              Container(
                margin: const EdgeInsets.only(right: 16),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: AppColors.gradientPrimary,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Obx(
                  () => Row(
                    children: [
                      _statCard(
                        'Active Orders',
                        vendorCtrl.activeOrders.length.toString(),
                        Icons.shopping_bag_rounded,
                        AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      _statCard(
                        'Tailoring Jobs',
                        vendorCtrl.tailoringJobs.length.toString(),
                        Icons.dry_cleaning_rounded,
                        AppColors.catTailoring,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Obx(
                  () => Row(
                    children: [
                      _statCard(
                        'Delivered sales',
                        vendorCtrl.totalEarnings.value,
                        Icons.account_balance_wallet_rounded,
                        AppColors.success,
                      ),
                      const SizedBox(width: 12),
                      _statCard(
                        'Rating',
                        vendorCtrl.averageRating.value,
                        Icons.star_rounded,
                        AppColors.warning,
                      ),
                    ],
                  ),
                ),

                Obx(
                  () => vendorCtrl.statsError.value == null
                      ? const SizedBox.shrink()
                      : Row(
                          children: [
                            Expanded(child: Text(vendorCtrl.statsError.value!)),
                            TextButton(
                              onPressed: vendorCtrl.statsLoading.value
                                  ? null
                                  : vendorCtrl.loadStats,
                              child: const Text('Retry sales'),
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 24),

                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Row(
                  children: [
                    _quickAction(
                      Icons.add_box_rounded,
                      'Add Product',
                      AppColors.primary,
                      () => Get.to(() => const VendorProductsScreen()),
                    ),
                    const SizedBox(width: 12),
                    _quickAction(
                      Icons.bar_chart_rounded,
                      'Analytics',
                      AppColors.info,
                      () => Get.to(() => const VendorAnalyticsScreen()),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniOrderCard(Map<String, dynamic> o) {
    final status = o['status'] ?? 'pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt_rounded,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order #${_shortId(o['id'])}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'PKR ${o['sub_total']}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _statusBadge(status),
        ],
      ),
    );
  }

  Widget _ordersTab() {
    return SafeArea(
      child: Column(
        children: [
          _tabHeader('Orders', Icons.shopping_bag_rounded),
          Obx(
            () => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _segBtn(
                      'Active',
                      !_showOrderHistory.value,
                      () => _showOrderHistory.value = false,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _segBtn(
                      'History',
                      _showOrderHistory.value,
                      () => _showOrderHistory.value = true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Obx(() {
              if (vendorCtrl.isLoadingOrders.value) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                );
              }
              if (vendorCtrl.ordersError.value != null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        vendorCtrl.ordersError.value!,
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => vendorCtrl.refreshOrders(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              final list = _showOrderHistory.value
                  ? vendorCtrl.orderHistory
                  : vendorCtrl.activeOrders;
              if (list.isEmpty && !vendorCtrl.hasMoreOrders.value) {
                return Center(
                  child: _emptyCard(
                    _showOrderHistory.value
                        ? 'No past orders yet.'
                        : 'No active orders right now.',
                    Icons.shopping_cart_outlined,
                  ),
                );
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => vendorCtrl.refreshOrders(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount:
                      list.length + (vendorCtrl.hasMoreOrders.value ? 1 : 0),
                  itemBuilder: (_, i) => i < list.length
                      ? _orderCard(list[i])
                      : TextButton(
                          onPressed: vendorCtrl.ordersRefreshing.value
                              ? null
                              : () => vendorCtrl.refreshOrders(loadMore: true),
                          child: Text(
                            vendorCtrl.ordersRefreshing.value
                                ? 'Loading…'
                                : 'Load more',
                          ),
                        ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _segBtn(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final date = o['created_at'] != null
        ? DateTime.tryParse(o['created_at'])
        : null;
    final status = o['status'] ?? 'pending';

    final orderInfo = o['orders'] as Map<String, dynamic>?;
    final customer = orderInfo?['users'] as Map<String, dynamic>?;
    final customerName = customer?['name'] as String?;
    final customerPhone = customer?['phone'] as String?;
    final address = orderInfo?['delivery_address'] as String?;

    final items = (o['order_items'] as List?) ?? const [];
    final itemsSummary = items
        .map((it) {
          final p = it['products'] as Map<String, dynamic>?;
          final name = p?['name'] ?? 'Item';
          final qty = it['quantity'] ?? 1;
          return '${qty}x $name';
        })
        .join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.receipt_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Order #${_shortId(o['id'])}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                _statusBadge(status),
              ],
            ),
            const SizedBox(height: 12),

            if (orderInfo?['delivery_speed'] == 'express') ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 14,
                      color: AppColors.warning,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'EXPRESS — prepare first',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            if (itemsSummary.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(
                    Icons.shopping_basket_outlined,
                    color: AppColors.textHint,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      itemsSummary,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],

            if (customerName != null) ...[
              Row(
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    color: AppColors.textHint,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      customerPhone != null
                          ? '$customerName · $customerPhone'
                          : customerName,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],

            if (address != null && address.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.textHint,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],

            Row(
              children: [
                const Icon(
                  Icons.payments_outlined,
                  color: AppColors.textHint,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'PKR ${o['sub_total']}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (date != null)
                  Text(
                    timeago.format(date),
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),

            if (status == 'pending') ...[
              const SizedBox(height: 14),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 14),
              Obx(() {
                final busy = vendorCtrl.orderTransitions.busy.contains(
                  o['id'].toString(),
                );
                return Column(
                  children: [
                    if (busy) const LinearProgressIndicator(),
                    if (vendorCtrl.orderTransitions.messages[o['id'].toString()]
                        case final message?)
                      Text(message),
                    Row(
                      children: [
                        Expanded(
                          child: _actionBtn(
                            'Reject',
                            AppColors.error,
                            false,
                            busy
                                ? null
                                : () => confirmVendorOrderRejection(
                                    context,
                                    () => vendorCtrl.updateOrderStatus(
                                      o['id'],
                                      'cancelled',
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: _actionBtn(
                            'Accept Order',
                            AppColors.primary,
                            true,
                            busy
                                ? null
                                : () => vendorCtrl.updateOrderStatus(
                                    o['id'],
                                    'accepted',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ] else if (status == 'accepted' ||
                status == 'preparing' ||
                status == 'ready' ||
                (status == 'on_the_way' &&
                    o['orders']?['rider_id'] == null)) ...[
              const SizedBox(height: 14),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 14),
              Obx(() {
                final id = o['id'].toString();
                final busy = vendorCtrl.assigningOrders.contains(id);
                final message = vendorCtrl.assignment.messages[id];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (busy) const LinearProgressIndicator(),
                    _actionBtn(
                      busy
                          ? 'Matching rider…'
                          : status == 'ready' || status == 'on_the_way'
                          ? 'Retry Rider Matching'
                          : 'Mark Ready & Call Rider',
                      AppColors.success,
                      true,
                      busy
                          ? null
                          : () async {
                              final msg = await vendorCtrl
                                  .markReadyAndAssignRider(o);
                              Get.snackbar(
                                'Rider',
                                msg,
                                snackPosition: SnackPosition.BOTTOM,
                              );
                            },
                    ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(message),
                      ),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tailoringTab() {
    return SafeArea(
      child: Column(
        children: [
          _tabHeader('Tailoring Jobs', Icons.dry_cleaning_rounded),
          Expanded(
            child: Obx(
              () => vendorCtrl.tailoringJobs.isEmpty
                  ? Center(
                      child: _emptyCard(
                        'No active tailoring jobs.',
                        Icons.dry_cleaning_outlined,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: vendorCtrl.tailoringJobs.length,
                      itemBuilder: (_, i) =>
                          _tailoringCard(vendorCtrl.tailoringJobs[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tailoringCard(Map<String, dynamic> o) {
    final date = o['created_at'] != null
        ? DateTime.tryParse(o['created_at'])
        : null;
    final status = o['status'];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.catTailoring.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.dry_cleaning_rounded,
                        color: AppColors.catTailoring,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Job #${_shortId(o['id'])}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                _statusBadge(status, color: AppColors.catTailoring),
              ],
            ),
            if (o['instructions'] != null) ...[
              const SizedBox(height: 10),
              Text(
                o['instructions'],
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (date != null)
              Text(
                timeago.format(date),
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (status == 'delivered_to_tailor') ...[
              const SizedBox(height: 14),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 14),
              _actionBtn(
                'Mark Ready for Customer',
                AppColors.catTailoring,
                true,
                () => vendorCtrl.updateTailoringStatus(
                  o['id'],
                  'ready_for_customer',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _profileTab() {
    final user = _supabase.auth.currentUser;
    final email = user?.email ?? 'Vendor Account';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'V';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: AppColors.gradientDark,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _storeName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.70),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Vendor Partner',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _profileSection('Store', [
              _profileTile(
                Icons.store_outlined,
                'Store Settings',
                AppColors.primary,
                _openStoreSettings,
              ),
              _profileTile(
                Icons.payments_outlined,
                'Payment & Earnings',
                AppColors.success,
                () => Get.to(() => const VendorAnalyticsScreen()),
              ),
              _profileTile(
                Icons.star_outline,
                'Reviews & Ratings',
                AppColors.warning,
                () {
                  Get.snackbar(
                    'Coming Soon',
                    'Reviews & ratings will be available in a future update.',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: AppColors.bgSection,
                    colorText: AppColors.textPrimary,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    borderRadius: 14,
                  );
                },
              ),
            ]),
            const SizedBox(height: 14),
            _profileSection('Support', [
              _profileTile(
                Icons.chat_bubble_outline_rounded,
                'Inbox / Chat',
                AppColors.primary,
                () {
                  Get.to(() => const ChatRoomsScreen());
                },
              ),
              _profileTile(
                Icons.help_outline_rounded,
                'Help Center',
                AppColors.info,
                () {
                  Get.to(() => const HelpCenterScreen());
                },
              ),
              _profileTile(
                Icons.settings_outlined,
                'Account Settings',
                AppColors.textHint,
                () {
                  Get.snackbar(
                    'Coming Soon',
                    'Account settings will be available in a future update.',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: AppColors.bgSection,
                    colorText: AppColors.textPrimary,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    borderRadius: 14,
                  );
                },
              ),
            ]),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _confirmLogout(),
                icon: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                label: const Text(
                  'Sign Out',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout() {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.error,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Sign Out?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'You will need to sign in again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Get.back(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Get.back();
                        await authController.logout(navigate: false);
                        Get.offAll(
                          () => const SplashScreen(showCyclist: false),
                          transition: Transition.fadeIn,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Sign Out',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabHeader(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      color: AppColors.bgLight,
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status, {Color? color}) {
    final col = color ?? _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: col, fontSize: 9, fontWeight: FontWeight.w800),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return AppColors.warning;
      case 'accepted':
        return AppColors.info;
      case 'on_the_way':
        return AppColors.catFood;
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textHint;
    }
  }

  Widget _actionBtn(
    String label,
    Color color,
    bool filled,
    VoidCallback? onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: filled
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: Size.zero,
                padding: EdgeInsets.zero,
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: Size.zero,
                padding: EdgeInsets.zero,
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }

  Widget _emptyCard(String msg, IconData icon) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 38),
          ),
          const SizedBox(height: 16),
          Text(
            msg,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _openStoreSettings() async {
    Get.snackbar(
      'Loading...',
      'Fetching your store info',
      duration: const Duration(seconds: 1),
    );

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        Get.snackbar('Error', 'You are not logged in.');
        return;
      }

      final userRecord = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .maybeSingle();
      if (userRecord == null) {
        Get.snackbar('Error', 'Could not find your account record.');
        return;
      }
      final vendorId = userRecord['id'];

      final existing = await _supabase
          .from('vendors')
          .select('store_name, latitude, longitude, address')
          .eq('user_id', vendorId)
          .maybeSingle();

      final ctrl = TextEditingController(text: existing?['store_name'] ?? '');
      final addrCtrl = TextEditingController(text: existing?['address'] ?? '');
      double? lat = (existing?['latitude'] as num?)?.toDouble();
      double? lng = (existing?['longitude'] as num?)?.toDouble();
      bool saving = false;
      bool locating = false;

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Store Settings',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: ctrl,
                      decoration: InputDecoration(
                        labelText: 'Shop / Store Name',
                        hintText: 'e.g. Hot N Spicy',
                        prefixIcon: const Icon(Icons.storefront_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: addrCtrl,
                      decoration: InputDecoration(
                        labelText: 'Store Address',
                        hintText: 'e.g. Shop 4, G-8 Markaz, Islamabad',
                        prefixIcon: const Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: lat != null
                            ? AppColors.primarySurface
                            : AppColors.bgSection,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            lat != null
                                ? Icons.check_circle_rounded
                                : Icons.my_location_rounded,
                            size: 18,
                            color: lat != null
                                ? AppColors.success
                                : AppColors.textHint,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              lat != null
                                  ? 'Location set (${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)})'
                                  : 'Store location not set — riders can\'t be matched',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: locating
                            ? null
                            : () async {
                                setDialogState(() => locating = true);
                                try {
                                  var perm = await Geolocator.checkPermission();
                                  if (perm == LocationPermission.denied) {
                                    perm = await Geolocator.requestPermission();
                                  }
                                  if (perm == LocationPermission.denied ||
                                      perm ==
                                          LocationPermission.deniedForever) {
                                    Get.snackbar(
                                      'Permission needed',
                                      'Please allow location access to set your store location.',
                                    );
                                    setDialogState(() => locating = false);
                                    return;
                                  }
                                  final pos =
                                      await Geolocator.getCurrentPosition();
                                  setDialogState(() {
                                    lat = pos.latitude;
                                    lng = pos.longitude;
                                    locating = false;
                                  });
                                } catch (e) {
                                  setDialogState(() => locating = false);
                                  Get.snackbar(
                                    'Error',
                                    'Could not get location: $e',
                                  );
                                }
                              },
                        icon: locating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location_rounded, size: 18),
                        label: Text(
                          locating
                              ? 'Getting location…'
                              : (lat != null
                                    ? 'Update to current location'
                                    : 'Use my current location'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Get.back(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final name = ctrl.text.trim();
                          if (name.isEmpty) {
                            Get.snackbar('Error', 'Store name cannot be empty');
                            return;
                          }
                          setDialogState(() => saving = true);
                          try {
                            await _supabase.from('vendors').upsert({
                              'user_id': vendorId,
                              'store_name': name,
                              'address': addrCtrl.text.trim(),
                              'latitude': lat,
                              'longitude': lng,
                              'is_active': true,
                            }, onConflict: 'user_id');
                            Get.back();
                            if (mounted) setState(() => _storeName = name);
                            Get.snackbar(
                              'Saved ✅',
                              'Your store details have been updated',
                              backgroundColor: AppColors.success,
                              colorText: Colors.white,
                            );
                          } catch (e) {
                            setDialogState(() => saving = false);
                            Get.snackbar('Error', 'Could not save: $e');
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Something went wrong: $e',
        duration: const Duration(seconds: 5),
      );
    }
  }

  Widget _profileSection(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textHint,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(children: tiles),
          ),
        ),
      ],
    );
  }

  Widget _profileTile(
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 13,
        color: AppColors.textHint,
      ),
      onTap: onTap,
    );
  }
}
