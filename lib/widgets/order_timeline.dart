import 'package:get/get.dart';
import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

class OrderTimeline extends StatefulWidget {
  final int currentStep;
  final Color activeColor;
  final List<Map<String, dynamic>>? events;

  const OrderTimeline({
    super.key,
    required this.currentStep,
    this.activeColor = AppColors.primary,
    this.events,
  });

  @override
  State<OrderTimeline> createState() => _OrderTimelineState();
}

class _OrderTimelineState extends State<OrderTimeline>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const _steps = [
    _TimelineStep(
      Icons.receipt_long_rounded,
      'Order Placed',
      'Your order has been received',
    ),
    _TimelineStep(
      Icons.check_circle_outline_rounded,
      'Confirmed',
      'Vendor has accepted your order',
    ),
    _TimelineStep(
      Icons.restaurant_rounded,
      'Preparing',
      'Your order is being freshly prepared',
    ),
    _TimelineStep(
      Icons.delivery_dining_rounded,
      'On the Way',
      'Rider is heading your way',
    ),
    _TimelineStep(Icons.home_rounded, 'Delivered', 'Enjoy your order! 🎉'),
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.18,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  void _syncMotion() {
    if (widget.events != null ||
        widget.currentStep >= 4 ||
        AppMotion.reduced(context)) {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    } else if (!_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant OrderTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    if (widget.events case final events?) {
      final sorted = [...events]
        ..sort(
          (a, b) =>
              a['created_at'].toString().compareTo(b['created_at'].toString()),
        );
      return Column(
        children: sorted
            .map(
              (event) => ListTile(
                dense: true,
                leading: Icon(
                  event['status'] == 'cancelled'
                      ? Icons.cancel_outlined
                      : Icons.check_circle_outline,
                ),
                title: Text(event['status'].toString().replaceAll('_', ' ').tr),
                subtitle: Text(
                  [
                    if (event['reason'] == 'vendor_timeout')
                      'Order cancelled — vendor unavailable.'.tr,
                    DateTime.tryParse(
                          event['created_at'].toString(),
                        )?.toLocal().toString() ??
                        'Timestamp unavailable'.tr,
                  ].join('\n'),
                ),
              ),
            )
            .toList(),
      );
    }
    return Column(
      children: List.generate(_steps.length, (i) {
        final isDone = i < widget.currentStep;
        final isActive = i == widget.currentStep;
        final isLast = i == _steps.length - 1;
        return _buildRow(_steps[i], i, isDone, isActive, isLast);
      }),
    );
  }

  Widget _buildRow(
    _TimelineStep step,
    int index,
    bool isDone,
    bool isActive,
    bool isLast,
  ) {
    final color = widget.activeColor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Column(
            children: [
              if (isActive)
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, child) =>
                      Transform.scale(scale: _pulseAnim.value, child: child),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(step.icon, size: 22, color: Colors.white),
                  ),
                )
              else
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone ? color : const Color(0xFFF0F0F0),
                    border: isDone
                        ? null
                        : Border.all(color: const Color(0xFFDDDDDD), width: 2),
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : step.icon,
                    size: 20,
                    color: isDone ? Colors.white : const Color(0xFFCCCCCC),
                  ),
                ),

              if (!isLast)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 2.5,
                  height: 44,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isDone
                        ? color.withValues(alpha: 0.6)
                        : const Color(0xFFE8E8E8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: isActive ? 10 : 8,
              bottom: isLast ? 0 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label.tr,
                  style: TextStyle(
                    fontSize: isActive ? 16 : 15,
                    fontWeight: isActive
                        ? FontWeight.w800
                        : (isDone ? FontWeight.w600 : FontWeight.w500),
                    color: isActive
                        ? const Color(0xFF1A0A00)
                        : isDone
                        ? const Color(0xFF333333)
                        : const Color(0xFFBBBBBB),
                  ),
                ),
                if (isActive || isDone) ...[
                  const SizedBox(height: 4),
                  Text(
                    step.sub.tr,
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive
                          ? const Color(0xFF666666)
                          : const Color(0xFFAAAAAA),
                      height: 1.4,
                    ),
                  ),
                ],
                if (isActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        "Current Status".tr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineStep {
  final IconData icon;
  final String label;
  final String sub;
  const _TimelineStep(this.icon, this.label, this.sub);
}

class OrderStatusCard extends StatelessWidget {
  final String orderId;
  final int currentStep;
  final Color accentColor;

  const OrderStatusCard({
    super.key,
    required this.orderId,
    required this.currentStep,
    this.accentColor = const Color(0xFFF2855A),
  });

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Order Status".tr,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    orderId,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A0A00),
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _stepLabels[currentStep.clamp(0, 4)],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          OrderTimeline(currentStep: currentStep, activeColor: accentColor),
        ],
      ),
    );
  }

  static const _stepLabels = [
    'Placed',
    'Confirmed',
    'Preparing',
    'On the Way',
    'Delivered',
  ];
}
