import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

const _kPurple  = Color(0xFF1B5E20);
const _kBg      = Color(0xFFF8F7FF);
const _kTextSub = Color(0xFF6B6B8A);

class ProductFormScreen extends StatefulWidget {
  final int? vendorId;
  final Map<String, dynamic>? existing;

  const ProductFormScreen({super.key, required this.vendorId, this.existing});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _supabase   = Supabase.instance.client;
  final _nameCtrl   = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _priceCtrl  = TextEditingController();
  final _imageCtrl  = TextEditingController();

  String _category   = 'Food';
  bool   _available  = true;
  bool   _saving     = false;
  XFile? _selectedImage;

  bool get _isEditing => widget.existing != null;

 List<Map<String, dynamic>> _dbCategories = [];
 bool _loadingCategories = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();

    if (_isEditing) {
      final p = widget.existing!;
      _nameCtrl.text  = p['name']        ?? '';
      _descCtrl.text  = p['description'] ?? '';
      _priceCtrl.text = p['price']?.toString() ?? '';
      _imageCtrl.text = p['image_url']   ?? '';
      _category = p['category'] ?? 'Food';
      _available = p['is_available'] ?? true;
    }
  }

Future<void> _loadCategories() async {
  try {
    final data = await _supabase
        .from('categories')
        .select('name, image_url')
        .order('sort_order');
         print("Categories from DB: $data");

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
    print(e);
    if (mounted) {
      setState(() => _loadingCategories = false);
    }
  }
}
  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
  final picker = ImagePicker();

  final image = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 80,
  );

  if (image != null) {
    setState(() {
      _selectedImage = image;
    });
  }
}

 Future<void> _save() async {
  try {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      Get.snackbar('Error', 'Session expired, please login again');
      Get.offAllNamed('/login'); // apna login route lagayein
      return;
    }
    if (session.isExpired) {
      await _supabase.auth.refreshSession();
    }
    } catch (e) {
    print("🔥 Session refresh failed: $e");
    Get.snackbar('Error', 'Session expired, please login again');
    Get.offAllNamed('/login');
    return;
  }
  
  final name = _nameCtrl.text.trim();
  final price = double.tryParse(_priceCtrl.text.trim());

  if (name.isEmpty || price == null) {
    Get.snackbar(
      'Error',
      'Name and a valid price are required.',
      backgroundColor: Colors.redAccent,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      borderRadius: 14,
    );
    return;
  }

  setState(() => _saving = true);

  try {
    // Current logged-in user
    final user = _supabase.auth.currentUser;

    print("USER = ${user?.email}");
    print("AUTH UID = ${user?.id}");
    print("SESSION = ${_supabase.auth.currentSession != null}");

    if (user == null) {
      throw Exception('User is not logged in');
    }

    final session = _supabase.auth.currentSession;
    print("AUTH UID = ${session?.user.id}");
    print("AUTH EMAIL = ${session?.user.email}");

    print("Current User = ${user.email}");

    // Get vendor ID from users table
    final userRecord = await _supabase
        .from('users')
        .select('id, email, role')
        .ilike('email', user.email!)
        .maybeSingle();

    print("User Record = $userRecord");

    if (userRecord == null) {
      throw Exception('Vendor record not found in users table');
    }

    if (userRecord['role'] != 'vendor') {
      throw Exception('Current user is not a vendor');
    }

    final vendorId = userRecord['id'];

    print("Vendor ID = $vendorId");
    // 🔍 RLS function test
    final vendorCheck = await _supabase.rpc(
     'is_current_vendor',
      params: {
       'p_vendor_id': vendorId,
    },
);

    print("🔥 is_current_vendor($vendorId) = $vendorCheck");
    print("🔥 vendorCheck type = ${vendorCheck.runtimeType}");
    print("Category = $_category");
    print("Product Name = $name");

    String imageUrl = '';

if (_selectedImage != null) {
  final bytes = await _selectedImage!.readAsBytes();

  final fileName =
      '${DateTime.now().millisecondsSinceEpoch}_${_selectedImage!.name}';

  final filePath = 'products/$fileName';

  await _supabase.storage
      .from('product-images')
      .uploadBinary(
        filePath,
        bytes,
        fileOptions: const FileOptions(
          upsert: true,
        ),
      );

  imageUrl = _supabase.storage
      .from('product-images')
      .getPublicUrl(filePath);

  print("🔥 IMAGE URL = $imageUrl");
}

    final data = {
      'vendor_id': vendorId,
      'name': name,
      'description': _descCtrl.text.trim(),
      'price': price,
      'image_url': imageUrl,
      'category': _category,
      'is_available': _available,
    };

    print("Data = $data");
   

if (vendorCheck != true) {
  throw Exception(
    'Vendor verification failed. vendor_id=$vendorId, result=$vendorCheck',
  );
}

    if (_isEditing) {
      await _supabase
          .from('products')
          .update(data)
          .eq('id', widget.existing!['id']);
    } else {
      print("🔥 INSERT START");
      final result = await _supabase
          .from('products')
          .insert(data)
          .select();
          

      print("🔥 INSERT SUCCESS");
    }
    print("🔥 BEFORE GET BACK");


    Get.back();

    Get.snackbar(
      _isEditing ? 'Updated ✅' : 'Added ✅',
      'Product saved successfully.',
      backgroundColor: _kPurple,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      borderRadius: 14,
      duration: const Duration(seconds: 2),
    );

  } catch (e) {
    print("SAVE ERROR = $e");

    Get.snackbar(
      'Error',
      'Failed to save: $e',
      backgroundColor: Colors.redAccent,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );

  } finally {
    if (mounted) {
      setState(() => _saving = false);
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPurple,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isEditing ? 'Edit Product' : 'Add Product',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          if (_imageCtrl.text.isNotEmpty)
            Container(
              height: 160,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Image.network(_imageCtrl.text, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),

          _card(children: [
            _field(_nameCtrl,  'Product Name',  Icons.shopping_bag_outlined,  TextInputType.text),
            const SizedBox(height: 14),
            _field(_descCtrl,  'Description (optional)', Icons.notes_rounded, TextInputType.multiline,
                maxLines: 3),
            const SizedBox(height: 14),
            _field(_priceCtrl, 'Price (PKR)',   Icons.monetization_on_outlined, TextInputType.number),
            const SizedBox(height: 14),
           const SizedBox(height: 12),

OutlinedButton.icon(
  onPressed: _pickImage,
  icon: const Icon(Icons.photo_library_outlined),
  label: Text(
    _selectedImage == null
        ? 'Choose Product Image'
        : 'Change Product Image',
  ),
),
          ]),

          const SizedBox(height: 16),

          _card(children: [
            const Text('Category',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1A1340))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
              children: _dbCategories.map((cat) {
                final name = cat['name'];
                final sel = _category == name;

                return GestureDetector(
                  onTap: () => setState(() => _category = name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? _kPurple : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel ? _kPurple : _kPurple.withValues(alpha: 0.20)),
                      boxShadow: sel
                          ? [BoxShadow(color: _kPurple.withValues(alpha: 0.25),
                                blurRadius: 8, offset: const Offset(0, 3))]
                          : [],
                    ),
                    child: Text(name,
                        style: TextStyle(
                          color: sel ? Colors.white : _kTextSub,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 13,
                        )),
                  ),
                );
              }).toList(),
            ),
          ]),

          const SizedBox(height: 16),

          _card(children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Available for order',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1A1340))),
                const SizedBox(height: 2),
                Text(_available ? 'Visible to customers' : 'Hidden from store',
                    style: const TextStyle(color: _kTextSub, fontSize: 12)),
              ])),
              Switch(
                value: _available,
                activeThumbColor: Colors.white,
                activeTrackColor: _kPurple,
                onChanged: (v) => setState(() => _available = v),
              ),
            ]),
          ]),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Text(_isEditing ? 'Save Changes' : 'Add Product',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),

          const SizedBox(height: 20),
        ]),
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
          BoxShadow(color: _kPurple.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon,
    TextInputType type, {
    int maxLines = 1,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _kPurple, size: 20),
        filled: true,
        fillColor: _kBg,
        labelStyle: const TextStyle(color: _kTextSub),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
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