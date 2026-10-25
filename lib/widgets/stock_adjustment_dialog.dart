import 'package:get/get.dart';
import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/inventory_service.dart';

class StockAdjustmentDialog extends StatefulWidget {
  const StockAdjustmentDialog({super.key, required this.product, this.writer});
  final Map<String, dynamic> product;
  final InventoryWriter? writer;

  @override
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  late final TextEditingController _quantity;
  final _reason = TextEditingController(text: 'Physical stock count');
  late final InventoryWriteFlow _flow;
  late int _version;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final stock = ProductStock(widget.product);
    _quantity = TextEditingController(
      text: stock.confirmed ? '${stock.quantity}' : '',
    );
    _version = stock.version;
    _flow = InventoryWriteFlow(writer: widget.writer);
  }

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final count = ProductStock.nonnegativeInteger(_quantity.text);
    if (count == null || _reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter a whole-number count and reason.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var closing = false;
    try {
      final result = await _flow.save('vendor_adjust_stock', {
        'p_product_id': widget.product['id'],
        'p_quantity': count,
        'p_mode': 'set',
        'p_reason': _reason.text.trim(),
        'p_threshold': null,
        'p_expected_version': _version,
      });
      if (!mounted) return;
      if (result['code'] == 'STOCK_CHANGED') {
        setState(() {
          _quantity.text = result['stock_qty'].toString();
          _version = (result['stock_version'] as num).toInt();
          _error = 'Stock changed. Review this count and save again.';
        });
      } else if (['UPDATED', 'ALREADY_UPDATED'].contains(result['code'])) {
        closing = true;
        Navigator.pop(context);
      } else {
        setState(
          () => _error =
              'Stock update was not confirmed. Refresh your inventory.',
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Update could not be confirmed. Retry the same count and reason.',
        );
    } finally {
      if (mounted && !closing) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          "Stock: @slot0end".uiTr({
            "slot0end": (widget.product['name']).toString(),
          }),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _quantity,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: "Confirmed quantity".tr),
              ),
              TextField(
                controller: _reason,
                enabled: !_saving,
                maxLength: 300,
                decoration: InputDecoration(labelText: "Reason".tr),
              ),
              if (_error != null)
                Text(_error!.tr, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text("Cancel".tr),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text("Save stock".tr),
          ),
        ],
      ),
    );
  }
}
