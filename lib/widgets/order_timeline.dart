import 'package:lottie/lottie.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

class OrderTimeline extends StatefulWidget {
  final int currentStep;
  final Color activeColor;
  final List<Map<String, dynamic>>? events;
  final bool showDeliveryAnimation;

  const OrderTimeline({
    super.key,
    required this.currentStep,
    this.activeColor = AppColors.primary,
    this.events,
    this.showDeliveryAnimation = false,
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
    _TimelineStep(Icons.home_rounded, 'Delivered', 'Enjoy your order!'),
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
        widget.currentStep < 0 ||
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Only the enclosing order may authorize this animation. A Vendor
          // portion's on_the_way event can describe a reserved pickup instead.
          if (widget.showDeliveryAnimation &&
              sorted.isNotEmpty &&
              sorted.last['status'] == 'on_the_way')
            _deliveryAnimation(),
          for (var i = 0; i < sorted.length; i++)
            _buildEvent(
              sorted[i],
              i == sorted.length - 1,
              i == sorted.length - 1,
            ),
        ],
      );
    }
    return Column(
      children: [
        if (widget.currentStep == 3) _deliveryAnimation(),
        ...List.generate(_steps.length, (i) {
          final isDone = i < widget.currentStep;
          final isActive = i == widget.currentStep;
          final isLast = i == _steps.length - 1;
          return _buildRow(_steps[i], i, isDone, isActive, isLast);
        }),
      ],
    );
  }

  Widget _deliveryAnimation() => Semantics(
    label: 'On the Way'.tr,
    image: true,
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Lottie.asset(
          'assets/lottie/delivery_cyclist.json',
          height: 124,
          fit: BoxFit.contain,
          animate: !AppMotion.reduced(context),
          repeat: !AppMotion.reduced(context),
          errorBuilder: (_, __, ___) => const SizedBox(
            height: 124,
            child: Icon(
              Icons.delivery_dining_rounded,
              size: 64,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildEvent(Map<String, dynamic> event, bool current, bool last) {
    final status = event['status']?.toString() ?? '';
    final cancelled = status == 'cancelled';
    final color = cancelled ? AppColors.error : widget.activeColor;
    final icon = switch (status) {
      'placed' => Icons.receipt_long_rounded,
      'accepted' || 'confirmed' => Icons.check_circle_outline_rounded,
      'preparing' => Icons.restaurant_rounded,
      'rider_assigned' => Icons.person_pin_circle_outlined,
      'picked_up' || 'on_the_way' => Icons.delivery_dining_rounded,
      'delivered' => Icons.home_rounded,
      'cancelled' => Icons.cancel_outlined,
      _ => Icons.history_rounded,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: current ? .14 : .06),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: .2)),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      width: 2,
                      color: AppColors.divider,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.replaceAll('_', ' ').tr,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cancelled ? color : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (event['reason'] == 'vendor_timeout')
                    Text(
                      'Order cancelled — vendor unavailable.'.tr,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  Text(
                    DateTime.tryParse(
                          event['created_at'].toString(),
                        )?.toLocal().toString() ??
                        'Timestamp unavailable'.tr,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
                  duration: AppMotion.duration(
                    context,
                    const Duration(milliseconds: 400),
                  ),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone ? color : AppColors.bgSection,
                    border: isDone
                        ? null
                        : Border.all(color: AppColors.divider, width: 2),
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : step.icon,
                    size: 20,
                    color: isDone ? Colors.white : AppColors.textHint,
                  ),
                ),

              if (!isLast)
                AnimatedContainer(
                  duration: AppMotion.duration(
                    context,
                    const Duration(milliseconds: 500),
                  ),
                  width: 2.5,
                  height: 44,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isDone
                        ? color.withValues(alpha: 0.6)
                        : AppColors.divider,
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
                        ? AppColors.textPrimary
                        : isDone
                        ? AppColors.textPrimary
                        : AppColors.textHint,
                  ),
                ),
                if (isActive || isDone) ...[
                  const SizedBox(height: 4),
                  Text(
                    step.sub.tr,
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive
                          ? AppColors.textSecondary
                          : AppColors.textHint,
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
    this.accentColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
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
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    orderId,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
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
