import '../../theme/app_theme.dart';
import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'dart:async';
import '../../services/product_image_service.dart';
import '../../widgets/product_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import '../../services/inventory_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

const _kPurple = AppColors.primaryDark;
const _kBg = AppColors.bgLight;
const _kTextSub = AppColors.textSecondary;

class ProductFormScreen extends StatefulWidget {
  final int? vendorId;
  final Map<String, dynamic>? existing;
  final Future<XFile?> Function()? imagePicker;
  final ProductImageService? imageService;

  const ProductFormScreen({
    super.key,
    required this.vendorId,
    this.existing,
    this.imagePicker,
    this.imageService,
  });

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _supabase = Supabase.instance.client;
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _thresholdCtrl = TextEditingController(text: '5');
  final _inventory = InventoryWriteFlow();
  late final _images = widget.imageService ?? ProductImageService();
  String? _account;
  bool _accountChanged = false;
  StreamSubscription<AuthState>? _auth;
  int _stockVersion = 0;

  String _category = 'Food';
  bool _available = true;
  bool _saving = false;
  XFile? _selectedImage;

  bool get _isEditing => widget.existing != null;
  bool get _productLocked => _saving || _inventory.hasPending;
  bool get _imageLocked => _productLocked || _images.hasPendingUpload;

  List<Map<String, dynamic>> _dbCategories = [];
  bool _loadingCategories = true;

  @override
  void initState() {
    super.initState();
    _account = _supabase.auth.currentUser?.id;
    _auth = _supabase.auth.onAuthStateChange.listen((_) {
      if (_supabase.auth.currentUser?.id != _account && mounted) {
        for (final ctrl in [
          _nameCtrl,
          _descCtrl,
          _priceCtrl,
          _imageCtrl,
          _stockCtrl,
          _thresholdCtrl,
        ]) {
          ctrl.clear();
        }
        setState(() {
          _accountChanged = true;
          _selectedImage = null;
        });
      }
    });
    _loadCategories();

    if (_isEditing) {
      final p = widget.existing!;
      _nameCtrl.text = p['name'] ?? '';
      _descCtrl.text = p['description'] ?? '';
      _priceCtrl.text = p['price']?.toString() ?? '';
      _imageCtrl.text = p['image_url'] ?? '';
      _category = p['category'] ?? 'Food';
      _available = p['is_available'] ?? true;
      _stockCtrl.text = p['stock_confirmed'] == true
          ? p['stock_qty'].toString()
          : '';
      _thresholdCtrl.text = (p['low_stock_threshold'] ?? 5).toString();
      _stockVersion = (p['stock_version'] as num?)?.toInt() ?? 0;
    }
  }

