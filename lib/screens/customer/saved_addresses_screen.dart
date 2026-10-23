import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';

const _kPurple  = Color(0xFF1B5E20);
const _kBg      = Color(0xFFF8F7FF);
const _kCard    = Color(0xFFFFFFFF);
const _kText    = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);
const _kPink    = Color(0xFFEC4899);

class SavedAddressesScreen extends StatefulWidget {
  const SavedAddressesScreen({super.key});

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;
  String? _loadError;
  bool _savingAddress = false;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw StateError('Sign in required');
      final userRecord = await _supabase.from('users').select('id').eq('email', user.email!).maybeSingle();
      if (userRecord == null) throw StateError('Account unavailable');
      final data = await _supabase
          .from('addresses')
          .select()
          .eq('user_id', userRecord['id'])
          .order('created_at', ascending: false) as List;
      if (mounted) setState(() => _addresses = data.cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Saved addresses could not be loaded. Retry.');
    }
    finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAddress(String id) async {
    try {
      await _supabase.from('addresses').delete().eq('id', id).select('id').single();
      _loadAddresses();
      Get.snackbar('Deleted', 'Address removed.',
          backgroundColor: _kPurple,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          borderRadius: 14);
    } catch (_) {
      Get.snackbar('Error', 'Could not delete address.',
          backgroundColor: _kPink,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          borderRadius: 14);
    }
  }

  void _showAddEditSheet({Map<String, dynamic>? existing}) {
    final labelCtrl   = TextEditingController(text: existing?['label'] ?? '');
    final addressCtrl = TextEditingController(text: existing?['address'] ?? '');
    final formKey     = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(existing == null ? 'Add New Address' : 'Edit Address',
                  style: const TextStyle(
                      color: _kText, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 24),
              TextFormField(
                controller: labelCtrl,
                decoration: _inputDecoration('Label', 'e.g. Home, Work', Icons.label_outline),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter a label' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: addressCtrl,
                maxLines: 2,
                decoration: _inputDecoration('Full Address', 'Street, City', Icons.location_on_outlined),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter an address' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_savingAddress) return;
                    if (!formKey.currentState!.validate()) return;
                    _savingAddress = true;
                    try {
                      final user = _supabase.auth.currentUser!;
                      final userRecord = await _supabase.from('users').select('id').eq('email', user.email!).maybeSingle();
                      if (userRecord == null) throw StateError('Account unavailable');
                      if (existing == null) {
                        await _supabase.from('addresses').insert({
                          'user_id': userRecord['id'],
                          'label':   labelCtrl.text.trim(),
                          'address': addressCtrl.text.trim(),
                        }).select('id').single();
                      } else {
                        await _supabase.from('addresses').update({
                          'label':   labelCtrl.text.trim(),
                          'address': addressCtrl.text.trim(),
                        }).eq('id', existing['id']).select('id').single();
                      }
                      if (mounted) { Navigator.pop(context); await _loadAddresses(); }
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Address changes were not confirmed. Please retry.')),
                        );
                      }
                    } finally { _savingAddress = false; }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPurple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: Text(existing == null ? 'Add Address' : 'Save Changes',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: _kPurple, size: 20),
      filled: true,
      fillColor: const Color(0xFFF8F7FF),
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
    );
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
        title: const Text('Saved Addresses',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
            onPressed: () => _showAddEditSheet(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2))
          : _loadError != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_loadError!), TextButton(onPressed: _loadAddresses, child: const Text('Retry addresses')),
                ]))
          : _addresses.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  itemCount: _addresses.length,
                  itemBuilder: (_, i) => _buildAddressCard(_addresses[i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditSheet(),
        backgroundColor: _kPurple,
        icon: const Icon(Icons.add_location_alt_rounded, color: Colors.white),
        label: const Text('Add Address',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📍', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 20),
        const Text('No saved addresses',
            style: TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Add an address for faster checkout.',
            style: TextStyle(color: _kTextSub, fontSize: 14)),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () => _showAddEditSheet(),
          icon: const Icon(Icons.add_location_alt_rounded),
          label: const Text('Add Address'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ]),
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> addr) {
    final label   = addr['label'] ?? 'Address';
    final address = addr['address'] ?? '';
    final isHome  = label.toLowerCase() == 'home';
    final isWork  = label.toLowerCase() == 'work';
    final icon    = isHome ? '🏠' : isWork ? '🏢' : '📍';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: _kPurple.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: _kPurple.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 22))),
        ),
        title: Text(label,
            style: const TextStyle(color: _kText, fontWeight: FontWeight.w800, fontSize: 15)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(address,
              style: TextStyle(color: _kTextSub, fontSize: 12),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(Icons.edit_outlined, color: _kPurple, size: 20),
            onPressed: () => _showAddEditSheet(existing: addr),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: _kPink, size: 20),
            onPressed: () {
              HapticFeedback.mediumImpact();
              showDialog(context: context, builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text('Delete Address?',
                    style: TextStyle(color: _kText, fontWeight: FontWeight.w800)),
                content: Text('Remove "$label" from your saved addresses?',
                    style: TextStyle(color: _kTextSub)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: _kTextSub))),
                  TextButton(
                    onPressed: () { Navigator.pop(context); _deleteAddress(addr['id']); },
                    child: const Text('Delete', style: TextStyle(color: _kPink, fontWeight: FontWeight.w800)),
                  ),
                ],
              ));
            },
          ),
        ]),
      ),
    );
  }
}
