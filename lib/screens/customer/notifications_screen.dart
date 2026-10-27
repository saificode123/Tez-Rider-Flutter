import '../../theme/app_theme.dart';
import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/notification_controller.dart';
import '../../services/android_broadcast_push_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsScreen extends StatelessWidget {
  NotificationsScreen({super.key});

  final NotificationController notifCtrl = Get.put(NotificationController());

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(
          "Notifications".tr,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (Get.isRegistered<AndroidBroadcastPushService>())
            Obx(() {
              final push = Get.find<AndroidBroadcastPushService>();
              return IconButton(
                tooltip: push.status.value,
                icon: const Icon(Icons.notifications_active_outlined),
                onPressed: push.busy.value || !push.configured
                    ? null
                    : () async {
                        await push.enable();
                        Get.snackbar(
                          "Android notifications".tr,
                          push.status.value,
                        );
                      },
              );
            }),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: "Mark all as read".tr,
            onPressed: () => notifCtrl.markAllAsRead(),
          ),
        ],
      ),
      body: Obx(() {
        if (notifCtrl.error.value != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(notifCtrl.error.value!.uiMessage),
                TextButton(
                  onPressed: notifCtrl.isLoading.value ? null : notifCtrl.retry,
                  child: Text("Retry notifications".tr),
                ),
              ],
            ),
          );
        }
        if (notifCtrl.isLoading.value && notifCtrl.notifications.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF1B5E20)),
          );
        }

        if (notifCtrl.notifications.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  size: 80,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  "No notifications yet".tr,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "We will notify you of any updates.".tr,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount:
              notifCtrl.notifications.length +
              (notifCtrl.hasMore.value ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == notifCtrl.notifications.length) {
              return TextButton(
                onPressed: notifCtrl.isLoading.value
                    ? null
                    : () => notifCtrl.load(append: true),
                child: Text("Load more notifications".tr),
              );
            }
            final n = notifCtrl.notifications[i];
            final bool isRead = n['is_read'] ?? true;
            final DateTime? date = n['created_at'] != null
                ? DateTime.tryParse(n['created_at'])
                : null;

            return GestureDetector(
              onTap: () {
                if (!isRead) notifCtrl.markAsRead(n['id'].toString());
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isRead
                      ? Colors.white
                      : const Color(0xFF1B5E20).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: isRead
                      ? Border.all(color: Colors.black.withValues(alpha: 0.05))
                      : Border.all(
                          color: const Color(0xFF1B5E20).withValues(alpha: 0.3),
                        ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isRead
                            ? Colors.grey.shade100
                            : const Color(0xFF1B5E20).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isRead
                            ? Icons.notifications_none
                            : Icons.notifications_active,
                        color: isRead ? Colors.grey : const Color(0xFF1B5E20),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (n['type'] == 'broadcast')
                            Text(
                              "Admin broadcast".tr,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                          Text(
                            n['title'] ?? "Alert".tr,
                            style: TextStyle(
                              fontWeight: isRead
                                  ? FontWeight.w600
                                  : FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            n['message'] ?? '',
                            style: TextStyle(
                              color: isRead
                                  ? Colors.grey.shade700
                                  : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                          if (date != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              timeago.format(date),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isRead)
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE91E63),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
