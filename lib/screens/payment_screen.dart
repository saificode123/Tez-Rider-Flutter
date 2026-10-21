import 'package:flutter/material.dart';

/// Constructor retained for compatibility. Never simulate a payment capture.
class PaymentScreen extends StatelessWidget {
  final double amount;
  final VoidCallback onPaymentSuccess;
  const PaymentScreen({
    super.key,
    required this.amount,
    required this.onPaymentSuccess,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment unavailable')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Online payment is not available. No payment has been taken. Return to checkout to use an available payment method.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Return to checkout'),
            ),
          ],
        ),
      ),
    ),
  );
}