  Future<void> _loadCategories() async {
    try {
      final data = await _supabase
          .from('categories')
          .select('name, image_url')
          .order('sort_order');

      if (mounted) {
        setState(() {
          _dbCategories = List<Map<String, dynamic>>.from(data);
          _loadingCategories = false;
        });

        // Editing ke time saved category select karna
        if (_isEditing) {
          final p = widget.existing!;
          _category = p['category'] ?? 'Food';
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingCategories = false);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_auth?.cancel());
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _imageCtrl.dispose();
    _stockCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final image = widget.imagePicker != null
          ? await widget.imagePicker!()
          : await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 80,
              maxWidth: 2048,
              maxHeight: 2048,
            );
      if (image != null && mounted && !_accountChanged) {
        setState(() => _selectedImage = image);
      }
    } catch (_) {
      if (mounted) {
        Get.snackbar(
          "Image not selected".tr,
          "Allow photo access or choose another image, then retry.".tr,
        );
      }
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _accountChanged ||
        _account == null ||
        _supabase.auth.currentUser?.id != _account) {
      return;
    }
    final stock = ProductStock.nonnegativeInteger(_stockCtrl.text);
    final threshold = ProductStock.nonnegativeInteger(_thresholdCtrl.text);
    final price = double.tryParse(_priceCtrl.text.trim());
    if (_nameCtrl.text.trim().isEmpty ||
        price == null ||
        !price.isFinite ||
        price < 0 ||
        stock == null ||
        threshold == null) {
      Get.snackbar(
        "Review product".tr,
        "Enter a name, valid price, confirmed whole-number stock and nonnegative threshold."
            .tr,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      var imageUrl = _imageCtrl.text.trim();
      if (_selectedImage != null) {
        imageUrl = await _images.upload(await _selectedImage!.readAsBytes());
      }
      if (_accountChanged || _supabase.auth.currentUser?.id != _account) {
        throw StateError('Account changed. Open the product again.');
      }
      final result = await _inventory.save('fr17_save_product', {
        'p_product_id': widget.existing?['id'],
        'p_data': {
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'price': price,
          'image_url': imageUrl,
          'category': _category,
          'is_available': _available,
        },
        'p_stock': stock,
        'p_threshold': threshold,
        'p_expected_version': _isEditing ? _stockVersion : null,
      });
      if (!mounted ||
          _accountChanged ||
          _supabase.auth.currentUser?.id != _account) {
        return;
      }
      if (result['code'] == 'STOCK_CHANGED') {
        setState(() {
          _stockCtrl.text = result['stock_qty'].toString();
          _stockVersion = (result['stock_version'] as num).toInt();
        });
        Get.snackbar(
          "Stock changed".tr,
          "Review the current count and save again.".tr,
        );
        return;
      }
      if (!['UPDATED', 'ALREADY_UPDATED'].contains(result['code'])) {
        throw StateError(
          result['code'] == 'FORBIDDEN'
              ? 'Only the approved, unblocked owning vendor can save this product.'
              : 'The product save was not confirmed. Refresh and retry.',
        );
      }
      Get.back();
      Get.snackbar(
        _isEditing ? "Updated".tr : "Added".tr,
        "Product and stock saved successfully.".tr,
      );
    } catch (e) {
      if (!mounted ||
          _accountChanged ||
          _supabase.auth.currentUser?.id != _account) {
        return;
      }
      Get.snackbar(
        "Save not confirmed".tr,
        e is StateError
            ? e.message.toString()
            : "Check your connection and retry the same values.".tr,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
          _isEditing ? "Edit Product".tr : "Add Product".tr,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    "Save".tr,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
          ),
        ],
      ),
      body: _accountChanged
          ? Center(child: Text("Account changed. Open the product again.".tr))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loadingCategories) const LinearProgressIndicator(),
                  if (_inventory.hasPending)
                    Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        "Product save is unconfirmed. Retry Save with the same values."
                            .tr,
                      ),
                    ),
                  if (_images.hasPendingUpload)
                    Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        "Image upload is unconfirmed. Retry Save with the selected image."
                            .tr,
                      ),
                    ),
                  if (_selectedImage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        "Selected image: @slot0end".uiTr({
                          "slot0end": (_selectedImage!.name).toString(),
                        }),
                      ),
                    ),
                  if (_imageCtrl.text.isNotEmpty)
                    Container(
                      height: 160,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ProductImage(
                        imageUrl: _imageCtrl.text,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),

                  _card(
                    children: [
                      _field(
                        _nameCtrl,
                        "Product Name".tr,
                        Icons.shopping_bag_outlined,
                        TextInputType.text,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        _descCtrl,
                        "Description (optional)".tr,
                        Icons.notes_rounded,
                        TextInputType.multiline,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        _priceCtrl,
                        "Price (PKR)".tr,
                        Icons.monetization_on_outlined,
                        TextInputType.number,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        _stockCtrl,
                        "Confirmed stock quantity".tr,
                        Icons.inventory_2_outlined,
                        TextInputType.number,
                        integer: true,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        _thresholdCtrl,
                        "Low-stock threshold".tr,
                        Icons.notifications_outlined,
                        TextInputType.number,
                        integer: true,
                      ),
                      const SizedBox(height: 14),
                      const SizedBox(height: 12),

                      OutlinedButton.icon(
                        onPressed: _imageLocked ? null : _pickImage,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          _selectedImage == null
                              ? "Choose Product Image".tr
                              : "Change Product Image".tr,
                        ),
                      ),
                    ],
                  ),

                  if (_selectedImage != null || _imageCtrl.text.isNotEmpty)
                    TextButton.icon(
                      onPressed: _imageLocked
                          ? null
                          : () => setState(() {
                              _selectedImage = null;
                              _imageCtrl.clear();
                            }),
                      icon: const Icon(Icons.clear),
                      label: Text("Remove product image".tr),
                    ),
                  const SizedBox(height: 16),

                  _card(
                    children: [
                      Text(
                        "Category".tr,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _dbCategories.map((cat) {
                          final name = cat['name'];
                          final sel = _category == name;

                          return GestureDetector(
                            onTap: _productLocked
                                ? null
                                : () => setState(() => _category = name),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: sel ? _kPurple : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: sel
                                      ? _kPurple
                                      : _kPurple.withValues(alpha: 0.20),
                                ),
                                boxShadow: sel
                                    ? [
                                        BoxShadow(
                                          color: _kPurple.withValues(
                                            alpha: 0.25,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: sel ? Colors.white : _kTextSub,
                                  fontWeight: sel
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  _card(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Available for order".tr,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _available
                                      ? "Visible to customers".tr
                                      : "Hidden from store".tr,
                                  style: const TextStyle(
                                    color: _kTextSub,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _available,
                            activeThumbColor: Colors.white,
                            activeTrackColor: _kPurple,
                            onChanged: _productLocked
                                ? null
                                : (v) => setState(() => _available = v),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _saving
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                          : Text(
                              _isEditing ? "Save Changes".tr : "Add Product".tr,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
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

  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
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
        children: children,
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon,
    TextInputType type, {
    int maxLines = 1,
    bool integer = false,
    void Function(String)? onChanged,
  }) {
    return TextField(
      enabled: !_productLocked,
      controller: ctrl,
      keyboardType: type,
      inputFormatters: integer
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _kPurple, size: 20),
        filled: true,
        fillColor: _kBg,
        labelStyle: const TextStyle(color: _kTextSub),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _kPurple.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kPurple, width: 1.5),
        ),
      ),
    );
  }
}
