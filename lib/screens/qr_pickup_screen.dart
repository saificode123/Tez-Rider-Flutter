import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QRPickupScreen extends StatefulWidget {
  final String orderId;
  final String storeName;
  final String items;
  final String total;
  final Color accentColor;

  const QRPickupScreen({
    super.key,
    required this.orderId,
    required this.storeName,
    required this.items,
    required this.total,
    this.accentColor = const Color(0xFF9B72CF),
  });

  @override
  State<QRPickupScreen> createState() => _QRPickupScreenState();
}

class _QRPickupScreenState extends State<QRPickupScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _qrData => 'TEZRIDER:ORDER:${widget.orderId}:PICKUP:${DateTime.now().millisecondsSinceEpoch}';

  Future<void> _copyId() async {
    await Clipboard.setData(ClipboardData(text: widget.orderId));
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)]),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF333333)),
          ),
        ),
        title: const Text('Pickup QR Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A), letterSpacing: -0.3)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          children: [
            Center(
              child: Lottie.asset('assets/lottie/order_picked.json',
                  width: 180, height: 160, fit: BoxFit.contain),
            ),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.store_rounded, color: color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.storeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A), letterSpacing: -0.3)),
                        const SizedBox(height: 3),
                        Text(widget.items, style: const TextStyle(fontSize: 12, color: Color(0xFF888888)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(widget.total, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.4)),
                      const Text('Total', style: TextStyle(fontSize: 11, color: Color(0xFFAAAAAA))),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, 10)),
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_scanner_rounded, size: 16, color: color),
                            const SizedBox(width: 8),
                            Text('Show to Rider for Pickup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: color.withValues(alpha: 0.15), width: 2),
                        ),
                        child: QrImageView(
                          data: _qrData,
                          version: QrVersions.auto,
                          size: 200,
                          backgroundColor: Colors.white,
                          eyeStyle: QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: color,
                          ),
                          dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      GestureDetector(
                        onTap: _copyId,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: _copied ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _copied ? const Color(0xFF4CAF50) : const Color(0xFFEEEEEE),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.orderId,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _copied ? const Color(0xFF2E7D32) : const Color(0xFF333333),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 10),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                                  key: ValueKey(_copied),
                                  size: 16,
                                  color: _copied ? const Color(0xFF4CAF50) : const Color(0xFF888888),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Tap to copy order ID',
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: color),
                      const SizedBox(width: 8),
                      Text('How it works', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...[
                    '1. The rider will scan this QR code when they arrive.',
                    '2. This confirms pickup and starts your delivery timer.',
                    '3. You\'ll get a notification when your order is delivered.',
                  ].map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(t, style: const TextStyle(fontSize: 12, color: Color(0xFF555555), height: 1.4)),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}