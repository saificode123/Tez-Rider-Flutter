import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _kPurple  = Color(0xFF1B5E20);
const _kBg      = Color.fromRGBO(181, 170, 251, 1);
const _kCard    = Color(0xFFFFFFFF);
const _kText    = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);
const _kGreen   = Color(0xFF10B981);
const _kSaffron = Color(0xFFF59E0B);

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final List<Map<String, dynamic>> _methods = [
    {
      'type': 'card',
      'label': 'Visa •••• 4242',
      'sub': 'Expires 12/26',
      'icon': '📲',
      'color': Color(0xFF1A56DB),
    },
    {
      'type': 'wallet',
      'label': 'EasyPaisa',
      'sub': '+92 300 **** 5678',
      'icon': '📱',
      'color': Color(0xFF00A651),
    },
    {
      'type': 'wallet',
      'label': 'JazzCash',
      'sub': '+92 311 **** 1234',
      'icon': '📲',
      'color': Color(0xFFEF4444),
    },
  ];

  int _selectedIndex = 0;

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Add Payment Method',
              style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          _addMethodTile('💳', 'Credit / Debit Card', 'Visa, Mastercard', Color(0xFF1A56DB)),
          const SizedBox(height: 12),
          _addMethodTile('📱', 'EasyPaisa', 'Mobile wallet', Color(0xFF00A651)),
          const SizedBox(height: 12),
          _addMethodTile('📲', 'JazzCash', 'Mobile wallet', Color(0xFFEF4444)),
          const SizedBox(height: 12),
          _addMethodTile('🏦', 'Bank Transfer', 'Direct bank payment', _kPurple),
        ]),
      ),
    );
  }

  Widget _addMethodTile(String emoji, String title, String sub, Color color) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title coming soon!'),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(color: _kText, fontWeight: FontWeight.w700, fontSize: 15)),
            Text(sub, style: TextStyle(color: _kTextSub, fontSize: 12)),
          ]),
          const Spacer(),
          Icon(Icons.arrow_forward_ios_rounded, color: color, size: 14),
        ]),
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
        title: const Text('Payment Methods',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
            onPressed: _showAddSheet,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kGreen.withValues(alpha: 0.20)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: _kGreen, size: 20),
              const SizedBox(width: 10),
              Text('Tap a payment method to set it as default.',
                  style: TextStyle(color: _kGreen, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),

          const SizedBox(height: 20),
          Text('Saved Methods'.toUpperCase(),
              style: TextStyle(
                  color: _kTextSub, fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 1.4)),
          const SizedBox(height: 12),

          ..._methods.asMap().entries.map((entry) {
            final i      = entry.key;
            final method = entry.value;
            final color  = method['color'] as Color;
            final sel    = _selectedIndex == i;

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedIndex = i);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: sel ? _kPurple : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: sel
                          ? _kPurple.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(child: Text(method['icon'] as String,
                        style: const TextStyle(fontSize: 24))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(method['label'] as String,
                        style: const TextStyle(color: _kText, fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(method['sub'] as String,
                        style: TextStyle(color: _kTextSub, fontSize: 12)),
                  ])),
                  if (sel)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _kPurple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Default',
                          style: TextStyle(color: _kPurple, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
            );
          }),

          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSaffron.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kSaffron.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: _kSaffron.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(child: Text('💵', style: TextStyle(fontSize: 24))),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cash on Delivery',
                    style: TextStyle(color: _kText, fontWeight: FontWeight.w800, fontSize: 15)),
                SizedBox(height: 3),
                Text('Pay when your order arrives',
                    style: TextStyle(color: _kTextSub, fontSize: 12)),
              ])),
              const Icon(Icons.check_circle_outline_rounded, color: _kSaffron, size: 20),
            ]),
          ),

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showAddSheet,
              icon: const Icon(Icons.add_card_rounded, color: Colors.white),
              label: const Text('Add New Method',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}