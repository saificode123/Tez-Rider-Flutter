import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RateOrderSheet extends StatefulWidget {
  final String orderId;
  final String storeName;
  final Color accentColor;
  final Function(int rating, String comment)? onSubmit;

  const RateOrderSheet({
    super.key,
    required this.orderId,
    required this.storeName,
    this.accentColor = const Color(0xFFF2855A),
    this.onSubmit,
  });

  static Future<void> show(
    BuildContext context, {
    required String orderId,
    required String storeName,
    Color accentColor = const Color(0xFFF2855A),
    Function(int rating, String comment)? onSubmit,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RateOrderSheet(
        orderId: orderId,
        storeName: storeName,
        accentColor: accentColor,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<RateOrderSheet> createState() => _RateOrderSheetState();
}

class _RateOrderSheetState extends State<RateOrderSheet> with SingleTickerProviderStateMixin {
  int _rating = 0;
  int _hoveredStar = 0;
  final _commentCtrl = TextEditingController();
  bool _submitted = false;

  late AnimationController _entryCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut),
    );
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  String get _ratingLabel {
    switch (_rating) {
      case 1: return 'Poor 😞';
      case 2: return 'Fair 😐';
      case 3: return 'Good 🙂';
      case 4: return 'Great 😄';
      case 5: return 'Amazing! 🤩';
      default: return 'Tap to rate';
    }
  }

  Future<void> _submit() async {
    if (_rating == 0) return;
    HapticFeedback.mediumImpact();
    setState(() => _submitted = true);
    await Future.delayed(const Duration(milliseconds: 1400));
    widget.onSubmit?.call(_rating, _commentCtrl.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: _submitted ? _buildSuccess() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final color = widget.accentColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2)),
            ),
          ),

          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.star_rounded, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Rate Your Order', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF1A0A00), letterSpacing: -0.4)),
                    Text(widget.storeName, style: const TextStyle(fontSize: 13, color: Color(0xFF888888))),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_outlined, size: 14, color: Color(0xFF888888)),
                const SizedBox(width: 6),
                Text(widget.orderId, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
              ],
            ),
          ),

          const SizedBox(height: 28),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < (_hoveredStar > 0 ? _hoveredStar : _rating);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _rating = i + 1;
                    _hoveredStar = 0;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  child: AnimatedScale(
                    scale: filled ? 1.2 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 46,
                      color: filled ? const Color(0xFFFFB300) : const Color(0xFFDDDDDD),
                    ),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 10),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _ratingLabel,
              key: ValueKey(_rating),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _rating > 0 ? color : const Color(0xFFAAAAAA),
              ),
            ),
          ),

          const SizedBox(height: 22),

          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: 'Add a comment (optional)...',
              hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
              fillColor: const Color(0xFFF8F8F8),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: color, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
              ),
              contentPadding: const EdgeInsets.all(14),
              counterStyle: const TextStyle(fontSize: 11, color: Color(0xFFBBBBBB)),
            ),
          ),

          const SizedBox(height: 20),

          GestureDetector(
            onTap: _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: _rating > 0
                    ? LinearGradient(colors: [color.withValues(alpha: 0.85), color])
                    : const LinearGradient(colors: [Color(0xFFE0E0E0), Color(0xFFE0E0E0)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: _rating > 0
                    ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))]
                    : [],
              ),
              child: Center(
                child: Text(
                  'Submit Review',
                  style: TextStyle(
                    color: _rating > 0 ? Colors.white : const Color(0xFF999999),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    final color = widget.accentColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(Icons.check_circle_rounded, size: 48, color: color),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Thanks for your review!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A0A00), letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text('Your feedback helps us improve.', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }
}