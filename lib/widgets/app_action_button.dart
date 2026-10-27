import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

enum AppActionStyle { primary, secondary, destructive }

/// Material press/keyboard feedback; busy is explicitly owned by the caller
/// and must cover the complete confirmed backend operation.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.style = AppActionStyle.primary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final AppActionStyle style;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: AppMotion.duration(context, AppMotion.quick),
        child: busy
            ? SizedBox(
                key: const ValueKey('busy'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: style == AppActionStyle.secondary
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
                  Flexible(child: Text(label, textAlign: TextAlign.center)),
                ],
              ),
      ),
    );
    final callback = busy ? null : onPressed;
    return SizedBox(
      width: double.infinity,
      child: style == AppActionStyle.secondary
          ? OutlinedButton(onPressed: callback, child: content)
          : ElevatedButton(
              onPressed: callback,
              style: style == AppActionStyle.destructive
                  ? ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Colors.white,
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: content,
              ),
            ),
    );
  }
}
