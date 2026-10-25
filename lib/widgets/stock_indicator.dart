import 'package:get/get.dart';
import '../core/stage2_ui_strings.dart';
import 'package:flutter/material.dart';
import '../services/inventory_service.dart';

class StockIndicator extends StatelessWidget {
  const StockIndicator({super.key, required this.product, this.vendor = false});
  final Map<String, dynamic> product;
  final bool vendor;
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final stock = ProductStock(product);
    return Text(
      !vendor && stock.confirmed && !stock.purchasable
          ? outOfStockMessage.tr
          : [
              stock.label.tr,
              if (stock.confirmed)
                '@slot0end units'.uiTr({'slot0end': stock.quantity.toString()}),
              if (vendor)
                'Low stock at @slot0end'.uiTr({
                  'slot0end': stock.threshold.toString(),
                }),
            ].join(' · '),
      style: TextStyle(
        fontSize: 12,
        color: !stock.purchasable
            ? Colors.red.shade700
            : stock.quantity <= stock.threshold
            ? Colors.orange.shade800
            : Colors.green.shade800,
      ),
    );
  }
}
