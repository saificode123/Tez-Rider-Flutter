import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../../controllers/cart_controller.dart';
import '../../controllers/prescription_controller.dart';
import '../../controllers/product_controller.dart';
import '../../models/product_model.dart';
import '../../services/order_timeout_service.dart';
import '../../services/delivery_destination.dart';
import '../../widgets/tez_map_tiles.dart';
import '../../widgets/prescription_upload_widget.dart';

class EnhancedCheckoutScreen extends StatefulWidget {
  final CartController cart;
  final String customerId;

  const EnhancedCheckoutScreen({
    super.key,
    required this.cart,
    required this.customerId,
  });

  @override
  State<EnhancedCheckoutScreen> createState() => _EnhancedCheckoutScreenState();
}

class _EnhancedCheckoutScreenState extends State<EnhancedCheckoutScreen> {
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();

  // 'cod' = Cash on Delivery, 'card' = Card / Online Payment

  final PrescriptionController _prescriptionController =
      Get.find<PrescriptionController>();

  final ProductController _productController = Get.find<ProductController>();

  final _supabase = Supabase.instance.client;

  bool _isProcessing = false;

  double? _currentLat;
  double? _currentLng;
  final _destination = DeliveryDestination();
  bool _selectingDestination = false;

  final Map<String, bool> _prescriptionsUploaded = {};

  late final _checkout = OrderCheckoutFlow(
    (request) async => Map<String, dynamic>.from(
      await _supabase
              .rpc('fr10_checkout', params: request)
              .timeout(const Duration(seconds: 15))
          as Map,
    ),
  );

  final MapController _mapController = MapController();

  final LatLng _currentLocation = const LatLng(33.6844, 73.0479);

  final bool _locationLoading = false;

  bool _useTwoRiders = false;

  static const Color _purple = Color(0xFF1B5E20);

  // ===== NEW VARIABLES =====

  bool _hasMultipleVendors = false;

  int _vendorCount = 0;

  double _extraDelivery = 0;

  static const double _baseDeliveryFee = 120;

  /// Delivery speed tier: 'standard' or 'express'
  String _deliverySpeed = 'standard';
  static const double _expressSurcharge = 90;

  double get _speedFee => _deliverySpeed == 'express' ? _expressSurcharge : 0;

  double get _totalDeliveryFee => _baseDeliveryFee + _extraDelivery + _speedFee;

  List<ProductModel> _nearbyProducts = [];
  // ================= RIDER TRACKING =================

  final LatLng _vendorLocation = const LatLng(33.7008, 72.9682);

  final LatLng _customerLocation = const LatLng(33.6844, 73.0479);

  final LatLng _riderLocation = const LatLng(33.7008, 72.9682);

  final LatLng _rider2Location = const LatLng(33.6940, 73.0200);

  bool _showTwoRiderSuggestion = false;

  double _singleRiderCharge = 0;

  double _twoRiderCharge = 0;

  double _estimatedSaving = 0;

  double _singleETA = 0;

  double _doubleETA = 0;

  @override
  void initState() {
    super.initState();

    _initializePrescriptionTracking();

    _checkMultipleVendors();

    _calculateDeliverySuggestion();

    _prefillContactInfo();
  }

  /// Pre-fills the contact fields from the logged-in user's auth record
  /// and, if one already exists, their saved profile row — so returning
  /// customers don't have to retype their details every time, but can
  /// still edit them for this order.
  Future<void> _prefillContactInfo() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _emailCtrl.text = user.email ?? '';
    _nameCtrl.text =
        user.userMetadata?['name'] ??
        (user.email != null ? user.email!.split('@').first : '');
    _phoneCtrl.text = user.userMetadata?['phone'] ?? '';

