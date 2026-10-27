import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Displays confirmed controller state; requesting a change never changes the
/// displayed value until the caller supplies the backend-confirmed result.
class RiderAvailabilityControl extends StatelessWidget {
  const RiderAvailabilityControl({
    super.key,
    required this.online,
    required this.ready,
    required this.busy,
    required this.onChanged,
  });

  final bool online;
  final bool ready;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = ready && online ? AppColors.primary : AppColors.textSecondary;
    final label = !ready
        ? (busy ? 'Checking availability' : 'Availability unavailable').tr
        : (online ? 'Online' : 'Offline').tr;
    return MergeSemantics(
      child: AnimatedContainer(
        duration: AppMotion.duration(context),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.sm,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Icon(
              ready && online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: color,
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: color),
              ),
            ),
            if (busy) ...[
              const SizedBox(width: AppSpace.sm),
              if (AppMotion.reduced(context))
                const Icon(Icons.sync, size: 18)
              else
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
            Switch.adaptive(
              value: online,
              onChanged: ready && !busy ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}
