import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import '../widgets/rider_performance_panel.dart';
import '../widgets/delivery_photo_panel.dart';
import 'customer/profile_screen.dart';
import '../widgets/language_settings_tile.dart';
import 'rating_summary_screen.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/tez_map_tiles.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../controllers/auth_controller.dart';
import '../controllers/rider_controller.dart';
import '../widgets/pre_delivery_checklist_card.dart';
import '../widgets/order_payment_panel.dart';
import '../theme/app_theme.dart';
import 'splash_screen.dart';
import 'chat_rooms_screen.dart';
import 'customer/help_center_screen.dart';
import 'customer/notifications_screen.dart';

/// Safely shortens an id string for display — never crashes on short ids.
String _shortId(dynamic id, [int len = 6]) {
  final s = id?.toString() ?? '------';
  return s.length < len ? s : s.substring(0, len);
}

class RiderDashboard extends StatefulWidget {
  const RiderDashboard({super.key});
  @override
  State<RiderDashboard> createState() => _RiderDashboardState();
}

class _RiderDashboardState extends State<RiderDashboard> {
  int _tab = 0;
  final _supabase = Supabase.instance.client;
  final AuthController authController = Get.find<AuthController>();
  final RiderController riderCtrl = Get.put(RiderController());

  Widget _locationStatus() {
    final message = Text(riderCtrl.location.message.value.uiMessage);
    if (!riderCtrl.location.hasSettingsLink) return message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        message,
        TextButton(
          onPressed: riderCtrl.location.openSettings,
          child: Text("Location settings".tr),
        ),
      ],
    );
  }

  LatLng? get _currentLocation {
    final fix = riderCtrl.location.latestFix.value;
    return fix == null ? null : LatLng(fix.latitude, fix.longitude);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Get.snackbar(
            "Welcome back! 🏍️".tr,
            "Ready to hit the road?".tr,
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
              Icons.two_wheeler_rounded,
              color: AppColors.primary,
            ),
          );
        }
      });
    });
  }

  Future<void> _acceptOrder(Map<String, dynamic> order) async {
    await riderCtrl.acceptOrder(order);
    if (riderCtrl.currentOrder.value != null) setState(() => _tab = 1);
  }

  Future<void> _acceptTailoring(Map<String, dynamic> request) async {
    await riderCtrl.acceptTailoring(request);
    if (riderCtrl.currentOrder.value != null) setState(() => _tab = 1);
  }

  Future<void> _markDelivered() async {
    await riderCtrl.markDelivered();
    if (riderCtrl.currentOrder.value == null) setState(() => _tab = 0);
  }

  Future<void> _arrived() async {
    await riderCtrl.requestDeliveryOtp();
    if (mounted) _showOtpSheet();
  }

  void _showOtpSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OtpVerifySheet(
        riderCtrl: riderCtrl,
        onSuccess: () {
          Get.back();
          setState(() => _tab = 0);
          Get.snackbar(
            "Delivery Complete!".tr,
            "Order successfully delivered.".tr,
            backgroundColor: AppColors.success,
            colorText: Colors.white,
            snackPosition: SnackPosition.TOP,
            margin: const EdgeInsets.all(16),
            borderRadius: 16,
            icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
            duration: const Duration(seconds: 3),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    Get.delete<RiderController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    // Subscribe this route to locale changes as Get translation lookups are global.
    Localizations.localeOf(context);
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: IndexedStack(
        index: _tab,
        children: [_homeTab(), _mapTab(), _earningsTab(), _profileTab()],
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
                "Home".tr,
              ),
              _navItem(1, Icons.map_rounded, Icons.map_outlined, "Map".tr),
              _navItem(
                2,
                Icons.account_balance_wallet_rounded,
                Icons.account_balance_wallet_outlined,
                "Earnings".tr,
              ),
              _navItem(
                3,
                Icons.person_rounded,
                Icons.person_outline_rounded,
                "Profile".tr,
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
                label.tr,
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

  Widget _homeTab() {
    return SafeArea(
      child: Obx(
        () => CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: AppColors.bgLight,
              elevation: 0,
              floating: true,
              snap: true,
              automaticallyImplyLeading: false,
              title: Text(
                'Rider Dashboard'.tr,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: AppColors.textPrimary,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: "Notifications".tr,
                  onPressed: () => Get.to(() => NotificationsScreen()),
                  icon: const Icon(Icons.notifications_outlined),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: riderCtrl.isOnline.value
                              ? AppColors.success.withValues(alpha: 0.12)
                              : AppColors.bgSection,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: riderCtrl.isOnline.value
                                    ? AppColors.success
                                    : AppColors.textHint,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              riderCtrl.isOnline.value
                                  ? "Online".tr
                                  : "Offline".tr,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: riderCtrl.isOnline.value
                                    ? AppColors.success
                                    : AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Switch.adaptive(
                        value: riderCtrl.isOnline.value,
                        onChanged:
                            riderCtrl.presenceBusy.value ||
                                !riderCtrl.presenceReady.value
                            ? null
                            : riderCtrl.setOnlineStatus,
                        activeThumbColor: AppColors.success,
                        activeTrackColor: AppColors.success.withValues(
                          alpha: 0.35,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (riderCtrl.presenceError.value != null)
              SliverToBoxAdapter(
                child: ListTile(
                  title: Text(riderCtrl.presenceError.value!.uiMessage),
                  trailing: TextButton(
                    onPressed: riderCtrl.presenceBusy.value
                        ? null
                        : riderCtrl.restoreOnlineStatus,
                    child: Text("Retry".tr),
                  ),
                ),
              ),

            if (riderCtrl.isOnline.value)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: _locationStatus(),
                ),
              ),

            if (riderCtrl.requestsError.value != null)
              SliverToBoxAdapter(
                child: ListTile(
                  title: Text(riderCtrl.requestsError.value!.uiMessage),
                  trailing: TextButton(
                    onPressed: riderCtrl.requestsLoading.value
                        ? null
                        : riderCtrl.retryRequests,
                    child: Text("Retry".tr),
                  ),
                ),
              ),

            if (riderCtrl.currentOrder.value != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: GestureDetector(
                    onTap: () => setState(() => _tab = 1),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: AppColors.gradientDark,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delivery_dining_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Active Delivery".tr,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Tap to view map & complete".tr,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Row(
                  children: [
                    Text(
                      "Available Requests".tr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Obx(
                        () => Text(
                          "@slot0end new".uiTr({
                            "slot0end":
                                (riderCtrl.availableOrders.length +
                                        riderCtrl.availableTailoring.length)
                                    .toString(),
                          }),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (!riderCtrl.isOnline.value)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.bgSection,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.wifi_off_rounded,
                          color: AppColors.textHint,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "You are offline".tr,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Toggle the switch to go online".tr,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (riderCtrl.availableOrders.isEmpty &&
                riderCtrl.availableTailoring.isEmpty)
              SliverFillRemaining(
                child: Center(
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
                        child: const Icon(
                          Icons.search_rounded,
                          color: AppColors.primary,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Searching for orders...".tr,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "New requests will appear here".tr,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    ...riderCtrl.availableOrders.map(
                      (o) => _orderRequestCard(o),
                    ),
                    ...riderCtrl.availableTailoring.map(
                      (o) => _tailoringRequestCard(o),
                    ),
                    if (riderCtrl.hasMoreRequests.value)
                      TextButton(
                        onPressed: riderCtrl.requestsLoading.value
                            ? null
                            : riderCtrl.loadMoreRequests,
                        child: Text("Load more".tr),
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _orderRequestCard(Map<String, dynamic> o) {
    final date = o['created_at'] != null
        ? DateTime.tryParse(o['created_at'])
        : null;
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
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.catFood.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.fastfood_rounded,
                    color: AppColors.catFood,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Order #@slot0end".uiTr({
                          "slot0end": (_shortId(o['id'])).toString(),
                        }),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (date != null)
                        Text(
                          timeago.format(date),
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  "PKR @slot0end".uiTr({
                    "slot0end": (o['amount'] ?? 0).toString(),
                  }),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (o['delivery_address'] != null)
              Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.error,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      o['delivery_address'],
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
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => _acceptOrder(o),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  "Accept Order".tr,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tailoringRequestCard(Map<String, dynamic> o) {
    final date = o['created_at'] != null
        ? DateTime.tryParse(o['created_at'])
        : null;
    final isToCustomer = o['status'] == 'ready_for_customer';

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
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.catTailoring.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.dry_cleaning_rounded,
                    color: AppColors.catTailoring,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Tailoring #@slot0end".uiTr({
                          "slot0end": (_shortId(o['id'])).toString(),
                        }),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (date != null)
                        Text(
                          timeago.format(date),
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.catTailoring.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.catTailoring,
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isToCustomer
                          ? "Deliver stitched clothes to customer".tr
                          : "Pickup unstitched clothes from customer".tr,
                      style: const TextStyle(
                        color: AppColors.catTailoring,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => _acceptTailoring(o),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.catTailoring,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  "Accept Job".tr,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapTab() {
    return Obx(() {
      final order = riderCtrl.currentOrder.value;
      if (order == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.map_outlined,
                    size: 44,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "No Active Delivery".tr,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Accept an order to see the route on the map.".tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => setState(() => _tab = 0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    "Find Orders".tr,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _currentLocation ?? const LatLng(33.6844, 73.0479),
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tezrider.app',
                tileProvider: tezMapTiles(),
              ),
              MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 60,
                      height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.20),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.motorcycle_rounded,
                            color: AppColors.primary,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          Positioned(
            top: 50,
            left: 20,
            child: GestureDetector(
              onTap: () => setState(() => _tab = 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ),

          const Positioned(top: 52, right: 16, child: TezMapAttribution()),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 24,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.68,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (order['type'] == 'order' &&
                          order['order_status'] != 'on_the_way')
                        PreDeliveryChecklistCard(
                          flow: riderCtrl.checklist,
                          onAccept: () => riderCtrl.acceptOrder(order),
                          onStart: riderCtrl.startDelivery,
                        ),
                      if (order['type'] == 'order' &&
                          order['order_status'] == 'on_the_way') ...[
                        Text(
                          "Share your live location with this order’s customer during delivery, including while the screen is locked. You can stop sharing below."
                              .tr,
                        ),
                        const SizedBox(height: 8),
                        _locationStatus(),
                        FilledButton(
                          onPressed: riderCtrl.location.busy.value
                              ? null
                              : riderCtrl.location.sharing.value
                              ? riderCtrl.location.stop
                              : riderCtrl.shareDeliveryLocation,
                          child: Text(
                            riderCtrl.location.sharing.value
                                ? "Stop sharing location".tr
                                : "Share delivery location".tr,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (order['type'] == 'order' &&
                          order['order_status'] == 'on_the_way')
                        DeliveryPhotoPanel(
                          key: ValueKey('proof-${order['id']}'),
                          orderId: int.parse(order['id'].toString()),
                        ),
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.pin_drop_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order['type'] == 'tailoring'
                                      ? "Tailoring Pickup/Dropoff".tr
                                      : "Delivering to".tr,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  order['delivery_address'] ??
                                      "Customer Location".tr,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final phone =
                                    order['customer_phone'] ?? order['phone'];
                                if (phone != null &&
                                    phone.toString().isNotEmpty) {
                                  final uri = Uri.parse(
                                    'tel:${phone.toString()}',
                                  );
                                  try {
                                    await launchUrl(uri);
                                  } catch (_) {}
                                } else {
                                  Get.snackbar(
                                    "Contact".tr,
                                    "Customer number not available.".tr,
                                    snackPosition: SnackPosition.BOTTOM,
                                    backgroundColor: AppColors.bgSection,
                                    colorText: AppColors.textPrimary,
                                    margin: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      20,
                                    ),
                                    borderRadius: 14,
                                  );
                                }
                              },
                              icon: const Icon(Icons.call_rounded, size: 18),
                              label: Text("Call".tr),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.success,
                                side: const BorderSide(
                                  color: AppColors.success,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed:
                                  riderCtrl.deliveryBusy.value ||
                                      riderCtrl.deliveryOtp.busy.value ||
                                      (order['type'] == 'order' &&
                                          order['order_status'] != 'on_the_way')
                                  ? null
                                  : order['type'] == 'tailoring'
                                  ? _markDelivered
                                  : _arrived,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                order['type'] == 'tailoring'
                                    ? "Complete Step".tr
                                    : "Arrived".tr,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _earningsTab() {
    return SafeArea(
      child: Obx(
        () => CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: AppColors.bgLight,
              elevation: 0,
              floating: true,
              snap: true,
              automaticallyImplyLeading: false,
              title: Text(
                'My Earnings'.tr,
                style: const TextStyle(
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
                  const RiderPerformancePanel(),
                  const SizedBox(height: 16),
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
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Earned delivery fees".tr,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.70),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          riderCtrl.todayEarnings.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Fee policy pending approval. Order totals are not Rider earnings."
                              .tr,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 22),
                        const Divider(color: Colors.white24, height: 1),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _earningsStat(
                              "Trips Today".tr,
                              riderCtrl.tripsToday.value.toString(),
                            ),
                            _dividerLine(),
                            _earningsStat(
                              "All Time".tr,
                              riderCtrl.totalDeliveries.value.toString(),
                            ),
                            _dividerLine(),
                            _earningsStat(
                              "This Week".tr,
                              riderCtrl.weeklyEarnings.value.replaceFirst(
                                'PKR ',
                                'PKR\n',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    children: [
                      _earningsCard(
                        "Weekly".tr,
                        riderCtrl.weeklyEarnings.value,
                        Icons.calendar_view_week_rounded,
                        AppColors.info,
                      ),
                      const SizedBox(width: 12),
                      _earningsCard(
                        "Monthly".tr,
                        riderCtrl.monthlyEarnings.value,
                        Icons.calendar_month_rounded,
                        AppColors.catTailoring,
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  Obx(() {
                    if (riderCtrl.totalDeliveries.value == 0) {
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 40),
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
                        child: Column(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.bgSection,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.history_rounded,
                                color: AppColors.textHint,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              "No deliveries yet".tr,
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            "Recent Deliveries".tr,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const _DeliveryHistoryList(),
                      ],
                    );
                  }),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _earningsStat(String label, String val) {
    return Column(
      children: [
        Text(
          val,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _dividerLine() =>
      Container(width: 1, height: 32, color: Colors.white24);

  Widget _earningsCard(String title, String value, IconData icon, Color color) {
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
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileTab() {
    final user = _supabase.auth.currentUser;
    final email = user?.email ?? 'rider@tezrider.com';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'R';

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
                          "TezRider Partner".tr,
                          style: TextStyle(
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
                        Obx(
                          () => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: riderCtrl.isOnline.value
                                  ? AppColors.success.withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: riderCtrl.isOnline.value
                                        ? AppColors.success
                                        : Colors.white70,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  riderCtrl.isOnline.value
                                      ? "Online".tr
                                      : "Offline".tr,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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

            _profileSection("Rider Details".tr, [
              _profileTile(
                Icons.directions_bike_rounded,
                "Vehicle Details".tr,
                AppColors.primary,
                () {
                  Get.snackbar(
                    "Coming Soon".tr,
                    "Vehicle details will be available in a future update.".tr,
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: AppColors.bgSection,
                    colorText: AppColors.textPrimary,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    borderRadius: 14,
                  );
                },
              ),
              _profileTile(
                Icons.account_balance_rounded,
                "Bank Information".tr,
                AppColors.success,
                () {
                  Get.snackbar(
                    "Coming Soon".tr,
                    "Bank information will be available in a future update.".tr,
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: AppColors.bgSection,
                    colorText: AppColors.textPrimary,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    borderRadius: 14,
                  );
                },
              ),
              _profileTile(
                Icons.star_outline_rounded,
                "Ratings & Reviews".tr,
                AppColors.warning,
                () => Get.to(() => const RatingSummaryScreen()),
              ),
            ]),
            const SizedBox(height: 14),
            _profileSection("Support".tr, [
              const LanguageSettingsTile(),
              _profileTile(
                Icons.chat_bubble_outline_rounded,
                "Inbox / Chat".tr,
                AppColors.primary,
                () {
                  Get.to(() => const ChatRoomsScreen());
                },
              ),
              _profileTile(
                Icons.help_outline_rounded,
                "Help & Support".tr,
                AppColors.info,
                () {
                  Get.to(() => const HelpCenterScreen());
                },
              ),
              _profileTile(
                Icons.settings_outlined,
                "Settings".tr,
                AppColors.textHint,
                () => Get.to(() => const ProfileScreen()),
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
                label: Text(
                  "Log Out".tr,
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
              Text(
                "Log Out?".tr,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                "You will need to sign in again.".tr,
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
                      child: Text(
                        "Cancel".tr,
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
                      child: Text(
                        "Log Out".tr,
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
          child: Column(children: tiles),
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

class _DeliveryHistoryList extends StatefulWidget {
  const _DeliveryHistoryList();
  @override
  State<_DeliveryHistoryList> createState() => _DeliveryHistoryListState();
}

class _DeliveryHistoryListState extends State<_DeliveryHistoryList> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final rec = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .maybeSingle();
      if (rec == null) return;
      final data =
          await _supabase
                  .from('orders')
                  .select(
                    'id, amount, created_at, delivery_address, order_status',
                  )
                  .eq('rider_id', rec['id'])
                  .eq('order_status', 'delivered')
                  .order('created_at', ascending: false)
                  .limit(20)
              as List;
      if (mounted) setState(() => _history = data.cast<Map<String, dynamic>>());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (_history.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
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
        child: Center(
          child: Text(
            "No completed deliveries yet.".tr,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }
    return Column(
      children: _history.map((o) {
        final rawId = o['id']?.toString() ?? '--------';
        final id = rawId.substring(0, rawId.length < 8 ? rawId.length : 8);
        final amount = o['amount'] ?? 0;
        final addr = o['delivery_address'] as String? ?? 'Customer location';
        final date = o['created_at'] != null
            ? DateTime.tryParse(o['created_at'])?.toLocal()
            : null;
        final dateStr = date != null
            ? '${date.day}/${date.month}/${date.year}'
            : '';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Order #@slot0end".uiTr({"slot0end": (id).toString()}),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      addr,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "Order total: PKR @slot0end".uiTr({
                      "slot0end": (amount).toString(),
                    }),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11,
                    ),
                  ),
                  if (int.tryParse(rawId) case final orderId?)
                    TextButton(
                      onPressed: () => showOrderPayment(
                        context,
                        orderId,
                        allowCollection: true,
                      ),
                      child: Text("Cash receipt".tr),
                    ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _OtpVerifySheet extends StatefulWidget {
  final RiderController riderCtrl;
  final VoidCallback onSuccess;
  const _OtpVerifySheet({required this.riderCtrl, required this.onSuccess});
  @override
  State<_OtpVerifySheet> createState() => _OtpVerifySheetState();
}

class _OtpVerifySheetState extends State<_OtpVerifySheet> {
  final input = TextEditingController();
  Timer? clock;
  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    final ok = await widget.riderCtrl.verifyOtpAndDeliver(input.text);
    if (!mounted) return;
    if (ok) {
      widget.onSuccess();
      return;
    }
    if (!widget.riderCtrl.deliveryOtp.uncertainVerification.value) {
      input.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final flow = widget.riderCtrl.deliveryOtp;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Obx(
            () => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Email delivery verification".tr,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  "Ask the customer for the six-digit code from their registered email when handing over the order."
                      .tr,
                ),
                if (flow.status['masked_email'] is String)
                  Text(flow.status['masked_email'] as String),
                const SizedBox(height: 12),
                Text(flow.message.uiMessage),
                if (flow.remainingAttempts != null)
                  Text(
                    "Attempts remaining: @slot0end".uiTr({
                      "slot0end": (flow.remainingAttempts).toString(),
                    }),
                  ),
                if (flow.status['expires_at'] != null)
                  Text(
                    flow.active
                        ? "Code expires: @slot0end".uiTr({
                            "slot0end": (flow.status['expires_at']).toString(),
                          })
                        : "Code is not currently active.".tr,
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: input,
                  enabled:
                      !flow.busy.value && !flow.uncertainVerification.value,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: "Six-digit delivery code".tr,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: flow.busy.value ? null : verify,
                  child: Text(
                    flow.uncertainVerification.value
                        ? "Retry unchanged verification".tr
                        : "Confirm Delivery".tr,
                  ),
                ),
                OutlinedButton(
                  onPressed: flow.busy.value ? null : () => flow.requestEmail(),
                  child: Text("Retry email request".tr),
                ),
                OutlinedButton(
                  onPressed:
                      flow.busy.value ||
                          flow.cooldownSeconds > 0 ||
                          flow.uncertainVerification.value
                      ? null
                      : () => flow.requestEmail(newCode: true),
                  child: Text(
                    flow.cooldownSeconds > 0
                        ? "Resend in @slot0ends".uiTr({
                            "slot0end": (flow.cooldownSeconds).toString(),
                          })
                        : "Request a new code".tr,
                  ),
                ),
                if (flow.busy.value)
                  const Center(child: CircularProgressIndicator()),
                TextButton(
                  onPressed: flow.busy.value ? null : () => flow.refresh(),
                  child: Text("Refresh server status".tr),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
