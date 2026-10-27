import '../../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../services/saved_addresses_service.dart';
import 'package:get/get.dart';

const _kPurple = AppColors.primaryDark;
const _kBg = AppColors.bgLight;
const _kCard = Color(0xFFFFFFFF);
const _kText = AppColors.textPrimary;
const _kTextSub = AppColors.textSecondary;
const _kPink = Color(0xFFEC4899);

class SavedAddressesScreen extends StatefulWidget {
  const SavedAddressesScreen({super.key, this.service});
  final SavedAddressesService? service;

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  late final SavedAddressesService _service;
  late final String? _owner;
  StreamSubscription<void>? _auth;
  BuildContext? _editor, _confirmation;
  int _generation = 0;
  bool _changed = false, _loadingMore = false, _hasMore = false;
  int? _cursor;
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;
  String? _loadError;
  bool _savingAddress = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SavedAddressesService();
    _owner = _service.identity();
    _auth = _service.accountChanges.listen((_) {
      if (!mounted || _service.identity() == _owner) return;
      _generation++;
      for (final overlay in [_confirmation, _editor]) {
        if (overlay != null && overlay.mounted) {
          final route = ModalRoute.of(overlay);
          if (route != null) Navigator.of(overlay).removeRoute(route);
        }
      }
      setState(() {
        _changed = true;
        _addresses.clear();
        _cursor = null;
        _hasMore = false;
        _loading = false;
        _loadError = 'Account changed. Open saved addresses again.';
      });
    });
    _loadAddresses();
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_auth?.cancel());
    super.dispose();
  }

  Future<void> _loadAddresses({bool more = false}) async {
    if (_changed || more && (_loadingMore || !_hasMore)) return;
    final request = more ? _generation : ++_generation;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _loadError = null;
    });
    try {
      final result = await _service.load(before: more ? _cursor : null);
      if (!mounted || request != _generation) return;
      setState(() {
        final rows = List<Map<String, dynamic>>.from(
          (result['items'] as List).map((x) => Map<String, dynamic>.from(x)),
        );
        if (more) {
          _addresses.addAll(rows);
        } else {
          _addresses = rows;
        }
        _cursor = result['cursor'];
        _hasMore = result['has_more'];
      });
    } catch (_) {
      if (mounted && request == _generation) {
        setState(
          () => _loadError = 'Saved addresses could not be loaded. Retry.',
        );
      }
    } finally {
      if (mounted && request == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _change(
    Future<Map<String, dynamic>> Function() operation,
  ) async {
    if (_savingAddress || _changed) return;
    final generation = _generation;
    setState(() {
      _savingAddress = true;
      _loadError = null;
    });
    try {
      final result = await operation();
      if (!mounted || generation != _generation || _changed) return;
      await _loadAddresses();
      if (mounted && !_changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (result['code'] == 'ALREADY_APPLIED'
                      ? 'Original address change confirmed.'
                      : 'Address change saved.')
                  .tr,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && !_changed) {
        setState(
          () => _loadError = _service.pending
              ? 'Address change was not confirmed. Retry the original change.'
              : 'Address could not be changed. Reload before editing.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingAddress = false);
    }
  }

  Future<void> _deleteAddress(Map<String, dynamic> address) => _change(
    () => _service.change(
      operation: 'delete',
      id: address['id'],
      revision: address['revision'],
    ),
  );

  Future<void> _showAddEditSheet({Map<String, dynamic>? existing}) async {
    if (_savingAddress || _changed || _service.pending) return;
    final label = TextEditingController(text: existing?['label'] ?? '');
    final address = TextEditingController(text: existing?['address'] ?? '');
    String? error;
    ModalRoute<dynamic>? sheetRoute;
    final generation = _generation;
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) {
          _editor = ctx;
          sheetRoute = ModalRoute.of(ctx);
          return StatefulBuilder(
            builder: (ctx, update) => Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                MediaQuery.viewInsetsOf(ctx).bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (existing == null ? 'Add New Address' : 'Edit Address')
                          .tr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (error != null)
                      Semantics(liveRegion: true, child: Text(error!.tr)),
                    TextField(
                      controller: label,
                      enabled: !_savingAddress && !_service.pending,
                      maxLength: 100,
                      decoration: _inputDecoration(
                        'Label'.tr,
                        'e.g. Home, Work'.tr,
                        Icons.label_outline,
                      ),
                    ),
                    TextField(
                      controller: address,
                      enabled: !_savingAddress && !_service.pending,
                      maxLength: 2000,
                      maxLines: 3,
                      decoration: _inputDecoration(
                        'Address'.tr,
                        'Street, city and delivery details'.tr,
                        Icons.location_on_outlined,
                      ),
                    ),
                    if (_savingAddress) const LinearProgressIndicator(),
                    FilledButton(
                      onPressed: _savingAddress
                          ? null
                          : () async {
                              if (!_service.pending) {
                                final validation =
                                    SavedAddressesService.validate(
                                      label.text,
                                      address.text,
                                    );
                                if (validation != null) {
                                  update(() => error = validation);
                                  return;
                                }
                              }
                              setState(() => _savingAddress = true);
                              update(() => error = null);
                              try {
                                if (_service.pending) {
                                  await _service.retry();
                                } else {
                                  await _service.change(
                                    operation: existing == null
                                        ? 'create'
                                        : 'edit',
                                    id: existing?['id'],
                                    revision: existing?['revision'],
                                    label: label.text,
                                    address: address.text,
                                  );
                                }
                                if (!mounted ||
                                    _changed ||
                                    generation != _generation) {
                                  return;
                                }
                                if (ctx.mounted) Navigator.of(ctx).pop();
                                await _loadAddresses();
                              } catch (_) {
                                if (ctx.mounted && !_changed) {
                                  update(
                                    () => error =
                                        'Address change was not confirmed. Retry the original change.',
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _savingAddress = false);
                                }
                                if (ctx.mounted) update(() {});
                              }
                            },
                      child: Text(
                        (_service.pending
                                ? 'Retry original change'
                                : 'Save Address')
                            .tr,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _editor = null;
      // A popped modal remains mounted during its reverse animation.
      // Keep its controllers alive until the overlay is actually removed.
      await sheetRoute?.completed;
      label.dispose();
      address.dispose();
    }
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
          'Saved Addresses'.tr,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh addresses'.tr,
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _changed || _savingAddress || _service.pending
                ? null
                : () => _loadAddresses(),
          ),
          IconButton(
            tooltip: 'Add New Address'.tr,
            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
            onPressed: _changed || _savingAddress || _service.pending
                ? null
                : () => _showAddEditSheet(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_loadError!.tr),
            ),
          if (_service.pending)
            TextButton(
              onPressed: _savingAddress || _changed
                  ? null
                  : () => _change(_service.retry),
              child: Text('Retry original change'.tr),
            ),
          if (_loadError != null && !_service.pending)
            TextButton(
              onPressed: _changed ? null : () => _loadAddresses(),
              child: Text('Retry addresses'.tr),
            ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _kPurple),
                  )
                : _addresses.isEmpty
                ? _loadError == null
                      ? _buildEmpty()
                      : const SizedBox.shrink()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    itemCount: _addresses.length + (_hasMore ? 1 : 0),
                    itemBuilder: (_, i) => i == _addresses.length
                        ? TextButton(
                            onPressed: _loadingMore
                                ? null
                                : () => _loadAddresses(more: true),
                            child: Text('Load more addresses'.tr),
                          )
                        : _buildAddressCard(_addresses[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _changed || _savingAddress || _service.pending
            ? null
            : () => _showAddEditSheet(),
        backgroundColor: _kPurple,
        icon: const Icon(Icons.add_location_alt_rounded, color: Colors.white),
        label: Text(
          'Add Address'.tr,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📍', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 20),
          Text(
            'No saved addresses'.tr,
            style: TextStyle(
              color: _kText,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add an address for faster checkout.'.tr,
            style: TextStyle(color: _kTextSub, fontSize: 14),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _changed || _savingAddress || _service.pending
                ? null
                : () => _showAddEditSheet(),
            icon: const Icon(Icons.add_location_alt_rounded),
            label: Text('Add Address'.tr),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> addr) {
    final label = addr['label'] ?? 'Address';
    final address = addr['address'] ?? '';
    final isHome = label.toLowerCase() == 'home';
    final isWork = label.toLowerCase() == 'work';
    final icon = isHome
        ? '🏠'
        : isWork
        ? '🏢'
        : '📍';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _kPurple.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(icon, style: const TextStyle(fontSize: 22)),
          ),
        ),
        title: Text(
          label,
          style: const TextStyle(
            color: _kText,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            address,
            style: TextStyle(color: _kTextSub, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit Address'.tr,
              icon: Icon(Icons.edit_outlined, color: _kPurple, size: 20),
              onPressed: _changed || _savingAddress || _service.pending
                  ? null
                  : () => _showAddEditSheet(existing: addr),
            ),
            IconButton(
              tooltip: 'Delete Address'.tr,
              icon: Icon(Icons.delete_outline_rounded, color: _kPink, size: 20),
              onPressed: _changed || _savingAddress || _service.pending
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      showDialog(
                        context: context,
                        builder: (dialogContext) {
                          _confirmation = dialogContext;
                          return AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            title: Text(
                              'Delete Address?'.tr,
                              style: TextStyle(
                                color: _kText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            content: Text(
                              'Remove @label from your saved addresses?'
                                  .trParams({'label': label}),
                              style: TextStyle(color: _kTextSub),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'Cancel'.tr,
                                  style: TextStyle(color: _kTextSub),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _deleteAddress(addr);
                                },
                                child: Text(
                                  'Delete'.tr,
                                  style: TextStyle(
                                    color: _kPink,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ).whenComplete(() => _confirmation = null);
                    },
            ),
          ],
        ),
      ),
    );
  }
}
