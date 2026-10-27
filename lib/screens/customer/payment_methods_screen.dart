import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../theme/app_theme.dart';

/// Mirrors the existing checkout policy; no payment instrument is saved here.
class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: Text('Payment Methods'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    size: 32,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    'Cash on Delivery'.tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text('Pay when your order arrives'.tr),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          Text(
            'No online payment method is configured.'.tr,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpace.lg),
          for (final method in [
            'Credit / Debit Card',
            'EasyPaisa',
            'JazzCash',
            'Bank Transfer',
          ])
            Card(
              margin: const EdgeInsets.only(bottom: AppSpace.md),
              child: ListTile(
                enabled: false,
                leading: const Icon(Icons.lock_outline_rounded),
                title: Text(method.tr),
                subtitle: Text(
                  'Unavailable: no payment provider is configured.'.tr,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
