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
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A0533),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A0533)),
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
                          'Android notifications',
                          push.status.value,
                        );
                      },
              );
            }),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all as read',
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
                Text(notifCtrl.error.value!),
                TextButton(
                  onPressed: notifCtrl.isLoading.value ? null : notifCtrl.retry,
                  child: const Text('Retry notifications'),
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
                const Text(
                  'No notifications yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We will notify you of any updates.',
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
                child: const Text('Load more notifications'),
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
                            const Text(
                              'Admin broadcast',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                          Text(
                            n['title'] ?? 'Alert',
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