    try {
      final existing = await _supabase
          .from('users')
          .select('name, phone')
          .eq('email', user.email as Object)
          .maybeSingle();

      if (existing != null && mounted) {
        setState(() {
          if ((existing['name'] as String?)?.isNotEmpty ?? false) {
            _nameCtrl.text = existing['name'];
          }
          if ((existing['phone'] as String?)?.isNotEmpty ?? false) {
            _phoneCtrl.text = existing['phone'];
          }
        });
      }
    } catch (e) {
      debugPrint("Prefill contact info error: $e");
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  /// Detect multiple vendors in cart
  void _checkMultipleVendors() {
    final vendors = widget.cart.cartItems
        .map((e) => e['vendor_id'].toString())
        .toSet();

    _vendorCount = vendors.length;

    _hasMultipleVendors = _vendorCount > 1;

    if (_hasMultipleVendors) {
      _extraDelivery = (_vendorCount - 1) * 80;

      _loadNearbyVendorProducts();
    }
  }

  Future<void> _getCurrentLocation() async {
    if (_selectingDestination || _isProcessing) return;
    setState(() => _selectingDestination = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        Get.snackbar("Location".tr, "Please enable location.".tr);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        Get.snackbar(
          "Permission".tr,
          "Location permission permanently denied.".tr,
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (position.accuracy > 100 ||
          DateTime.now().difference(position.timestamp).abs() >
              const Duration(seconds: 30)) {
        throw StateError('Waiting for a fresh, accurate location.');
      }
      await _confirmDestination(
        position.latitude,
        position.longitude,
        'my_location',
      );
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          "Location unavailable".tr,
          "Choose a map pin or retry My Location.".tr,
        );
      }
    } finally {
      if (mounted) setState(() => _selectingDestination = false);
    }
  }

