import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../controllers/cart_controller.dart';
import '../../controllers/prescription_controller.dart';
import '../../controllers/product_controller.dart';
import '../../models/product_model.dart';
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
  State<EnhancedCheckoutScreen> createState() =>
      _EnhancedCheckoutScreenState();
}

class _EnhancedCheckoutScreenState extends State<EnhancedCheckoutScreen> {

  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();

  // 'cod' = Cash on Delivery, 'card' = Card / Online Payment
  final String _paymentMethod = 'cod';

  final PrescriptionController _prescriptionController =
      Get.find<PrescriptionController>();

  final ProductController _productController =
      Get.find<ProductController>();

  final _supabase = Supabase.instance.client;

  bool _isProcessing = false;

  double? _currentLat;
  double? _currentLng;

  final Map<String, bool> _prescriptionsUploaded = {};

  final Map<String, String?> _vendorOrderIds = {};

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

double _trackingProgress = 0;

bool _orderPicked = false;

bool _orderDelivered = false;

bool _trackingStarted = false;

Timer? _trackingTimer;
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

    _getCurrentLocation();

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
    _nameCtrl.text = user.userMetadata?['name'] ??
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

  void _startTracking() {
    if (_trackingStarted) return;

    _trackingStarted = true;
    _trackingProgress = 0;
    _orderPicked = false;
    _orderDelivered = false;

    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _trackingProgress = (_trackingProgress + 20).clamp(0, 100).toDouble();

        if (_trackingProgress >= 35) {
          _orderPicked = true;
        }

        if (_trackingProgress >= 100) {
          _orderDelivered = true;
          _trackingStarted = false;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
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
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      Get.snackbar("Location", "Please enable location.");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      Get.snackbar(
        "Permission",
        "Location permission permanently denied.",
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition();

    setState(() {
      _currentLat = position.latitude;
      _currentLng = position.longitude;
    });

    await _reverseGeocode(position.latitude, position.longitude);

  } catch (e) {
    debugPrint(e.toString());
  }
}

Future<void> _reverseGeocode(double lat, double lng) async {
  setState(() => _addressCtrl.text = 'Fetching address...');
  try {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
    );
    final res = await http.get(
      uri,
      headers: {'User-Agent': 'TezRiderApp/1.0'},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final displayName = data['display_name'] as String?;
      if (displayName != null && displayName.isNotEmpty && mounted) {
        setState(() => _addressCtrl.text = displayName);
        return;
      }
    }
  } catch (e) {
    debugPrint('Reverse geocode failed: $e');
  }
  if (mounted) {
    setState(() => _addressCtrl.text =
        'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}');
  }
}

Future<void> _selectLocationOnMap() async {

  await Get.dialog(

    Scaffold(

      appBar: AppBar(
        title: const Text("Select Delivery Location"),
      ),

      body: FlutterMap(

        options: MapOptions(

          initialCenter: LatLng(

            _currentLat ?? 33.6844,
            _currentLng ?? 73.0479,

          ),

          initialZoom: 15,

          onTap: (tapPosition, point) {

            setState(() {

              _currentLat = point.latitude;
              _currentLng = point.longitude;

            });

            Get.back();

            _reverseGeocode(point.latitude, point.longitude);

          },

        ),

        children: [

          TileLayer(

            urlTemplate:
                "https://tile.openstreetmap.org/{z}/{x}/{y}.png",

            userAgentPackageName:
                "com.example.flutter_application_1",

          ),

          MarkerLayer(

            markers: [

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

  _nearbyProducts = _productController.products.where((product) {

    return categories.contains(product.category.toLowerCase().trim()) &&
           !currentVendors.contains(product.vendorId);

  }).take(8).toList();
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

  _estimatedSaving =
      _singleRiderCharge - _twoRiderCharge;

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

    return _prescriptionsUploaded.values.every(
      (uploaded) => uploaded,
    );
  }

  /// Group cart items by vendor
  Map<String, List<Map<String, dynamic>>> _getVendorGroups() {
    final Map<String, List<Map<String, dynamic>>> vendorGroups = {};

    for (var item in widget.cart.cartItems) {
      final vId = item['vendor_id']?.toString() ?? '1';

      if (!vendorGroups.containsKey(vId)) {
        vendorGroups[vId] = [];
      }

      vendorGroups[vId]!.add(item);
    }

    return vendorGroups;
  }

  /// Create vendor order
  Future<String?> _createVendorOrder(
    String masterOrderId,
    String vendorId,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      double subTotal = items.fold(
        0,
        (sum, item) =>
            sum + ((item['price'] as num) * (item['qty'] ?? 1)),
      );

      bool requiresPrescription = items.any((item) {
        final productId = item['product_id']?.toString();

        if (productId == null) return false;

        final product = _productController.products.firstWhereOrNull(
          (p) => p.id == productId,
        );

        return product?.requiresPrescription ?? false;
      });

      final vendorOrderRes = await _supabase
          .from('vendor_orders')
          .insert({
            'order_id': masterOrderId,
            'vendor_id': int.tryParse(vendorId),
            'sub_total': subTotal,
            'status': requiresPrescription
                ? 'pending_prescription'
                : 'pending',
            'requires_prescription': requiresPrescription,
          })
          .select('id')
          .single();

      final vOrderId = vendorOrderRes['id'];

      final itemsToInsert = items
          .map(
            (item) => {
              'vendor_order_id': vOrderId,
              'product_id': item['product_id'] ?? 1,
              'quantity': item['qty'] ?? 1,
              'price_at_time': item['price'],
            },
          )
          .toList();

      if (itemsToInsert.isNotEmpty) {
        await _supabase.from('order_items').insert(itemsToInsert);
      }

      return vOrderId.toString();
    } catch (e) {
      debugPrint("CreateVendorOrder Error: $e");
      return null;
    }
  }
Future<void> _placeOrder() async {

  if (widget.cart.cartItems.isEmpty) {
    Get.snackbar(
      'Error',
      'Cart is empty',
    );
    return;
  }

  if (_nameCtrl.text.trim().isEmpty) {
    Get.snackbar('Error', 'Please enter your full name');
    return;
  }

  final phone = _phoneCtrl.text.trim();
  if (phone.isEmpty || phone.length < 10) {
    Get.snackbar('Error', 'Please enter a valid phone number');
    return;
  }

  final email = _emailCtrl.text.trim();
  final emailValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  if (!emailValid) {
    Get.snackbar('Error', 'Please enter a valid email address');
    return;
  }

  if (_addressCtrl.text.trim().isEmpty) {
    Get.snackbar(
      'Error',
      'Please enter delivery address',
    );
    return;
  }

  if (!_allPrescriptionsUploaded()) {
    Get.snackbar(
      'Prescription Required',
      'Please upload all required prescriptions before payment.',
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

        title: const Text("Multiple Vendors"),

        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            Text(
              "Your cart contains products from $_vendorCount different vendors.",
            ),

            const SizedBox(height:15),

            Text(
              "Estimated extra delivery charges: PKR ${_extraDelivery.toStringAsFixed(0)}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),

            const SizedBox(height:20),

            const Text(
              "You can continue with multiple vendors or buy from nearby vendors to reduce delivery charges.",
            ),

          ],
        ),

        actions: [

          TextButton(

            onPressed: () {

              Get.back(result: false);

            },

            child: const Text("Check Nearby Vendors"),

          ),

          ElevatedButton(

            onPressed: () {

              Get.back(result: true);

            },

            child: const Text("Continue"),

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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Text(
            "Nearby Vendor Suggestions",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 15),

         Expanded(
  child: _nearbyProducts.isEmpty
      ? const Center(
          child: Text(
            "No nearby vendors found",
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
                    Text("Vendor ID: ${product.vendorId}"),
                    Text("PKR ${product.price}"),
                  ],
                ),

                trailing: ElevatedButton(
                  onPressed: () {
                    Get.snackbar(
                      "Selected",
                      "${product.name} selected",
                    );
                  },
                  child: const Text("Select"),
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

    final vendorGroups = _getVendorGroups();

    final profile = await _supabase
        .from('users')
        .upsert({

      'email': _emailCtrl.text.trim(),

      'name': _nameCtrl.text.trim(),

      'phone': _phoneCtrl.text.trim(),

      'role': 'customer',

    }, onConflict: 'email')
        .select('id')
        .single();

    final customerId = profile['id'];

    // Cash on Delivery only — order is placed directly, no payment screen needed.
    await _finalizeOrder(customerId, vendorGroups);

  } catch (e) {

    Get.snackbar(
      "Error",
      "Failed to place order.\n$e",
    );

    setState(() {
      _isProcessing = false;
    });

  }

}

/// Creates the master order + per-vendor orders once payment (or COD
/// confirmation) is settled. Shared by both the COD path and the
/// card-payment success callback.
Future<void> _finalizeOrder(
  dynamic customerId,
  Map<String, List<Map<String, dynamic>>> vendorGroups,
) async {
  try {

    setState(() {
      _isProcessing = true;
    });

    // Create Master Order

final masterOrder = await _supabase
    .from('orders')
    .insert({
      'user_id': customerId,
      'amount': widget.cart.totalPrice + _totalDeliveryFee,
      'fare': _totalDeliveryFee,
      'delivery_speed': _deliverySpeed,
      'delivery_address': _addressCtrl.text.trim(),
      'delivery_lat': _currentLat ?? 33.6844,
      'delivery_lng': _currentLng ?? 73.0479,
      'order_status': 'pending',
      'payment_method': _paymentMethod,
      'has_prescription_items':
          _prescriptionsUploaded.isNotEmpty,
      'prescription_status':
          _prescriptionsUploaded.isEmpty
              ? 'none'
              : 'pending_verification',
    })
    .select('id')
    .single();

final masterOrderId = masterOrder['id'];



// Create Vendor Orders

for (final entry in vendorGroups.entries) {

  final vendorId = entry.key;

  final items = entry.value;

  final vendorOrderId = await _createVendorOrder(
    masterOrderId.toString(),
    vendorId,
    items,
  );

  if (vendorOrderId != null) {
    _vendorOrderIds[vendorId] = vendorOrderId;
  }
}




// Clear Cart

widget.cart.clear();

// Start Rider Tracking
_startTracking();

// Success Message

Get.back();

Get.snackbar(
  "Order Placed Successfully 🎉",

  _hasMultipleVendors
      ? "Order placed from $_vendorCount vendors.\nExtra delivery charges may apply."
      : "Your order has been placed successfully.",

  backgroundColor: Colors.green,
  colorText: Colors.white,
  duration: const Duration(seconds: 4),
);

} catch (e) {

  Get.snackbar(
    "Error",
    e.toString(),
  );

} finally {

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
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
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
  return Scaffold(
    appBar: AppBar(
      title: const Text("Checkout"),
      backgroundColor: _purple,
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          /// Contact Details
          const Text(
            "Contact Details",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              hintText: "Full name",
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
              hintText: "Phone number",
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
              hintText: "Email address",
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 25),

          /// Delivery Address
          const Text(
            "Delivery Address",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          TextField(
            controller: _addressCtrl,
            readOnly: true,
            decoration: InputDecoration(
              hintText: "Select delivery location",
              prefixIcon: const Icon(Icons.location_on),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [

                  IconButton(
                    icon: const Icon(Icons.my_location),
                    onPressed: _getCurrentLocation,
                  ),

                  IconButton(
                    icon: const Icon(Icons.map),
                    onPressed: _selectLocationOnMap,
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
          const Text(
            "Payment Method",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
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
                const Text(
                  'Cash on Delivery',
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

      const Row(

        children: [

          Icon(Icons.local_shipping,
              color: Colors.deepOrange),

          SizedBox(width: 8),

          Text(

            "Smart Rider Suggestion",

            style: TextStyle(

              fontWeight: FontWeight.bold,

              fontSize: 17,

            ),

          ),

        ],

      ),

      const SizedBox(height: 12),

      Text(

        "Products are coming from $_vendorCount different vendors.",

      ),

      const SizedBox(height: 10),

      Text(

        "One Rider Delivery",

        style: TextStyle(fontWeight: FontWeight.bold),

      ),

      Text(

        "Charges : PKR ${_singleRiderCharge.toStringAsFixed(0)}",

      ),

      Text(

        "ETA : ${_singleETA.toStringAsFixed(0)} mins",

      ),

      const SizedBox(height: 15),

      Text(

        "Two Rider Delivery",

        style: TextStyle(fontWeight: FontWeight.bold),

      ),

      Text(

        "Charges : PKR ${_twoRiderCharge.toStringAsFixed(0)}",

      ),

      Text(

        "ETA : ${_doubleETA.toStringAsFixed(0)} mins",

      ),

      const Divider(),

      Text(

        "You save PKR ${_estimatedSaving.toStringAsFixed(0)} and approximately ${( _singleETA - _doubleETA ).toStringAsFixed(0)} minutes by using 2 riders.",

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

        title: const Text(

          "Use Two Riders",

        ),

      ),

    ],

  ),

),

const SizedBox(height: 25),



          /// Prescription Section
          if (_prescriptionsUploaded.isNotEmpty) ...[
            const Text(
              "Prescription",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
          const Text(
            "Delivery Speed",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
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
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Subtotal"),
                      Text(
                        "PKR ${widget.cart.totalPrice.toStringAsFixed(0)}",
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Delivery Charges"),
                        Text(
                          "PKR ${_baseDeliveryFee.toStringAsFixed(0)}",
                        ),
                      ],
                    ),
                  ),

                  if (_speedFee > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Express Delivery"),
                          Text(
                            "PKR ${_speedFee.toStringAsFixed(0)}",
                          ),
                        ],
                      ),
                    ),

                  if (_extraDelivery > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Extra Delivery"),
                          Text(
                            "PKR ${_extraDelivery.toStringAsFixed(0)}",
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),

                  const Divider(),

                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [

                      const Text(
                        "Total",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),

                      Text(
                        "PKR ${(widget.cart.totalPrice + _totalDeliveryFee).toStringAsFixed(0)}",
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
                  ? const CircularProgressIndicator(
                      color: Colors.white,
                    )
                  : const Text(
                      "Place Order (Cash on Delivery)",
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                      ),
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