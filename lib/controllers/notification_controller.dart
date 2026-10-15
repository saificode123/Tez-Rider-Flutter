import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationController extends GetxController
    with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  final notifications = <Map<String, dynamic>>[].obs;
  final unreadCount = 0.obs,
      isLoading = true.obs,
      hasMore = false.obs,
      updating = false.obs;
  final error = RxnString();
  int? _appUserId;
  String? _account;
  bool _closed = false, _busy = false, _dirty = false;
  int _generation = 0;
  Timer? _refresh;
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _auth;
  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _auth = _supabase.auth.onAuthStateChange.listen((_) {
      if (_account != _supabase.auth.currentUser?.id) unawaited(_initialize());
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    _account = _supabase.auth.currentUser?.id;
    _appUserId = null;
    notifications.clear();
    unreadCount.value = 0;
    hasMore.value = false;
    _refresh?.cancel();
    _refresh = null;
    final old = _channel;
    _channel = null;
    if (old != null) await _supabase.removeChannel(old);
    if (_closed || generation != _generation) return;
    if (_account == null) {
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    try {
      final id = await _supabase
          .rpc('fr21_actor')
          .timeout(const Duration(seconds: 10));
      if (_closed || generation != _generation) return;
      if (id is! int) throw StateError('Confirmed user required');
      _appUserId = id;
      _channel = _supabase
          .channel('notifications-$id-$generation')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: id,
            ),
            callback: (_) {
              if (_closed || generation != _generation) return;
              _refresh ??= Timer(const Duration(milliseconds: 350), () {
                _refresh = null;
                if (_busy) {
                  _dirty = true;
                } else {
                  unawaited(load());
                }
              });
            },
          )
          .subscribe((status, _) {
            if (!_closed &&
                generation == _generation &&
                status == RealtimeSubscribeStatus.subscribed) {
              if (_busy) {
                _dirty = true;
              } else {
                unawaited(load());
              }
            }
            if (!_closed &&
                generation == _generation &&
                (status == RealtimeSubscribeStatus.channelError ||
                    status == RealtimeSubscribeStatus.timedOut)) {
              error.value = 'Live notifications disconnected. Tap Retry.';
            }
          });
      if (_busy) {
        _dirty = true;
      } else {
        await load();
      }
    } catch (_) {
      if (!_closed && generation == _generation) {
        error.value = 'Could not load notifications. Tap Retry.';
      }
    } finally {
      if (!_closed && generation == _generation) isLoading.value = false;
    }
  }

  Future<void> retry() async {
    await _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_closed) {
      if (_busy) {
        _dirty = true;
      } else {
        unawaited(load());
      }
    }
  }

  Future<void> load({bool append = false}) async {
    if (_closed ||
        _busy ||
        _appUserId == null ||
        _account != _supabase.auth.currentUser?.id) {
      return;
    }
    final generation = _generation;
    _busy = true;
    isLoading.value = true;
    error.value = null;
    try {
      var query = _supabase
          .from('notifications')
          .select('id,title,message,type,is_read,created_at,dispute_id')
          .eq('user_id', _appUserId!);
      if (append && notifications.isNotEmpty) {
        query = query.lt('id', notifications.last['id']);
      }
      final rows = await query
          .order('id', ascending: false)
          .limit(30)
          .timeout(const Duration(seconds: 10));
      final count = await _supabase
          .from('notifications')
          .count()
          .eq('user_id', _appUserId!)
          .eq('is_read', false)
          .timeout(const Duration(seconds: 10));
      if (_closed || generation != _generation) return;
      if (append) {
        final ids = notifications.map((n) => n['id']).toSet();
        notifications.addAll(rows.where((n) => !ids.contains(n['id'])));
      } else {
        notifications.assignAll(rows);
      }
      hasMore.value = rows.length == 30;
      unreadCount.value = count;
    } catch (_) {
      if (!_closed && generation == _generation) {
        error.value = 'Could not load notifications. Tap Retry.';
      }
    } finally {
      _busy = false;
      if (!_closed && generation == _generation) isLoading.value = false;
      if (_dirty && !_closed) {
        _dirty = false;
        unawaited(load());
      }
    }
  }

  Future<void> markAsRead(String id) async {
    if (updating.value || _appUserId == null || _closed) return;
    updating.value = true;
    try {
      final changed = await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id)
          .eq('user_id', _appUserId!)
          .select('id,is_read')
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (changed == null || changed['is_read'] != true) {
        throw StateError('Read state unconfirmed');
      }
      await load();
    } catch (_) {
      if (!_closed) error.value = 'Read status was not confirmed. Retry.';
    } finally {
      if (!_closed) updating.value = false;
    }
  }

  Future<void> markAllAsRead() async {
    if (updating.value || _appUserId == null || _closed) return;
    updating.value = true;
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', _appUserId!)
          .eq('is_read', false)
          .timeout(const Duration(seconds: 10));
      await load();
    } catch (_) {
      if (!_closed) error.value = 'Read status was not confirmed. Retry.';
    } finally {
      if (!_closed) updating.value = false;
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _closed = true;
    _generation++;
    _refresh?.cancel();
    unawaited(_auth?.cancel());
    final old = _channel;
    _channel = null;
    if (old != null) unawaited(_supabase.removeChannel(old));
    super.onClose();
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