  Future<void> _confirmDestination(
    double lat,
    double lng,
    String source,
  ) async {
    if (!mounted) return;
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text("Confirm delivery destination".tr),
        content: Text(
          "Deliver to this @slot0end?\n@slot1end, @slot2end".uiTr({
            "slot0end":
                (source == 'my_location' ? 'current location' : 'map pin')
                    .toString(),
            "slot1end": (lat.toStringAsFixed(5)).toString(),
            "slot2end": (lng.toStringAsFixed(5)).toString(),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text("Cancel".tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text("Confirm destination".tr),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _destination.confirm(lat, lng, source);
    setState(() {
      _currentLat = lat;
      _currentLng = lng;
      _addressCtrl.text =
          'Confirmed delivery pin: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    });
  }

  Future<void> _selectLocationOnMap() async {
    if (_selectingDestination || _isProcessing) return;
    setState(() => _selectingDestination = true);
    final point = await Get.dialog<LatLng>(
      Scaffold(
        appBar: AppBar(title: Text("Select Delivery Location".tr)),

        body: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(
              _currentLat ?? 33.6844,
              _currentLng ?? 73.0479,
            ),

            initialZoom: 15,

            onTap: (tapPosition, point) {
              Get.back(result: point);
            },
          ),

          children: [
            TileLayer(
              urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",

              userAgentPackageName: "com.example.flutter_application_1",
              tileProvider: tezMapTiles(),
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),

            MarkerLayer(
              markers: [
                if (_destination.confirmed)
                  Marker(
                    point: LatLng(
                      _currentLat ?? 33.6844,
                      _currentLng ?? 73.0479,
                    ),

                    width: 45,

                    height: 45,

                    child: const Icon(
                      Icons.location_pin,

                      color: Colors.red,

                      size: 40,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (point != null && mounted) {
      await _confirmDestination(point.latitude, point.longitude, 'map_pin');
    }
    if (mounted) setState(() => _selectingDestination = false);
  }

  /// Load same-category products from all vendors
  void _loadNearbyVendorProducts() {
    final productIds = widget.cart.cartItems
        .map((e) => e['product_id'].toString())
        .toList();

    final categories = _productController.products
        .where((p) => productIds.contains(p.id))
        .map((p) => p.category.toLowerCase().trim())
        .toSet();

    // Vendors already present in cart
    final currentVendors = widget.cart.cartItems
        .map((e) => e['vendor_id'].toString())
        .toSet();

    _nearbyProducts = _productController.products
        .where((product) {
          return categories.contains(product.category.toLowerCase().trim()) &&
              !currentVendors.contains(product.vendorId);
        })
        .take(8)
        .toList();
    debugPrint("Nearby Products Count: ${_nearbyProducts.length}");

    for (var p in _nearbyProducts) {
      debugPrint(
        "Product: ${p.name} | Vendor: ${p.vendorId} | Category: ${p.category}",
      );
    }
  }

  void _calculateDeliverySuggestion() {
    if (!_hasMultipleVendors) return;

    _singleRiderCharge = 220 + (_vendorCount * 40);

    _twoRiderCharge = 280;

    _singleETA = 60;

    _doubleETA = 35;

    _estimatedSaving = _singleRiderCharge - _twoRiderCharge;

    if (_estimatedSaving > 0) {
      _showTwoRiderSuggestion = true;
    }
  }

  /// Initialize prescription tracking
  void _initializePrescriptionTracking() {
    final Map<String, List<Map<String, dynamic>>> vendorGroups = {};

    for (var item in widget.cart.cartItems) {
      final vId = item['vendor_id']?.toString() ?? '1';

      if (!vendorGroups.containsKey(vId)) {
        vendorGroups[vId] = [];
      }

      vendorGroups[vId]!.add(item);
    }

    for (var entry in vendorGroups.entries) {
      final vendorId = entry.key;

      final hasPrescriptionItems = entry.value.any((item) {
        final productId = item['product_id']?.toString();

        if (productId == null) return false;

        final product = _productController.products.firstWhereOrNull(
          (p) => p.id == productId,
        );

        return product?.requiresPrescription ?? false;
      });

      if (hasPrescriptionItems) {
        _prescriptionsUploaded[vendorId] = false;
      }
    }
  }

  /// Check all prescriptions uploaded
  bool _allPrescriptionsUploaded() {
    if (_prescriptionsUploaded.isEmpty) return true;

    return _prescriptionsUploaded.values.every((uploaded) => uploaded);
  }

  Future<void> _placeOrder() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await _placeValidatedOrder();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _placeValidatedOrder() async {
    if (!widget.cart.synchronizationReady) {
      Get.snackbar(
        "Cart synchronization required".tr,
        "Restore or retry your saved cart before placing an order.".tr,
      );
      return;
    }
    if (widget.cart.cartItems.isEmpty) {
      Get.snackbar("Error".tr, "Cart is empty".tr);
      return;
    }

    if (_nameCtrl.text.trim().isEmpty) {
      Get.snackbar("Error".tr, "Please enter your full name".tr);
      return;
    }

    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      Get.snackbar("Error".tr, "Please enter a valid phone number".tr);
      return;
    }

    final email = _emailCtrl.text.trim();
    final emailValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!emailValid) {
      Get.snackbar("Error".tr, "Please enter a valid email address".tr);
      return;
    }

    if (!_destination.confirmed || _selectingDestination) {
      Get.snackbar(
        "Delivery destination".tr,
        "Confirm My Location or a map pin before placing your order.".tr,
      );
      return;
    }

    if (!_allPrescriptionsUploaded()) {
      Get.snackbar(
        "Prescription Required".tr,
        "Please upload all required prescriptions before payment.".tr,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    // ==========================
    // MULTIPLE VENDOR WARNING
    // ==========================

    if (_hasMultipleVendors) {
      final proceed = await Get.dialog<bool>(
        AlertDialog(
          title: Text("Multiple Vendors".tr),

          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Your cart contains products from @slot0end different vendors."
                    .uiTr({"slot0end": (_vendorCount).toString()}),
              ),

              const SizedBox(height: 15),

              Text(
                "Estimated extra delivery charges: PKR @slot0end".uiTr({
                  "slot0end": (_extraDelivery.toStringAsFixed(0)).toString(),
                }),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),

              const SizedBox(height: 20),

              Text(
                "You can continue with multiple vendors or buy from nearby vendors to reduce delivery charges."
                    .tr,
              ),
            ],
          ),

          actions: [
            TextButton(
              onPressed: () {
                Get.back(result: false);
              },

              child: Text("Check Nearby Vendors".tr),
            ),

            ElevatedButton(
              onPressed: () {
                Get.back(result: true);
              },

              child: Text("Continue".tr),
            ),
          ],
        ),
      );

      if (proceed != true) {
        Get.bottomSheet(
          Container(
            height: 400,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Nearby Vendor Suggestions".tr,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 15),

                Expanded(
                  child: _nearbyProducts.isEmpty
                      ? Center(
                          child: Text(
                            "No nearby vendors found".tr,
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _nearbyProducts.length,
                          itemBuilder: (context, index) {
                            final product = _nearbyProducts[index];

                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.store),

                                title: Text(product.name),

                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(product.category),
                                    Text(
                                      "Vendor ID: @slot0end".uiTr({
                                        "slot0end": (product.vendorId)
                                            .toString(),
                                      }),
                                    ),
                                    Text(
                                      "PKR @slot0end".uiTr({
                                        "slot0end": (product.price).toString(),
                                      }),
                                    ),
                                  ],
                                ),

                                trailing: ElevatedButton(
                                  onPressed: () {
                                    Get.snackbar(
                                      "Selected".tr,
                                      "@slot0end selected".uiTr({
                                        "slot0end": (product.name).toString(),
                                      }),
                                    );
                                  },
                                  child: Text("Select".tr),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );

        return;
      }
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      if (_currentLat == null || _currentLng == null) {
        throw StateError(
          'Your delivery location is unavailable. Allow location access and retry.',
        );
      }
      await _checkout.place(
        widget.cart.cartItems
            .map(
              (item) => {
                'product_id': int.parse(item['product_id'].toString()),
                'quantity': (item['qty'] as num?)?.toInt() ?? 1,
              },
            )
            .toList(),
        {
          'address': _addressCtrl.text.trim(),
          'lat': _currentLat,
          'lng': _currentLng,
          'speed': _deliverySpeed,
          ..._destination.provenance,
        },
      );
      final cartCleared = await widget.cart.clear();
      if (mounted) {
        Get.back();
        Get.snackbar(
          "Order placed".tr,
          cartCleared
              ? "Order placed! Awaiting vendor confirmation.".tr
              : "Order placed. Cart synchronization is pending; retry it before placing another order."
                    .tr,
        );
      }
    } catch (e) {
      if (e is CheckoutStockShortage) {
        await widget.cart.refreshAvailability();
        if (!mounted) return;
        final adjust = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("Stock changed".tr),
            content: SingleChildScrollView(
              child: Text(
                e.products
                    .map(
                      (p) =>
                          '${p['name']}: requested ${p['requested']}, available ${p['available']}',
                    )
                    .join('\n'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text("Keep cart".tr),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text("Adjust quantities".tr),
              ),
            ],
          ),
        );
        if (adjust == true) await widget.cart.applyShortages(e.products);
        if (mounted) Get.back(); // Return to the existing cart for review.
        return;
      }
      final message = e is PostgrestException
          ? e.message
          : e is StateError
          ? e.message
          : 'Order placement could not be confirmed. Check your connection and retry with the same cart.';
      Get.snackbar("Order not confirmed".tr, message);

      setState(() {
        _isProcessing = false;
      });
    }
  }

  Widget _speedOption({
    required String value,
    required String title,
    required String subtitle,
    required String priceLabel,
  }) {
    final selected = _deliverySpeed == value;
    return InkWell(
      onTap: () => setState(() => _deliverySpeed = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? Colors.green.withValues(alpha: 0.06) : Colors.white,
          border: Border.all(
            color: selected ? Colors.green : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? Colors.green : Colors.grey,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              priceLabel,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: selected ? Colors.green : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      appBar: AppBar(title: Text("Checkout".tr), backgroundColor: _purple),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Contact Details
            Text(
              "Contact Details".tr,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: "Full name".tr,
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: "Phone number".tr,
                prefixIcon: const Icon(Icons.phone_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: "Email address".tr,
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 25),

            /// Delivery Address
            Text(
              "Delivery Address".tr,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: _addressCtrl,
              readOnly: true,
              decoration: InputDecoration(
                hintText: "Select delivery location".tr,
                prefixIcon: const Icon(Icons.location_on),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.my_location),
                      tooltip: "My Location".tr,
                      onPressed: _isProcessing || _selectingDestination
                          ? null
                          : _getCurrentLocation,
                    ),

                    IconButton(
                      icon: const Icon(Icons.map),
                      tooltip: "Choose delivery pin".tr,
                      onPressed: _isProcessing || _selectingDestination
                          ? null
                          : _selectLocationOnMap,
                    ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 25),

            /// Payment Method
            Text(
              "Payment Method".tr,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                color: _purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _purple, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.payments_outlined, color: _purple),
                  const SizedBox(width: 12),
                  Text(
                    "Cash on Delivery".tr,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            if (_showTwoRiderSuggestion)
              Container(
                margin: const EdgeInsets.only(top: 18),

                padding: const EdgeInsets.all(18),

                decoration: BoxDecoration(
                  color: Colors.orange.shade50,

                  borderRadius: BorderRadius.circular(16),

                  border: Border.all(color: Colors.orange),
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_shipping, color: Colors.deepOrange),

                        SizedBox(width: 8),

                        Text(
                          "Smart Rider Suggestion".tr,

                          style: TextStyle(
                            fontWeight: FontWeight.bold,

                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Text(
                      "Products are coming from @slot0end different vendors."
                          .uiTr({"slot0end": (_vendorCount).toString()}),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      "One Rider Delivery".tr,

                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),

                    Text(
                      "Charges : PKR @slot0end".uiTr({
                        "slot0end": (_singleRiderCharge.toStringAsFixed(
                          0,
                        )).toString(),
                      }),
                    ),

                    Text(
                      "ETA : @slot0end mins".uiTr({
                        "slot0end": (_singleETA.toStringAsFixed(0)).toString(),
                      }),
                    ),

                    const SizedBox(height: 15),

                    Text(
                      "Two Rider Delivery".tr,

                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),

                    Text(
                      "Charges : PKR @slot0end".uiTr({
                        "slot0end": (_twoRiderCharge.toStringAsFixed(
                          0,
                        )).toString(),
                      }),
                    ),

                    Text(
                      "ETA : @slot0end mins".uiTr({
                        "slot0end": (_doubleETA.toStringAsFixed(0)).toString(),
                      }),
                    ),

                    const Divider(),

                    Text(
                      "You save PKR @slot0end and approximately @slot1end minutes by using 2 riders."
                          .uiTr({
                            "slot0end": (_estimatedSaving.toStringAsFixed(
                              0,
                            )).toString(),
                            "slot1end":
                                ((_singleETA - _doubleETA).toStringAsFixed(
                                  0,
                                )).toString(),
                          }),

                      style: const TextStyle(
                        color: Colors.green,

                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    SwitchListTile(
                      value: _useTwoRiders,

                      onChanged: (v) {
                        setState(() {
                          _useTwoRiders = v;
                        });
                      },

                      title: Text("Use Two Riders".tr),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 25),

            /// Prescription Section
            if (_prescriptionsUploaded.isNotEmpty) ...[
              Text(
                "Prescription".tr,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              PrescriptionUploadWidget(
                vendorOrderId: "",
                customerId: widget.customerId,
                onUploadSuccess: () {
                  setState(() {
                    _prescriptionsUploaded.updateAll((key, value) => true);
                  });
                },
              ),

              const SizedBox(height: 25),
            ],

            /// Delivery Speed
            Text(
              "Delivery Speed".tr,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            _speedOption(
              value: 'standard',
              title: 'Standard Delivery',
              subtitle: 'Arrives in ~30-45 min',
              priceLabel: 'Included',
            ),

            const SizedBox(height: 10),

            _speedOption(
              value: 'express',
              title: 'Express Delivery',
              subtitle: 'Priority rider · arrives in ~15-20 min',
              priceLabel: '+ PKR ${_expressSurcharge.toStringAsFixed(0)}',
            ),

            const SizedBox(height: 25),

            /// Order Summary
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Subtotal".tr),
                        Text(
                          "PKR @slot0end".uiTr({
                            "slot0end": (widget.cart.totalPrice.toStringAsFixed(
                              0,
                            )).toString(),
                          }),
                        ),
                      ],
                    ),

                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text("Delivery Charges".tr)),
                          Text(
                            "PKR @slot0end".uiTr({
                              "slot0end": (_baseDeliveryFee.toStringAsFixed(
                                0,
                              )).toString(),
                            }),
                          ),
                        ],
                      ),
                    ),

                    if (_speedFee > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text("Express Delivery".tr)),
                            Text(
                              "PKR @slot0end".uiTr({
                                "slot0end": (_speedFee.toStringAsFixed(
                                  0,
                                )).toString(),
                              }),
                            ),
                          ],
                        ),
                      ),

                    if (_extraDelivery > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Extra Delivery".tr),
                            Text(
                              "PKR @slot0end".uiTr({
                                "slot0end": (_extraDelivery.toStringAsFixed(
                                  0,
                                )).toString(),
                              }),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),

                    const Divider(),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Total".tr,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),

                        Text(
                          "PKR @slot0end".uiTr({
                            "slot0end":
                                ((widget.cart.totalPrice + _totalDeliveryFee)
                                        .toStringAsFixed(0))
                                    .toString(),
                          }),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _placeOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        "Place Order (Cash on Delivery)".tr,
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
