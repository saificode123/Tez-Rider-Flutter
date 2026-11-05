import '../../services/saved_addresses_service.dart';
import '../../widgets/spatial_surface.dart';
import '../../theme/app_theme.dart';

import 'package:flutter_application_1/core/stage2_ui_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../../controllers/cart_controller.dart';
import '../../controllers/product_controller.dart';
import '../../services/order_timeout_service.dart';
import '../../services/checkout_request_store.dart';
import '../../services/delivery_destination.dart';
import '../../widgets/tez_map_tiles.dart';
import 'order_detail_screen.dart';

class EnhancedCheckoutScreen extends StatefulWidget {
  final CartController cart;
  final String customerId;
  final SavedAddressesService? savedAddressesService;

  const EnhancedCheckoutScreen({
    super.key,
    required this.cart,
    required this.customerId,
    this.savedAddressesService,
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

  final ProductController _productController = Get.find<ProductController>();

  final _supabase = Supabase.instance.client;

  bool _isProcessing = false;

  double? _currentLat;
  double? _currentLng;
  var _destination = DeliveryDestination();
  late final SavedAddressesService _savedAddresses;
  bool _choosingSavedAddress = false;
  bool _selectingDestination = false;

  final Map<String, bool> _prescriptionsUploaded = {};

  late final _checkout = OrderCheckoutFlow(
    (request) async => Map<String, dynamic>.from(
      await _supabase
              .rpc('fr10_checkout', params: request)
              .timeout(const Duration(seconds: 15))
          as Map,
    ),
    store: SecureCheckoutRequestStore(expectedAccount: widget.customerId),
  );

  static const Color _purple = AppColors.primary;

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

  @override
  void initState() {
    super.initState();
    _savedAddresses = widget.savedAddressesService ?? SavedAddressesService();

    _initializePrescriptionTracking();

    _checkMultipleVendors();

    _restoreCheckout();
  }

  Future<void> _restoreCheckout() async {
    _isProcessing = true;
    try {
      await _prefillContactInfo();
      final saved = await _checkout.restore();
      if (!mounted || saved == null) return;
      final delivery = Map<String, dynamic>.from(saved['p_delivery'] as Map);
      final lat = (delivery['lat'] as num).toDouble();
      final lng = (delivery['lng'] as num).toDouble();
      if (delivery['destination_confirmed'] != true ||
          !const ['standard', 'express'].contains(delivery['speed'])) {
        throw StateError('Saved checkout requires review.');
      }
      _destination.confirm(lat, lng, delivery['destination_source'] as String);
      _currentLat = lat;
      _currentLng = lng;
      _addressCtrl.text = delivery['address'] as String;
      _deliverySpeed = delivery['speed'] as String;
      // Restores the customer's prior explicit confirmation, never a GPS fix.
    } catch (_) {
      if (mounted) {
        Get.snackbar(
          'Checkout'.tr,
          'Checkout recovery could not be confirmed. Retry before placing an order.'
              .tr,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
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
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

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
    String source, {
    String? expectedOwner,
  }) async {
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
    if (!mounted ||
        confirmed != true ||
        expectedOwner != null && _savedAddresses.identity() != expectedOwner) {
      return;
    }
    _destination.confirm(lat, lng, source);
    setState(() {
      _currentLat = lat;
      _currentLng = lng;
      // A map confirmation changes coordinates, never the customer's written
      // house/street details. Both are required independently at checkout.
    });
  }

  Future<void> _selectLocationOnMap() async {
    if (_selectingDestination || _isProcessing) return;
    setState(() => _selectingDestination = true);
    final point = await Get.dialog<LatLng>(
      Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          title: Text("Select Delivery Location".tr),
        ),

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

  Future<void> _chooseSavedAddress() async {
    if (_isProcessing || _selectingDestination || _choosingSavedAddress) return;
    final owner = _savedAddresses.identity();
    if (owner == null) return;
    setState(() => _choosingSavedAddress = true);
    try {
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            _CheckoutSavedAddressPicker(service: _savedAddresses, owner: owner),
      );
      if (!mounted || selected == null || _savedAddresses.identity() != owner) {
        return;
      }
      setState(() {
        _addressCtrl.text = selected['address'] as String;
        // A different written address must never inherit an older destination.
        _destination = DeliveryDestination();
        _currentLat = null;
        _currentLng = null;
      });
      final lat = selected['latitude'];
      final lng = selected['longitude'];
      final confirmedAt = selected['location_confirmed_at'];
      if (lat is num &&
          lng is num &&
          lat.isFinite &&
          lng.isFinite &&
          lat.abs() <= 90 &&
          lng.abs() <= 180 &&
          confirmedAt is String &&
          DateTime.tryParse(confirmedAt) != null) {
        await _confirmDestination(
          lat.toDouble(),
          lng.toDouble(),
          'map_pin',
          expectedOwner: owner,
        );
      }
    } finally {
      if (mounted) setState(() => _choosingSavedAddress = false);
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

  Future<void> _placeOrder() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await _submitOrder();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _submitOrder() async {
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

    final address = _addressCtrl.text.trim();
    if (address.isEmpty ||
        address.startsWith('Confirmed delivery pin:') ||
        address.length > 2000 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(address)) {
      Get.snackbar(
        'Delivery Address'.tr,
        'Enter your house, street, area and city (up to 2000 characters).'.tr,
      );
      return;
    }

    if (_hasMultipleVendors) {
      final proceed = await Get.dialog<bool>(
        AlertDialog(
          title: Text('Multiple Vendors'.tr),
          content: Text(
            'Your cart contains products from @slot0end different vendors.'
                .uiTr({'slot0end': '$_vendorCount'}),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('Cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: Text('Continue'.tr),
            ),
          ],
        ),
      );
      if (!mounted || proceed != true) return;
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
      final placed = await _checkout.place(
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
      var recoveryCleared = false;
      if (cartCleared) {
        try {
          await _checkout.complete();
          recoveryCleared = true;
        } catch (_) {
          // Placement is confirmed even if local recovery cleanup fails.
        }
      }
      if (mounted) {
        Get.back();
        if (_prescriptionsUploaded.isNotEmpty) {
          Get.to(() => OrderDetailScreen(orderId: placed['order_id'] as int));
        }
        Get.snackbar(
          "Order placed".tr,
          cartCleared && recoveryCleared
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
      Get.snackbar("Order not confirmed".tr, message.uiMessage);

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
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : Colors.white,
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
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
              color: selected ? AppColors.primary : Colors.grey,
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
                  const SizedBox(height: 6),
                  Text(
                    priceLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: selected
                          ? AppColors.primary
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
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
      appBar: AppBar(
        toolbarHeight: 64,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        title: Text("Checkout".tr, style: const TextStyle(color: Colors.white)),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SpatialSurface(
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
                ],
              ),
            ),
            const SizedBox(height: 20),
            SpatialSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Delivery Address
                  Text(
                    "Delivery Address".tr,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 10),

                  OutlinedButton.icon(
                    onPressed:
                        _isProcessing ||
                            _selectingDestination ||
                            _choosingSavedAddress
                        ? null
                        : _chooseSavedAddress,
                    icon: const Icon(Icons.bookmark_outline_rounded),
                    label: Text('Use saved address'.tr),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressCtrl,
                    readOnly: _isProcessing,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      hintText: "House, street, area and city".tr,
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

                  const SizedBox(height: 10),
                  Text(
                    (_destination.confirmed
                            ? 'Delivery pin confirmed'
                            : 'Choose and confirm a delivery pin before checkout.')
                        .tr,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 25),
                ],
              ),
            ),
            const SizedBox(height: 20),

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
                  Expanded(
                    child: Text(
                      "Cash on Delivery".tr,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            Text(
              'Route and ETA become available after a Rider starts sharing the delivery location.'
                  .tr,
            ),
            const SizedBox(height: 25),

            /// Prescription Section
            if (_prescriptionsUploaded.isNotEmpty) ...[
              Text(
                "Prescription".tr,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              Text(
                'Place your order first. Upload the prescription securely from Order details; the Vendor reviews it before accepting the medicine order.'
                    .tr,
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
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 4,
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
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text("Delivery Charges".tr),
                          Text(
                            "PKR @slot0end".uiTr({
                              "slot0end": (_baseDeliveryFee.toStringAsFixed(0))
                                  .toString(),
                            }),
                          ),
                        ],
                      ),
                    ),

                    if (_speedFee > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text("Express Delivery".tr),
                            Text(
                              "PKR @slot0end".uiTr({
                                "slot0end": (_speedFee.toStringAsFixed(0))
                                    .toString(),
                              }),
                            ),
                          ],
                        ),
                      ),

                    if (_extraDelivery > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text("Extra Delivery".tr),
                            Text(
                              "PKR @slot0end".uiTr({
                                "slot0end": (_extraDelivery.toStringAsFixed(0))
                                    .toString(),
                              }),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),

                    const Divider(),

                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 4,
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
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _placeOrder,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(55),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  backgroundColor: _purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        "Place Order (Cash on Delivery)".tr,
                        textAlign: TextAlign.center,
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

/// Reads only the current customer's versioned saved-address service.
class _CheckoutSavedAddressPicker extends StatefulWidget {
  const _CheckoutSavedAddressPicker({
    required this.service,
    required this.owner,
  });
  final SavedAddressesService service;
  final String owner;
  @override
  State<_CheckoutSavedAddressPicker> createState() =>
      _CheckoutSavedAddressPickerState();
}

class _CheckoutSavedAddressPickerState
    extends State<_CheckoutSavedAddressPicker> {
  final List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _loadingMore = false, _hasMore = false;
  int? _cursor;
  String? _error;
  StreamSubscription<void>? _accountChanges;

  bool get _sameOwner => mounted && widget.service.identity() == widget.owner;

  @override
  void initState() {
    super.initState();
    _accountChanges = widget.service.accountChanges.listen((_) {
      if (mounted && !_sameOwner) Navigator.of(context).pop();
    });
    _load();
  }

  @override
  void dispose() {
    unawaited(_accountChanges?.cancel());
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (!_sameOwner || more && (_loadingMore || !_hasMore)) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final page = await widget.service.load(before: more ? _cursor : null);
      if (!_sameOwner) return;
      final rows = List<Map<String, dynamic>>.from(
        (page['items'] as List).map((row) => Map<String, dynamic>.from(row)),
      );
      setState(() {
        if (!more) _rows.clear();
        final seen = _rows.map((row) => row['id']).toSet();
        _rows.addAll(rows.where((row) => seen.add(row['id'])));
        _hasMore = page['has_more'] == true;
        _cursor = page['cursor'] as int?;
      });
    } catch (_) {
      if (_sameOwner) {
        setState(() => _error = 'Saved addresses could not be loaded. Retry.');
      }
    } finally {
      if (_sameOwner) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  bool _hasPin(Map<String, dynamic> row) {
    final lat = row['latitude'];
    final lng = row['longitude'];
    final timestamp = row['location_confirmed_at'];
    return lat is num &&
        lng is num &&
        lat.isFinite &&
        lng.isFinite &&
        lat.abs() <= 90 &&
        lng.abs() <= 180 &&
        timestamp is String &&
        DateTime.tryParse(timestamp) != null;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Use saved address'.tr,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('Confirm the delivery pin after selecting an address.'.tr),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!.tr, textAlign: TextAlign.center),
              TextButton.icon(
                onPressed: _loading || _loadingMore
                    ? null
                    : () => _load(more: _rows.isNotEmpty && _hasMore),
                icon: const Icon(Icons.refresh_rounded),
                label: Text('Retry addresses'.tr),
              ),
            ],
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? Center(
                      child: Text(
                        (_error == null
                                ? 'No saved addresses'
                                : 'Saved addresses are unavailable.')
                            .tr,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _rows.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, index) {
                        if (index == _rows.length) {
                          return TextButton(
                            onPressed: _loadingMore
                                ? null
                                : () => _load(more: true),
                            child: _loadingMore
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text('Load more addresses'.tr),
                          );
                        }
                        final row = _rows[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          leading: const Icon(
                            Icons.location_on_outlined,
                            color: AppColors.primary,
                          ),
                          title: Text(row['label'] as String),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row['address'] as String),
                              const SizedBox(height: 6),
                              Text(
                                (_hasPin(row)
                                        ? 'Saved delivery pin available'
                                        : 'No delivery pin saved')
                                    .tr,
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: !_sameOwner
                              ? null
                              : () => Navigator.of(context).pop(row),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
