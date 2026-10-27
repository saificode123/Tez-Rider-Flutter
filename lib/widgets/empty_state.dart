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
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: AppSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.06),
                  ),
                ),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.1),
                  ),
                ),
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                    border: Border.all(
                      color: color.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 34,
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.4,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 10),

            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),

            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!, textAlign: TextAlign.center),
              ),
            ],
          ],
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
      accentColor: const Color(0xFF9B72CF),
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
      accentColor: const Color(0xFF72B77A),
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
      accentColor: Color(0xFF9B72CF),
    );
  }
}
