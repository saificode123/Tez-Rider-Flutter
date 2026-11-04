import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A visual surface only: callers retain all data, state and actions.
class SpatialSurface extends StatelessWidget {
  const SpatialSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.color,
    this.borderRadius = 24,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double borderRadius;
  final bool elevated;

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: elevated ? AppShadow.soft : null,
    ),
    child: Material(
      color: color ?? Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.dividerDark
              : AppColors.divider,
        ),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class SpatialSectionHeading extends StatelessWidget {
  const SpatialSectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          Flexible(child: trailing!),
        ],
      ],
    ),
  );
}

class SpatialStatusBadge extends StatelessWidget {
  const SpatialStatusBadge({
    super.key,
    required this.label,
    this.color = AppColors.primary,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .14)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: color == AppColors.primary ? AppColors.primaryDark : color,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color == AppColors.primary ? AppColors.primaryDark : color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Inset navigation keeps every existing destination and safe-area clearance.
class SpatialBottomBar extends StatelessWidget {
  const SpatialBottomBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SpatialSurface(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          borderRadius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: child,
        ),
      ),
    ),
  );
}

/// A branded page opening. It never supplies or derives application data.
class SpatialPageHeader extends StatelessWidget {
  const SpatialPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.coral,
      borderRadius: const BorderRadiusDirectional.only(
        topStart: Radius.circular(24),
        topEnd: Radius.circular(24),
        bottomStart: Radius.circular(40),
        bottomEnd: Radius.circular(24),
      ),
      boxShadow: AppShadow.soft,
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: AppColors.textPrimary),
      child: IconTheme(
        data: const IconThemeData(color: AppColors.textPrimary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null || trailing != null) ...[
              Row(
                children: [
                  if (icon != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, size: 26),
                    ),
                  const Spacer(),
                  if (trailing != null) Flexible(child: trailing!),
                ],
              ),
              const SizedBox(height: 20),
            ],
            SpatialHeadline(
              title: title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -.6,
                height: 1.2,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Fits whole words to the available column while retaining system text scaling.
class SpatialHeadline extends StatelessWidget {
  const SpatialHeadline({super.key, required this.title, this.style});
  final String title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final resolvedStyle = style ?? Theme.of(context).textTheme.headlineSmall!;
      var widestWord = 0.0;
      for (final word in title.split(RegExp(r'\s+'))) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: resolvedStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        if (painter.width > widestWord) widestWord = painter.width;
        painter.dispose();
      }
      final factor = widestWord > constraints.maxWidth && widestWord > 0
          ? (constraints.maxWidth / widestWord * .98).clamp(0.0, 1.0)
          : 1.0;
      return Text(
        title,
        style: resolvedStyle.copyWith(
          fontSize: (resolvedStyle.fontSize ?? 26) * factor,
        ),
      );
    },
  );
}
