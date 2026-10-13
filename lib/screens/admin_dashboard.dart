import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/admin_controller.dart';
import '../models/user_model.dart';
import '../widgets/app_drawer.dart';
import '../theme/app_theme.dart';
import 'chat_rooms_screen.dart';
import '../widgets/cnic_document_viewer.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _tab = 0;
  final AdminController adminCtrl = Get.put(AdminController());
  @override
  void dispose() {
    Get.delete<AdminController>();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Get.snackbar(
            'Welcome back! 🛡️',
            'Let\'s review operations.',
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
            icon: const Icon(
              Icons.admin_panel_settings_rounded,
              color: AppColors.primary,
            ),
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      drawer: const AppDrawer(),
      body: Obx(() {
        if (adminCtrl.isLoading.value) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          );
        }
        return IndexedStack(
          index: _tab,
          children: [
            _overviewTab(),
            _ridersTab(),
            _vendorsTab(),
            _disputesTab(),
          ],
        );
      }),
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
                Icons.analytics_rounded,
                Icons.analytics_outlined,
                'Overview',
              ),
              _navItem(
                1,
                Icons.delivery_dining_rounded,
                Icons.delivery_dining_outlined,
                'Riders',
              ),
              _navItem(
                2,
                Icons.storefront_rounded,
                Icons.storefront_outlined,
                'Vendors',
              ),
              _navItem(
                3,
                Icons.report_problem_rounded,
                Icons.report_problem_outlined,
                'Disputes',
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _overviewTab() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: AppColors.bgLight,
          elevation: 0,
          floating: true,
          snap: true,
          leading: Builder(
            builder: (ctx) => GestureDetector(
              onTap: () => Scaffold.of(ctx).openDrawer(),
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.menu_rounded,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ),
          title: const Text(
            'Admin Panel',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: AppColors.textPrimary,
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.gradientDark,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.32),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Operations Control',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'TezRider Admin',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Obx(() {
                            final live = adminCtrl.orders
                                .where(
                                  (o) =>
                                      o.orderStatus != 'delivered' &&
                                      o.orderStatus != 'cancelled',
                                )
                                .length;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(
                                  alpha: 0.20,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$live active orders right now',
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Obx(() {
                final activeRiders =
                    adminCtrl.activeRiderCount.value?.toString() ?? '—';
                final liveOrders = adminCtrl.orders
                    .where(
                      (o) =>
                          o.orderStatus != 'delivered' &&
                          o.orderStatus != 'cancelled',
                    )
                    .length;
                final openDisputes = adminCtrl.disputes
                    .where((d) => d['status'] == 'Open')
                    .length;

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.12,
                  children: [
                    _statCard(
                      'Total Orders',
                      '${adminCtrl.orders.length}',
                      Icons.receipt_long_rounded,
                      AppColors.primary,
                    ),
                    _statCard(
                      'Live Orders',
                      '$liveOrders',
                      Icons.local_shipping_rounded,
                      AppColors.info,
                    ),
                    _statCard(
                      'Active Riders',
                      activeRiders,
                      Icons.moped_rounded,
                      AppColors.success,
                    ),
                    _statCard(
                      'Open Disputes',
                      '$openDisputes',
                      Icons.warning_amber_rounded,
                      AppColors.error,
                    ),
                  ],
                );
              }),

              const SizedBox(height: 24),

              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Text(
                  'Awaiting Approval',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),

              Obx(
                () => Row(
                  children: [
                    if (adminCtrl.isLoading.value)
                      const Expanded(child: LinearProgressIndicator())
                    else
                      const Spacer(),
                    IconButton(
                      onPressed: adminCtrl.isLoading.value
                          ? null
                          : adminCtrl.refreshApprovals,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh approvals',
                    ),
                  ],
                ),
              ),

              Obx(() {
                final pendingRiders = adminCtrl.pendingRiders.toList();
                final pendingVendors = adminCtrl.vendors
                    .where((v) => v.verificationStatus == 'pending')
                    .toList();
                if (adminCtrl.approvalError.value != null) {
                  return Text(
                    adminCtrl.approvalError.value!,
                    style: const TextStyle(color: AppColors.error),
                  );
                }
                if (adminCtrl.isLoading.value &&
                    pendingRiders.isEmpty &&
                    pendingVendors.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (pendingRiders.isEmpty && pendingVendors.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.success,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          'No pending approvals',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    ...pendingRiders.map((r) => _pendingCard(r, 'Rider')),
                    ...pendingVendors.map((v) => _pendingCard(v, 'Vendor')),
                    if (adminCtrl.hasMorePending.value)
                      TextButton(
                        onPressed: adminCtrl.isLoading.value
                            ? null
                            : () => adminCtrl.loadMore(pending: true),
                        child: const Text('Load more pending riders'),
                      ),
                    TextButton(
                      onPressed: adminCtrl.isLoading.value
                          ? null
                          : adminCtrl.refreshApprovals,
                      child: const Text('Refresh approvals / Retry'),
                    ),
                    if (adminCtrl.approvalError.value != null)
                      Text(
                        adminCtrl.approvalError.value!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                  ],
                );
              }),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
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
        mainAxisAlignment: MainAxisAlignment.center,
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
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard(UserModel item, String type) {
    final isRider = type == 'Rider';
    final color = isRider ? AppColors.primary : AppColors.catFood;
    final icon = isRider ? Icons.two_wheeler_rounded : Icons.storefront_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.30),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'New $type · ${item.email}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.cnic != null && item.cnic!.isNotEmpty)
                  Text(
                    'CNIC: ${item.cnic}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRider)
                _actionBtn(
                  'View CNIC',
                  AppColors.info,
                  item.documentValid
                      ? () => Get.dialog(CnicDocumentViewer(userId: item.id))
                      : null,
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _actionBtn(
                    'Approve',
                    AppColors.success,
                    isRider && !item.documentValid
                        ? null
                        : () => adminCtrl.updateStatus(
                            'users',
                            item.id,
                            'approved',
                          ),
                  ),
                  const SizedBox(width: 6),
                  _actionBtn(
                    'Reject',
                    AppColors.error,
                    () => adminCtrl.updateStatus('users', item.id, 'rejected'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ridersTab() {
    return CustomScrollView(
      slivers: [
        _tabSliverAppBar('Riders Management', Icons.moped_rounded),
        Obx(
          () => adminCtrl.riders.isEmpty
              ? SliverFillRemaining(
                  child: _emptyState(
                    'No riders found.',
                    Icons.delivery_dining_outlined,
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _userCard(adminCtrl.riders[i], isRider: true),
                      childCount: adminCtrl.riders.length,
                    ),
                  ),
                ),
        ),
        Obx(
          () => SliverToBoxAdapter(
            child: adminCtrl.hasMoreRiders.value
                ? TextButton(
                    onPressed: adminCtrl.isLoading.value
                        ? null
                        : () => adminCtrl.loadMore(),
                    child: const Text('Load more riders'),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _vendorsTab() {
    return CustomScrollView(
      slivers: [
        _tabSliverAppBar('Vendor Partners', Icons.storefront_rounded),
        Obx(
          () => adminCtrl.vendors.isEmpty
              ? SliverFillRemaining(
                  child: _emptyState('No vendors found.', Icons.store_outlined),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _userCard(adminCtrl.vendors[i], isRider: false),
                      childCount: adminCtrl.vendors.length,
                    ),
                  ),
                ),
        ),
        Obx(
          () => SliverToBoxAdapter(
            child: adminCtrl.hasMoreVendors.value
                ? TextButton(
                    onPressed: adminCtrl.isLoading.value
                        ? null
                        : () => adminCtrl.loadMore(vendor: true),
                    child: const Text('Load more vendors'),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _userCard(UserModel item, {required bool isRider}) {
    final statusColor = _statusColor(item.verificationStatus);
    final color = isRider ? AppColors.primary : AppColors.catFood;
    final icon = isRider ? Icons.two_wheeler_rounded : Icons.storefront_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (item.verificationStatus == 'approved') ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: AppColors.info,
                      ),
                    ],
                  ],
                ),
                Text(
                  item.email,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _statusBadge(item.verificationStatus, statusColor),
        ],
      ),
    );
  }

  Widget _disputesTab() {
    return CustomScrollView(
      slivers: [
        _tabSliverAppBar('Dispute Resolution', Icons.report_problem_rounded),
        Obx(
          () => adminCtrl.disputes.isEmpty
              ? SliverFillRemaining(
                  child: _emptyState(
                    'No disputes.',
                    Icons.check_circle_outline_rounded,
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _disputeCard(adminCtrl.disputes[i]),
                      childCount: adminCtrl.disputes.length,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _disputeCard(Map<String, dynamic> d) {
    final isOpen = d['status'] == 'Open';
    final statusColor = isOpen ? AppColors.error : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isOpen
            ? Border.all(
                color: AppColors.error.withValues(alpha: 0.20),
                width: 1,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isOpen
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_rounded,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d['type'] ?? 'Dispute',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Raised by ${d['by'] ?? 'Unknown'}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _statusBadge(d['status'] ?? 'Unknown', statusColor),
            ],
          ),
          if (isOpen) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _actionBtn('Chat', AppColors.info, () {
                    Get.to(() => const ChatRoomsScreen());
                  }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _actionBtn(
                    'Mark Resolved',
                    AppColors.success,
                    () async {
                      try {
                        final supabase = Supabase.instance.client;
                        await supabase
                            .from('disputes')
                            .update({'status': 'Resolved'})
                            .eq('id', d['id']);
                      } catch (_) {}
                      Get.snackbar(
                        'Dispute Resolved',
                        'The dispute has been marked as resolved.',
                        snackPosition: SnackPosition.BOTTOM,
                        backgroundColor: AppColors.success,
                        colorText: Colors.white,
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        borderRadius: 14,
                        icon: const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  SliverAppBar _tabSliverAppBar(String title, IconData icon) {
    return SliverAppBar(
      backgroundColor: AppColors.bgLight,
      elevation: 0,
      floating: true,
      snap: true,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.textHint;
    }
  }

  Widget _actionBtn(String label, Color color, VoidCallback? onTap) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        onPressed: adminCtrl.reviewing.value != null ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.10),
          foregroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _emptyState(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
          ),
        ],
      ),
    );
  }
}
