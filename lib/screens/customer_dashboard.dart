import '../widgets/stock_indicator.dart';
import '../services/catalogue_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/product_image.dart';
import 'package:lottie/lottie.dart';
import 'package:shimmer/shimmer.dart';
import 'customer/cart_screen.dart';
import 'map_screen.dart';
import '../controllers/auth_controller.dart';
import '../controllers/tez_order_controller.dart';
import '../controllers/cart_controller.dart';
import '../controllers/product_controller.dart';
import '../controllers/notification_controller.dart';
import '../widgets/order_timeout_summary.dart';
import '../controllers/vendor_info_controller.dart';
import '../widgets/app_drawer.dart';
import 'ai_assistant_screen.dart';
import 'search_screen.dart';
import 'customer/profile_screen.dart';
import 'customer/tailoring_screen.dart';
import 'customer/order_history_screen.dart';
import 'customer/dispute_screen.dart';
import 'customer/saved_addresses_screen.dart';
import 'customer/payment_methods_screen.dart';
import 'customer/saved_stores_screen.dart';
import 'customer/notifications_screen.dart';
import 'customer/help_center_screen.dart';
import 'customer/about_tezrider_screen.dart';
import 'product_detail_screen.dart';
import 'chat_rooms_screen.dart';
import 'package:url_launcher/url_launcher.dart';

