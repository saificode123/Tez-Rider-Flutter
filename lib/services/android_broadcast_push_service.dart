import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;
import 'broadcast_push_delivery.dart';

bool get androidTestPushEnabled =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    appFlavor == 'fr21test' &&
    const bool.fromEnvironment('FR30_ANDROID_PUSH') &&
    const bool.fromEnvironment('FR21_ISOLATED_TEST', defaultValue: true) &&
    const String.fromEnvironment('SUPABASE_URL', defaultValue: pushTestUrl) ==
        pushTestUrl;

const _storage = FlutterSecureStorage();
const _channel = AndroidNotificationChannel(
  'fr30_admin_broadcasts',
  'TezRider updates',
  description: 'Order, delivery and account updates from TezRider',
  importance: Importance.high,
);

Future<void> _showNotice(String id, String title, String message) async {
  final ticket = await _storage.read(key: pushTicketKey);
  if (ticket == null) return;
  final account = jsonDecode(ticket) as Map;
  final scope = '${account['owner']}:${account['session']}';
  final saved = await _storage.read(key: 'fr30_push_seen');
  final previous = saved == null ? null : jsonDecode(saved) as Map;
  final seen = previous?['scope'] == scope
      ? List<String>.from(previous?['ids'] as List? ?? [])
      : <String>[];
  if (seen.contains(id)) return;
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (_) {
      if (Get.isRegistered<AndroidBroadcastPushService>()) {
        Get.find<AndroidBroadcastPushService>().requestOpen();
      }
    },
  );
  final notificationId = int.parse(id.substring(0, 8), radix: 16) & 0x7fffffff;
  final posted = await publishPushForSession(
    ticket: ticket,
    readTicket: () => _storage.read(key: pushTicketKey),
    withdraw: () => plugin.cancel(notificationId, tag: id),
    publish: () => plugin.show(
      notificationId,
      title,
      message,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          tag: id,
          onlyAlertOnce: true,
        ),
      ),
      payload: id,
    ),
  );
  if (!posted) return;
  await _storage.write(
    key: 'fr30_push_seen',
    value: jsonEncode({
      'scope': scope,
      'ids': [id, ...seen].take(100).toList(),
    }),
  );
}

Future<void> _receiveHint(RemoteMessage message) async {
  final delivery = BroadcastPushDelivery(
    readTicket: () => _storage.read(key: pushTicketKey),
    display: _showNotice,
    publicKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  try {
    await delivery.receive(message.data);
  } finally {
    delivery.close();
  }
}

@pragma('vm:entry-point')
Future<void> androidBroadcastBackgroundMessage(RemoteMessage message) async {
  if (!androidTestPushEnabled) return;
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    await _receiveHint(message);
  } catch (_) {
    /* A missing configuration or denied lookup never displays text. */
  }
}

class AndroidBroadcastPushService extends GetxService {
  final status = 'Android notifications are not enabled.'.obs;
  final busy = false.obs;
  final plugin = FlutterLocalNotificationsPlugin();
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<String>? _registration;
  StreamSubscription<RemoteMessage>? _messages;
  bool configured = false, _closed = false, _openPending = false;
  int _generation = 0;
  Future<void> _sessionWork = Future.value();

