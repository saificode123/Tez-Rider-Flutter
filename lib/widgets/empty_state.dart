import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accentColor;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.divider),
              boxShadow: AppShadow.soft,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, size: 32, color: color),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.6),
                  textAlign: TextAlign.center,
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: onAction,
                    child: Text(actionLabel!, textAlign: TextAlign.center),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyOrdersState extends StatelessWidget {
  final VoidCallback? onBrowse;
  const EmptyOrdersState({super.key, this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget(
      icon: Icons.receipt_long_outlined,
      title: 'No Orders Yet',
      subtitle:
          'You haven\'t placed any orders.\nBrowse stores and order something delicious!',
      actionLabel: 'Browse Now',
      onAction: onBrowse,
      accentColor: AppColors.primary,
    );
  }
}

class EmptySearchState extends StatelessWidget {
  final String query;
  const EmptySearchState({super.key, required this.query});

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget(
      icon: Icons.search_off_rounded,
      title: 'No Results Found',
      subtitle:
          'We couldn\'t find anything for "$query".\nTry a different search term.',
      accentColor: AppColors.primary,
    );
  }
}

class NoInternetState extends StatelessWidget {
  final VoidCallback? onRetry;
  const NoInternetState({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget(
      icon: Icons.wifi_off_rounded,
      title: 'No Internet Connection',
      subtitle: 'Please check your connection\nand try again.',
      actionLabel: 'Retry',
      onAction: onRetry,
      accentColor: AppColors.info,
    );
  }
}

class EmptyNotificationsState extends StatelessWidget {
  const EmptyNotificationsState({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyStateWidget(
      icon: Icons.notifications_none_rounded,
      title: 'All Caught Up!',
      subtitle:
          'You have no new notifications.\nWe\'ll let you know when something happens.',
      accentColor: AppColors.primary,
    );
  }
}