const _kBg = Color(0xFFF5F0E8);
const _kCard = Color(0xFFFFFFFF);
const _kCardSub = Color(0xFFEDF7EE);
const _kPurple = Color(0xFF1B5E20);
const _kPurpleL = Color(0xFF388E3C);
const _kSaffron = Color(0xFFF59E0B);
const _kGreen = Color(0xFF10B981);
const _kPink = Color(0xFFEC4899);
const _kTeal = Color(0xFF06B6D4);
const _kText = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});
  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard>
    with TickerProviderStateMixin {
  int _tab = 0;
  int _selectedCatIndex = 0;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _dbCategories = [];
  bool _categoriesLoading = true;
  String? _categoriesError;
  bool _ordersLoading = true;
  Worker? _orderRefresh;
  bool _ordersBusy = false, _ordersDirty = false;
  String? _ordersError;
  int? _userId;
  Set<dynamic> _favIds = {};

  final AuthController auth = Get.find<AuthController>();
  final TezOrderController tezCtrl = Get.put(TezOrderController());
  final CartController cart = Get.put(CartController());
  final NotificationController notifCtrl = Get.put(NotificationController());
  final ProductController productCtrl = Get.put(ProductController());
  final VendorInfoController vendorInfoCtrl = Get.put(VendorInfoController());
  final _supabase = Supabase.instance.client;

  late AnimationController _heroAnim;
  late AnimationController _navAnim;
  late AnimationController _orderButtonAnim;
  late List<AnimationController> _cardAnims;

  late Animation<double> _heroFade;
  late Animation<Offset> _heroSlide;
  late Animation<double> _navFade;
  late Animation<double> _orderButtonScale;

  final _scrollCtrl = ScrollController();
  int _featuredIndex = 0;
  late PageController _pageCtrl;
  Timer? _carouselTimer;

  List<Map<String, dynamic>> _featured = [];
  bool _featuredLoading = true;
  String? _featuredError;

  @override
  void initState() {
    super.initState();
    _orderRefresh = ever(notifCtrl.notifications, (_) {
      if (mounted) unawaited(_loadOrders());
    });
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _heroAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _navAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _orderButtonAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _cardAnims = List.generate(
      8,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      ),
    );

    // Get customer's live location (for "nearest branch") and, once the
    // product list is in, batch-fetch shop name/rating/branches for every
    // vendor shown — one round trip instead of one per card.
    vendorInfoCtrl.loadCustomerLocation();
    ever(productCtrl.products, (_) {
      final vendorIds = productCtrl.products.map((p) => p.vendorId).toSet();
      vendorInfoCtrl.loadVendorInfo(vendorIds);
    });
    if (productCtrl.products.isNotEmpty) {
      vendorInfoCtrl.loadVendorInfo(
        productCtrl.products.map((p) => p.vendorId).toSet(),
      );
    }

    _heroFade = CurvedAnimation(parent: _heroAnim, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, -0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _heroAnim, curve: Curves.easeOutCubic));
    _navFade = CurvedAnimation(parent: _navAnim, curve: Curves.easeOut);
    _orderButtonScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _orderButtonAnim, curve: Curves.easeInOut),
    );

    _pageCtrl = PageController(viewportFraction: 0.88);
    _startCarouselAutoPlay();

    _orderButtonAnim.repeat(reverse: true);

    Future.delayed(const Duration(milliseconds: 80), () {
      _heroAnim.forward();
      Future.delayed(
        const Duration(milliseconds: 350),
        () => _navAnim.forward(),
      );
      for (int i = 0; i < _cardAnims.length; i++) {
        Future.delayed(Duration(milliseconds: 400 + i * 80), () {
          if (mounted) _cardAnims[i].forward();
        });
      }
    });

    _loadOrders();
    _loadCategories();
    _loadFavourites();
    _loadFeatured();
  }

  Future<void> _loadFeatured() async {
    if (mounted) {
      setState(() {
        _featuredLoading = true;
        _featuredError = null;
      });
    }
    try {
      final page = await CatalogueService().load(limit: 4);
      const gradients = [
        [Color(0xFFFF6B35), Color(0xFFFF3B00)],
        [Color(0xFF10B981), Color(0xFF059669)],
        [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        [Color(0xFFF59E0B), Color(0xFFD97706)],
      ];
      final mapped = page.items.asMap().entries.map((entry) {
        final product = entry.value;
        return <String, dynamic>{
          'title': product['name'],
          'sub': 'From the catalogue',
          'price': (product['price'] as num).toStringAsFixed(2),
          'emoji': _catEmoji(product['category']?.toString() ?? ''),
          'imageUrl': product['image_url']?.toString() ?? '',
          'gradient': gradients[entry.key % gradients.length],
          'product': product,
        };
      }).toList();
      if (mounted) {
        setState(() {
          _featured = mapped;
          _featuredIndex = 0;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _featuredError = 'Featured products could not be loaded. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _featuredLoading = false);
    }
  }

  Future<void> _loadFavourites() async {
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
      final favs =
          await _supabase
                  .from('favourite')
                  .select('product_id')
                  .eq('user_id', _userId!)
              as List;
      if (mounted) {
        setState(() => _favIds = favs.map((f) => f['product_id']).toSet());
      }
    } catch (_) {}
  }

  Future<void> _toggleFavourite(dynamic productId) async {
    if (_userId == null || int.tryParse(productId.toString()) == null) return;
    final pid = int.parse(productId.toString());
    final isFav = _favIds.contains(pid);
    setState(() {
      isFav ? _favIds.remove(pid) : _favIds.add(pid);
    });
    try {
      if (isFav) {
        await _supabase
            .from('favourite')
            .delete()
            .eq('user_id', _userId!)
            .eq('product_id', pid);
      } else {
        await _supabase.from('favourite').insert({
          'user_id': _userId!,
          'product_id': pid,
        });
      }
    } catch (_) {
      setState(() {
        isFav ? _favIds.add(pid) : _favIds.remove(pid);
      });
    }
  }

  @override
  void dispose() {
    _orderRefresh?.dispose();
    _carouselTimer?.cancel();
    _heroAnim.dispose();
    _navAnim.dispose();
    _orderButtonAnim.dispose();
    for (final c in _cardAnims) {
      c.dispose();
    }
    _scrollCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    if (_ordersBusy) {
      _ordersDirty = true;
      return;
    }
    _ordersBusy = true;
    _ordersError = null;
    setState(() => _ordersLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final userRecord = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .maybeSingle();
      if (userRecord == null) return;
      final data =
          await _supabase
                  .from('orders')
                  .select(
                    '*,order_refund_actions(status,amount),order_timeline_events(status,reason,created_at)',
                  )
                  .eq('user_id', userRecord['id'])
                  .order('created_at', ascending: false)
                  .limit(30)
              as List;
      if (mounted) setState(() => _orders = data.cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) {
        setState(
          () => _ordersError =
              'Order status could not be refreshed. Retry when connected.',
        );
      }
    } finally {
      _ordersBusy = false;
      if (_ordersDirty && mounted) {
        _ordersDirty = false;
        unawaited(_loadOrders());
      }
      if (mounted) setState(() => _ordersLoading = false);
    }
  }

  Future<void> _loadCategories() async {
    if (mounted) {
      setState(() {
        _categoriesLoading = true;
        _categoriesError = null;
      });
    }
    try {
      final data = await CatalogueService().categories();
      if (mounted) {
        final selected = productCtrl.category.value;
        final names = ['All', ...data.map((c) => c['name'] as String)];
        final index = names.indexWhere(
          (name) => name.toLowerCase().trim() == selected.toLowerCase().trim(),
        );
        setState(() {
          _dbCategories = data;
          _selectedCatIndex = index < 0 ? 0 : index;
        });
        if (index < 0) unawaited(productCtrl.selectCategory('All'));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _categoriesError = 'Categories could not be loaded. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _categoriesLoading = false);
    }
  }

  String get _userName =>
      (_supabase.auth.currentUser?.userMetadata?['name'] as String? ?? 'there')
          .split(' ')
          .first;

  String get _selectedCatName {
    final names = ['All', ..._dbCategories.map((c) => c['name'] as String)];
    return _selectedCatIndex < names.length ? names[_selectedCatIndex] : 'All';
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe this route to locale changes as Get translation lookups are global.
    Localizations.localeOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _kBg,
        drawer: const AppDrawer(role: 'customer'),
        extendBody: true,
        body: IndexedStack(
          index: _tab,
          children: [_homeTab(), _ordersTab(), _trackTab(), _profileTab()],
        ),
        floatingActionButton: _tab == 0 ? _buildFAB() : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    return FadeTransition(
      opacity: _navFade,
      child: SafeArea(
        child: Container(
          height: 72,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: _kPurple.withValues(alpha: 0.14),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _navItem(0, Icons.home_rounded, Icons.home_outlined, 'Home'),
              _navItem(
                1,
                Icons.receipt_long_rounded,
                Icons.receipt_long_outlined,
                'Orders',
              ),
              _navItem(2, Icons.bolt_rounded, Icons.bolt_outlined, 'TezRaftar'),
              _navItem(
                3,
                Icons.person_rounded,
                Icons.person_outline_rounded,
                'Me',
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
    IconData inactiveIcon,
    String label,
  ) {
    final sel = _tab == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _tab = index);
        if (index == 1) _loadOrders();
      },
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              sel ? activeIcon : inactiveIcon,
              color: sel ? _kPurple : _kTextSub,
              size: 24,
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              height: 4,
              width: sel ? 28 : 0,
              decoration: BoxDecoration(
                color: _kPurple,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: _kPurple.withValues(alpha: 0.15),
        border: Border.all(color: _kPurple.withValues(alpha: 0.30), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Get.to(() => const AIAssistantScreen()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(
                    'AI Assistant',
                    style: TextStyle(
                      color: _kPurple,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _homeTab() {
    return RefreshIndicator(
      color: _kPurple,
      backgroundColor: _kCard,
      onRefresh: () async {
        productCtrl.onInit();
        setState(() {});
      },
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeroBanner()),
          SliverToBoxAdapter(child: _buildFeaturedSection()),
          SliverToBoxAdapter(child: _buildCategoriesSection()),
          SliverToBoxAdapter(child: _buildProductsSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }

  Widget _buildHeroBanner() {
    return SlideTransition(
      position: _heroSlide,
      child: FadeTransition(
        opacity: _heroFade,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D3B12), Color(0xFF1B5E20), Color(0xFF388E3C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -40,
                right: -40,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                left: -60,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Builder(
                            builder: (ctx) => GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                Scaffold.of(ctx).openDrawer();
                              },
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.menu_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF6EE7B7),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'My Location',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white70,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => Get.to(() => NotificationsScreen()),
                            child: Obx(() {
                              final unread = notifCtrl.unreadCount.value;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                      Icons.notifications_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  if (unread > 0)
                                    Positioned(
                                      top: -4,
                                      right: -4,
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: _kPink,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _kPurple,
                                            width: 2,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$unread',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            }),
                          ),
                          const SizedBox(width: 10),
                          Obx(
                            () => GestureDetector(
                              onTap: () => Get.to(() => CartScreen()),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                      Icons.shopping_bag_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  if (cart.totalItems > 0)
                                    Positioned(
                                      top: -4,
                                      right: -4,
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: _kSaffron,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _kPurple,
                                            width: 2,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${cart.totalItems}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Hello, $_userName ',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'Poppins',
                                letterSpacing: -0.5,
                              ),
                            ),
                            const TextSpan(
                              text: '👋',
                              style: TextStyle(fontSize: 26),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      GestureDetector(
                        onTap: () => Get.to(() => const SearchScreen()),
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 16),
                              Icon(
                                Icons.search_rounded,
                                color: _kPurple.withValues(alpha: 0.6),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Search food, stores, cuisines...',
                                  style: TextStyle(
                                    color: _kTextSub,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.all(6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _kPurple,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.tune_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
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

  void _startCarouselAutoPlay() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageCtrl.hasClients || _featured.isEmpty) return;
      if (_pageCtrl.position.isScrollingNotifier.value) return;
      final nextPage = (_featuredIndex + 1) % _featured.length;
      _pageCtrl.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
      );
    });
  }

  Widget _buildFeaturedSection() {
    if (_featuredLoading) {
      return const SizedBox(
        height: 196,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_featuredError != null) {
      return Column(
        children: [
          Text(_featuredError!),
          TextButton(
            onPressed: _loadFeatured,
            child: const Text('Retry featured products'),
          ),
        ],
      );
    }
    if (_featured.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No featured products available.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
          child: Row(
            children: [
              const Text(
                'Featured',
                style: TextStyle(
                  color: _kText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kSaffron, Color(0xFFD97706)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'CATALOGUE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Get.to(() => const SearchScreen()),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See all',
                      style: TextStyle(
                        color: _kPurple,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: _kPurple,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        SizedBox(
          height: 196,
          child: PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _featuredIndex = i),
            itemCount: _featured.length,
            itemBuilder: (_, i) => _buildFeaturedCard(_featured[i], i),
          ),
        ),

        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _featured.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _featuredIndex == i ? 22 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: _featuredIndex == i
                    ? _kPurple
                    : _kPurple.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturedCard(Map<String, dynamic> item, int index) {
    final gradColors = item['gradient'] as List<Color>;
    return GestureDetector(
      onTap: () => Get.to(
        () => ProductDetailScreen(
          product: Map<String, dynamic>.from(item['product'] as Map),
        ),
      ),
      child: AnimatedScale(
        scale: _featuredIndex == index ? 1.0 : 0.95,
        duration: const Duration(milliseconds: 300),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: gradColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: gradColors[0].withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Builder(
                    builder: (_) {
                      final imageUrl = (item['imageUrl'] as String?) ?? '';
                      if (imageUrl.isEmpty) {
                        return Text(
                          item['emoji'] as String,
                          style: const TextStyle(fontSize: 72),
                        );
                      }
                      return Container(
                        width: 118,
                        height: 118,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.20),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: ProductImage(
                            imageUrl: imageUrl,
                            fit: BoxFit
                                .contain, // shows the real product photo, never crops
                            errorWidget: (_, __, ___) => Text(
                              item['emoji'] as String,
                              style: const TextStyle(fontSize: 60),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item['sub'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 170,
                      child: Text(
                        item['title'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'PKR ${item['price']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_rounded, size: 13),
                              const SizedBox(width: 3),
                              Text(
                                'View',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: gradColors[0],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesSection() {
    if (_categoriesLoading) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_categoriesError != null) {
      return Column(
        children: [
          Text(_categoriesError!),
          TextButton(
            onPressed: _loadCategories,
            child: const Text('Retry categories'),
          ),
        ],
      );
    }
    final cats = [
      <String, dynamic>{'name': 'All', 'image_url': null},
      ..._dbCategories,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 24, 22, 14),
          child: Text(
            'Categories',
            style: TextStyle(
              color: _kText,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: cats.length,
            itemBuilder: (_, i) {
              final c = cats[i];
              final name = c['name'] as String;
              final imageUrl = c['image_url'] as String?;
              final sel = _selectedCatIndex == i;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (name == 'Tailoring') {
                    Get.to(() => const TailoringScreen());
                    return;
                  }
                  setState(() => _selectedCatIndex = i);
                  unawaited(productCtrl.selectCategory(name));
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: sel
                                ? _kPurple
                                : _kPurple.withValues(alpha: 0.18),
                            width: sel ? 3 : 1.5,
                          ),
                          color: _kCardSub,
                          boxShadow: sel
                              ? [
                                  BoxShadow(
                                    color: _kPurple.withValues(alpha: 0.28),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        child: ClipOval(
                          child: imageUrl != null && imageUrl.isNotEmpty
                              ? ProductImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => _shimmerBox(64, 64),
                                  errorWidget: (_, __, ___) => Center(
                                    child: Text(
                                      _catEmoji(name),
                                      style: const TextStyle(fontSize: 28),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    _catEmoji(name),
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        style: TextStyle(
                          color: sel ? _kPurple : _kTextSub,
                          fontSize: 11,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _catEmoji(String name) {
    const map = {
      'All': '🛍️',
      'Food': '🍔',
      'Grocery': '🥦',
      'Pharmacy': '💊',
      'Thrift': '👗',
      'Preloved': '♻️',
      'Tailoring': '✂️',
    };
    return map[name] ?? '🛍️';
  }

  Widget _buildProductsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _selectedCatName == 'All' ? 'All Items' : _selectedCatName,
                style: const TextStyle(
                  color: _kText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Obx(
                () => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _kPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${productCtrl.getProductsByCategory(_selectedCatName).length} items',
                    style: const TextStyle(
                      color: _kPurple,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Obx(() {
            if (productCtrl.isLoading.value) return _buildShimmerGrid();
            if (productCtrl.error.value != null) {
              return Column(
                children: [
                  Text(productCtrl.error.value!),
                  TextButton(
                    onPressed: productCtrl.refreshProducts,
                    child: const Text('Retry'),
                  ),
                ],
              );
            }
            final products = productCtrl.getProductsByCategory(
              _selectedCatName,
            );
            return Column(
              children: [
                products.isEmpty
                    ? _buildEmptyState()
                    : _buildProductGrid(products),
                if (productCtrl.hasMore.value)
                  TextButton(
                    onPressed: productCtrl.loadingMore.value
                        ? null
                        : () => productCtrl.refreshProducts(loadMore: true),
                    child: const Text('Load more products'),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProductGrid(List products) {
    final List<Widget> leftCol = [];
    final List<Widget> rightCol = [];

    for (int i = 0; i < products.length; i++) {
      final animIndex = i % _cardAnims.length;
      final card = _buildProductCard(products[i], i, animIndex);
      if (i % 2 == 0) {
        leftCol.add(card);
      } else {
        rightCol.add(card);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: leftCol)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(children: [const SizedBox(height: 24), ...rightCol]),
        ),
      ],
    );
  }

  Widget _buildProductCard(dynamic p, int index, int animIndex) {
    final accents = [
      _kPurple,
      _kSaffron,
      _kGreen,
      _kPink,
      _kTeal,
      Color(0xFF8B5CF6),
    ];
    final accent = accents[index % accents.length];
    const double cardImageHeight =
        120; // compact, consistent size for every card — matches reference-style listing

    final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cardAnims[animIndex], curve: Curves.easeOutBack),
    );
    final slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _cardAnims[animIndex],
            curve: Curves.easeOutCubic,
          ),
        );

    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: slideAnim,
        child: GestureDetector(
          onTap: () => Get.to(
            () => ProductDetailScreen(
              product: {
                'id': p.id,
                'name': p.name,
                'price': p.price,
                'description': p.description,
                'image_url': p.imageUrl,
                'category': p.category,
                'vendor_id': p.vendorId,
              },
            ),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _kPurple.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  child: Stack(
                    children: [
                      SizedBox(
                        height:
                            cardImageHeight, // fixed, compact, same on every screen size
                        width: double.infinity,
                        child: Container(
                          width: double.infinity,
                          color: accent.withValues(alpha: 0.06),
                          child: p.imageUrl.isNotEmpty
                              ? ProductImage(
                                  imageUrl: p.imageUrl,
                                  fit: BoxFit
                                      .contain, // never crops — always shows the full photo
                                  placeholder: (_, __) => _shimmerBox(
                                    double.infinity,
                                    cardImageHeight,
                                  ),
                                  errorWidget: (_, __, ___) => _placeholderBox(
                                    accent,
                                    cardImageHeight,
                                    p.category,
                                  ),
                                )
                              : _placeholderBox(
                                  accent,
                                  cardImageHeight,
                                  p.category,
                                ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            p.category ?? 'Food',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          elevation: 4,
                          shadowColor: Colors.black26,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            splashColor: accent.withValues(alpha: 0.25),
                            onTap:
                                p.isPurchasable && !cart.checking.contains(p.id)
                                ? () async {
                                    HapticFeedback.mediumImpact();
                                    final added = await cart.addItem({
                                      'product_id': p.id,
                                      'name': p.name,
                                      'price': p.price,
                                      'image_url': p.imageUrl,
                                      'vendor_id': p.vendorId,
                                    });
                                    if (!added) {
                                      Get.snackbar(
                                        'Cart',
                                        cart.lastError.value,
                                      );
                                      return;
                                    }
                                    Get.snackbar(
                                      '',
                                      '${p.name} added to cart! 🛒',
                                      titleText: const SizedBox.shrink(),
                                      messageText: Text(
                                        '${p.name} added to cart! 🛒',
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
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: Icon(
                                Icons.add_rounded,
                                color: accent,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Obx(() {
                    final info = vendorInfoCtrl.infoFor(p.vendorId);
                    final pos = vendorInfoCtrl.customerPosition.value;
                    final nearest = info?.nearestBranch(
                      pos?.latitude,
                      pos?.longitude,
                    );
                    final ratingText = info?.rating != null
                        ? info!.rating!.toStringAsFixed(1)
                        : '—';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StockIndicator(product: p.toJson()),
                        Text(
                          p.name,
                          style: const TextStyle(
                            color: _kText,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (info != null && info.storeName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.storefront_rounded,
                                size: 11,
                                color: accent,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  info.storeName,
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (nearest != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 11,
                                color: _kTextSub,
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  '${nearest.branch.name} • ${nearest.distanceKm.toStringAsFixed(1)} km',
                                  style: TextStyle(
                                    color: _kTextSub,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Rs.${p.price}',
                              style: const TextStyle(
                                color: _kSaffron,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                _toggleFavourite(p.id);
                              },
                              child: Icon(
                                _favIds.contains(int.tryParse(p.id.toString()))
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: _kPink,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: _kSaffron,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              ratingText,
                              style: const TextStyle(
                                color: _kTextSub,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (info != null && info.reviewCount > 0) ...[
                              const SizedBox(width: 2),
                              Text(
                                '(${info.reviewCount})',
                                style: TextStyle(color: _kTextSub, fontSize: 9),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderBox(Color accent, double height, String? category) {
    final emojis = {
      'Food': '🍔',
      'Grocery': '🥦',
      'Pharmacy': '💊',
      'Thrift': '👗',
      'Tailoring': '✂️',
      'Preloved': '♻️',
      'Electronics': '💻',
    };

    final emoji = emojis[category] ?? '🍽️';
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.15),
            accent.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 44))),
    );
  }

  Widget _shimmerBox(double width, double height) {
    return Shimmer.fromColors(
      baseColor: _kCardSub,
      highlightColor: Colors.white,
      child: Container(width: width, height: height, color: _kCardSub),
    );
  }

  Widget _buildShimmerGrid() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              _shimmerCard(false),
              _shimmerCard(true),
              _shimmerCard(false),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              const SizedBox(height: 24),
              _shimmerCard(true),
              _shimmerCard(false),
              _shimmerCard(false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _shimmerCard(bool tall) {
    return Shimmer.fromColors(
      baseColor: _kCardSub,
      highlightColor: Colors.white,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        height: tall ? 200 : 160,
        decoration: BoxDecoration(
          color: _kCardSub,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          const Text('😔', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text(
            'Nothing here yet',
            style: TextStyle(
              color: _kText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No items in this category.',
            style: TextStyle(color: _kTextSub, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _ordersTab() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: Row(
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Orders',
                      style: TextStyle(
                        color: _kText,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Track your order history',
                      style: TextStyle(color: _kTextSub, fontSize: 13),
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _loadOrders,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _kPurple.withValues(alpha: 0.10),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      color: _kPurple,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_ordersError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(_ordersError!, style: const TextStyle(color: _kPink)),
            ),
          Expanded(
            child: _ordersLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: _kPurple,
                          strokeWidth: 2,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Fetching orders...',
                          style: TextStyle(color: _kTextSub, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : _orders.isEmpty
                ? _buildOrdersEmpty()
                : RefreshIndicator(
                    color: _kPurple,
                    onRefresh: _loadOrders,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                      physics: const BouncingScrollPhysics(),
                      itemCount: _orders.length,
                      itemBuilder: (_, i) => _buildOrderCard(_orders[i], i),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersEmpty() {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 190,
              height: 190,
              child: Lottie.asset(
                'assets/lottie/home_delivery.json',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No orders yet',
              style: TextStyle(
                color: _kText,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your order history will appear here.',
              style: TextStyle(color: _kTextSub, fontSize: 14),
            ),
            const SizedBox(height: 32),
            ScaleTransition(
              scale: _orderButtonScale,
              child: GestureDetector(
                onTap: () => setState(() => _tab = 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kPurple, _kPurpleL],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _kPurple.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Start Ordering',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
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

  Widget _buildOrderCard(Map<String, dynamic> order, int index) {
    final status = order['order_status'] ?? 'placed';
    final amount = order['amount'] ?? 0;
    final rawId = order['id']?.toString() ?? '';
    final id = rawId.isEmpty
        ? '--------'
        : rawId.substring(0, rawId.length < 8 ? rawId.length : 8);

    final statusData = {
      'delivered': {'color': _kGreen, 'icon': '✅', 'label': 'Delivered'},
      'cancelled': {'color': _kPink, 'icon': '❌', 'label': 'Cancelled'},
      'on_the_way': {'color': _kTeal, 'icon': '🏍️', 'label': 'On the way'},
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
                        'Order #$id',
                        style: const TextStyle(
                          color: _kText,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'PKR $amount',
                        style: TextStyle(color: _kTextSub, fontSize: 13),
                      ),
                    ],
                  ),
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
              ],
            ),

            OrderTimeoutSummary(order: order),

            if (status == 'on_the_way') ...[
              const SizedBox(height: 14),
              Text(
                order['delivery_otp_email_status'] == 'accepted'
                    ? 'A delivery verification code has been sent to your registered email. Check your inbox and spam folder.'
                    : 'Your rider will request a verification code to your registered email when they arrive.',
                style: TextStyle(color: _kTextSub, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trackTab() {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TezRaftar',
              style: TextStyle(
                color: _kText,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Instant on-demand delivery',
              style: TextStyle(color: _kTextSub, fontSize: 14),
            ),

            const SizedBox(height: 28),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D3B12), _kPurple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kPurple.withValues(alpha: 0.35),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -10,
                    top: -10,
                    child: Text(
                      '⚡',
                      style: TextStyle(
                        fontSize: 90,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              '⚡',
                              style: TextStyle(fontSize: 26),
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Instant Rider',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Nearest rider in under 5 min',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Obx(
                        () => GestureDetector(
                          onTap: tezCtrl.isSearching.value
                              ? null
                              : () => tezCtrl.placeOrder(
                                  lat: 33.6844,
                                  lng: 73.0479,
                                  fare: 250,
                                ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Center(
                              child: tezCtrl.isSearching.value
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            color: _kPurple,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        const Text(
                                          'Searching for rider...',
                                          style: TextStyle(
                                            color: _kPurple,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '🏍️',
                                          style: TextStyle(fontSize: 18),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Request TezRider',
                                          style: TextStyle(
                                            color: _kPurple,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            GestureDetector(
              onTap: () => Get.to(() => const MapScreen()),
              child: Container(
                padding: const EdgeInsets.all(20),
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
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _kTeal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text('🗺️', style: TextStyle(fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Open Live Map',
                            style: TextStyle(
                              color: _kText,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Real-time delivery tracking',
                            style: TextStyle(color: _kTextSub, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: _kTextSub,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                _statChip('⏱️', 'Avg 5 min', _kGreen),
                const SizedBox(width: 10),
                _statChip('⭐', '4.9 rating', _kSaffron),
                const SizedBox(width: 10),
                _statChip('✅', 'Verified', _kTeal),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String emoji, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.20)),
          boxShadow: [
            BoxShadow(
              color: _kPurple.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileTab() {
    final user = _supabase.auth.currentUser;
    final name = user?.userMetadata?['name'] as String? ?? 'User';
    final email = user?.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 120),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D3B12), _kPurple, _kPurpleL],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kPurple.withValues(alpha: 0.30),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.40),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _profileBadge(
                            'Customer',
                            Colors.white.withValues(alpha: 0.20),
                            Colors.white,
                          ),
                          const SizedBox(width: 8),
                          _profileBadge(
                            '${_orders.length} orders',
                            Colors.white.withValues(alpha: 0.20),
                            Colors.white,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () => Get.to(() => const ProfileScreen()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Edit Profile',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
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
            ),

            const SizedBox(height: 24),

            _menuGroup('My Account', [
              _menuRow(
                '🕒',
                'Order History',
                _kPurple,
                () => Get.to(() => const OrderHistoryScreen()),
              ),
              _menuRow(
                '📍',
                'Saved Addresses',
                _kTeal,
                () => Get.to(() => const SavedAddressesScreen()),
              ),
              _menuRow(
                '💳',
                'Payment Methods',
                _kGreen,
                () => Get.to(() => const PaymentMethodsScreen()),
              ),
              _menuRow(
                '❤️',
                'Saved Stores',
                _kPink,
                () => Get.to(() => const SavedStoresScreen()),
              ),
              _menuRow(
                '💬',
                'Inbox / Chat',
                _kTeal,
                () => Get.to(() => const ChatRoomsScreen()),
              ),
            ]),

            const SizedBox(height: 16),

            _menuGroup('Support', [
              _menuRow(
                '⚖️',
                'Disputes',
                _kPink,
                () => Get.to(() => const DisputeHistoryScreen()),
              ),
              _menuRow(
                '💬',
                'Help Center',
                _kSaffron,
                () => Get.to(() => const HelpCenterScreen()),
              ),
              _menuRow(
                'ℹ️',
                'About TezRider',
                _kTeal,
                () => Get.to(() => const AboutTezRiderScreen()),
              ),
              _menuRow('⭐', 'Rate the App', _kPurple, () => _rateApp()),
            ]),

            const SizedBox(height: 28),

            GestureDetector(
              onTap: _confirmLogout,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _kPink.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _kPink.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🚪', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 10),
                    Text(
                      'Sign Out',
                      style: TextStyle(
                        color: _kPink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileBadge(String label, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _menuGroup(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: _kTextSub,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _kPurple.withValues(alpha: 0.07),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _menuRow(String emoji, String title, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: _kBg)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _kText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: _kTextSub, size: 13),
          ],
        ),
      ),
    );
  }

  Future<void> _rateApp() async {
    const androidUrl = 'market://details?id=pk.tezrider.app';
    const fallbackUrl =
        'https://play.google.com/store/apps/details?id=pk.tezrider.app';
    final uri = Uri.parse(androidUrl);
    final fallback = Uri.parse(fallbackUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  void _confirmLogout() {
    HapticFeedback.mediumImpact();
    Get.dialog(
      Dialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🚪', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              const Text(
                'Sign Out?',
                style: TextStyle(
                  color: _kText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'ll need to sign in again to access your account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _kTextSub, fontSize: 13),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Get.back(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _kBg,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: _kTextSub,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Get.back();
                        auth.logout();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _kPink.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _kPink.withValues(alpha: 0.30),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'Sign Out',
                            style: TextStyle(
                              color: _kPink,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
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
    );
  }
}