  Future<void> initialize() async {
    if (!androidTestPushEnabled) return;
    try {
      final app = await Firebase.initializeApp().timeout(
        const Duration(seconds: 8),
      );
      if (app.options.projectId !=
          const String.fromEnvironment(
            'FR30_FIREBASE_PROJECT_ID',
            defaultValue: 'tez-rider-fe12b',
          )) {
        throw StateError('Firebase TEST project mismatch');
      }
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (_) => requestOpen(),
      );
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
      _openPending =
          (await plugin.getNotificationAppLaunchDetails())
              ?.didNotificationLaunchApp ??
          false;
      FirebaseMessaging.onBackgroundMessage(androidBroadcastBackgroundMessage);
      _messages = FirebaseMessaging.onMessage.listen(
        (message) => unawaited(_receiveHint(message)),
      );
      _registration = FirebaseMessaging.instance.onRegistered.listen(
        (fid) => unawaited(_register(fid)),
        onError: (_) =>
            status.value = 'Android registration failed. Tap Enable to retry.',
      );
      configured = true;
      _auth = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        // Leave the synchronous Auth callback before invoking authenticated RPCs.
        _sessionWork = _sessionWork
            .then((_) => _syncSession())
            .catchError((_) {});
      });
      await _syncSession();
    } catch (_) {
      status.value = 'Android push configuration is unavailable.';
    }
  }

  String _sessionId(Session session) {
    final claims =
        jsonDecode(
              utf8.decode(
                base64Url.decode(
                  base64Url.normalize(session.accessToken.split('.')[1]),
                ),
              ),
            )
            as Map;
    return claims['session_id'] as String;
  }

  Future<void> _syncSession() async {
    if (_closed || !configured) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      await clearLocal();
      return;
    }
    final old = await _storage.read(key: pushTicketKey);
    final data = old == null ? null : jsonDecode(old) as Map;
    if (data == null ||
        data['owner'] != session.user.id ||
        data['session'] != _sessionId(session)) {
      final random = Random.secure();
      final ticket = {
        'owner': session.user.id,
        'session': _sessionId(session),
        'installation': blockRequestId(),
        'secret': List.generate(
          32,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
      };
      await _storage.write(key: pushTicketKey, value: jsonEncode(ticket));
    }
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await FirebaseMessaging.instance.register();
    } else {
      status.value = 'Tap Enable to allow Android notifications.';
    }
  }

  Future<void> enable() async {
    if (busy.value || !configured || _closed) return;
    busy.value = true;
    try {
      final permission = await FirebaseMessaging.instance.requestPermission();
      if (permission.authorizationStatus != AuthorizationStatus.authorized) {
        status.value =
            'Android notification permission is denied. Enable it in system settings.';
        return;
      }
      await _syncSession();
    } catch (_) {
      status.value = 'Android notifications could not be enabled. Retry.';
    } finally {
      if (!_closed) busy.value = false;
    }
  }

  Future<void> _register(String fid) async {
    final generation = ++_generation;
    try {
      final ticket = await _storage.read(key: pushTicketKey);
      if (ticket == null || _closed) return;
      final data = jsonDecode(ticket) as Map;
      final result = await Supabase.instance.client
          .rpc(
            'fr30_register_push',
            params: {
              'p_installation': data['installation'],
              'p_token': fid,
              'p_secret': data['secret'],
            },
          )
          .timeout(const Duration(seconds: 10));
      if (_closed ||
          generation != _generation ||
          await _storage.read(key: pushTicketKey) != ticket) {
        return;
      }
      status.value = result['code'] == 'REGISTERED'
          ? 'Android notifications enabled.'
          : result['code'] == 'PUSH_NOT_CONFIGURED'
          ? 'Android sender setup is pending.'
          : 'Android registration was not confirmed. Retry.';
    } catch (_) {
      if (!_closed && generation == _generation) {
        status.value = 'Android registration was not confirmed. Retry.';
      }
    }
  }

  Future<void> unregisterBeforeLogout() async {
    try {
      final ticket = await _storage.read(key: pushTicketKey);
      await clearLocal();
      if (ticket == null) return;
      final data = jsonDecode(ticket) as Map;
      await Supabase.instance.client
          .rpc(
            'fr30_unregister_push',
            params: {'p_installation': data['installation']},
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      /* Device credential is already erased; server session gates remain. */
    }
  }

  Future<void> clearLocal() async {
    _generation++;
    _openPending = false;
    await _storage.delete(key: pushTicketKey);
    await _storage.delete(key: 'fr30_push_seen');
    if (configured) {
      try {
        await plugin.cancelAll();
      } catch (_) {}
      try {
        await FirebaseMessaging.instance.unregister().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {}
    }
    status.value = 'Android notifications require sign-in.';
  }

  bool takeOpenRequest() {
    if (!_openPending || Supabase.instance.client.auth.currentUser == null) {
      return false;
    }
    _openPending = false;
    return true;
  }

  void requestOpen() {
    _openPending = true;
    openPendingIfReady();
  }

  void openPendingIfReady() {
    if (!_openPending ||
        Get.context == null ||
        Supabase.instance.client.auth.currentUser == null ||
        [
          '/',
          '/login',
          '/signup',
          '/pending_verification',
        ].contains(Get.currentRoute)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!takeOpenRequest()) return;
      if (Get.currentRoute != '/notifications' &&
          !Get.currentRoute.contains('NotificationsScreen')) {
        Get.toNamed('/notifications');
      }
    });
  }

  @override
  void onClose() {
    _closed = true;
    _generation++;
    unawaited(_auth?.cancel());
    unawaited(_registration?.cancel());
    unawaited(_messages?.cancel());
    super.onClose();
  }
}
