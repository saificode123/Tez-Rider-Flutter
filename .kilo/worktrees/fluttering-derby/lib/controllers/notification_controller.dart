import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationController extends GetxController {
  final _supabase = Supabase.instance.client;
  var notifications = <Map<String, dynamic>>[].obs;
  var unreadCount = 0.obs;
  var isLoading = true.obs;

  dynamic _appUserId; // the bigint public.users.id — NOT the auth UUID

  @override
  void onInit() {
    super.onInit();
    _listenToNotifications();
  }

  Future<void> _listenToNotifications() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      isLoading.value = false;
      return;
    }

    try {
      final userRecord = await _supabase
          .from('users')
          .select('id')
          .ilike('email', user.email!)
          .maybeSingle();
      if (userRecord == null) {
        isLoading.value = false;
        return;
      }
      _appUserId = userRecord['id'];

      _supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', _appUserId)
          .order('created_at')
          .listen((data) {
        notifications.value = List<Map<String, dynamic>>.from(data).reversed.toList();
        unreadCount.value = notifications.where((n) => n['is_read'] == false).length;
        isLoading.value = false;
      }, onError: (error) {
        debugPrint('Error listening to notifications: $error');
        isLoading.value = false;
      });
    } catch (e) {
      debugPrint('Failed to resolve user for notifications: $e');
      isLoading.value = false;
    }
  }

  Future<void> markAsRead(String id) async {
    try {
      await _supabase.from('notifications').update({'is_read': true}).eq('id', id);
    } catch (e) {
      debugPrint('Failed to mark notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    if (_appUserId == null) return;
    try {
      await _supabase.from('notifications').update({'is_read': true}).eq('user_id', _appUserId).eq('is_read', false);
    } catch (e) {
      debugPrint('Failed to mark all as read: $e');
    }
  }

  /// Sends a notification to a user identified by their app-level
  /// (bigint) user id — NOT the Supabase Auth UUID. Callers already
  /// resolving a vendor_id/user_id via the `users` table (as most of
  /// this app's controllers do) can pass that id straight through.
  static Future<void> sendNotification({
    required dynamic userId,
    required String title,
    required String message,
    String type = 'system',
  }) async {
    try {
      await Supabase.instance.client.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'message': message,
        'type': type,
      });
    } catch (e) {
      debugPrint('Failed to send notification: $e');
    }
  }
}