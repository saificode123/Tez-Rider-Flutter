import 'package:flutter/material.dart';
import '../services/inventory_service.dart';

class StockIndicator extends StatelessWidget {
  const StockIndicator({super.key, required this.product, this.vendor = false});
  final Map<String, dynamic> product;
  final bool vendor;
  @override
  Widget build(BuildContext context) {
    final stock = ProductStock(product);
    return Text(
      !vendor && stock.confirmed && !stock.purchasable
          ? outOfStockMessage
          : '${stock.label}${stock.confirmed ? ' · ${stock.quantity} units' : ''}${vendor ? ' · Low stock at ${stock.threshold}' : ''}',
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
