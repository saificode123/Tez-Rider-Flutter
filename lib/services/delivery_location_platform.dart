import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'delivery_location.dart';
import 'ios_rider_location_source.dart';

RiderLocationSource createRiderLocationSource() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
    ? IosRiderLocationSource()
    : AndroidRiderLocationSource();

class AndroidRiderLocationSource implements RiderLocationSource {
  @override
  Future<String?> prepare({
    required bool requestPermission,
    bool delivery = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'Delivery location sharing is currently available on Android only.';
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Location services are disabled. Enable GPS and retry.';
    }
    var permission = await Geolocator.checkPermission();
    if (requestPermission &&
        permission == LocationPermission.denied &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location permission is blocked. Enable it in app settings and retry.';
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return 'Allow location permission to refresh delivery matching and share an active delivery.';
    }
    if (delivery && requestPermission) {
      final notifications = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await notifications?.areNotificationsEnabled() == false &&
          await notifications?.requestNotificationsPermission() != true) {
        return 'Allow notifications so active delivery location sharing remains visible.';
      }
    }
    return null;
  }

  @override
  Stream<bool> get serviceEnabled => Geolocator.getServiceStatusStream().map(
    (status) => status == ServiceStatus.enabled,
  );
  @override
  Stream<DeviceFix> positions({required bool delivery}) =>
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: delivery ? LocationAccuracy.high : LocationAccuracy.medium,
          distanceFilter: 0,
          intervalDuration: delivery
              ? const Duration(milliseconds: 2500)
              : const Duration(minutes: 1),
          foregroundNotificationConfig: delivery
              ? const ForegroundNotificationConfig(
                  notificationTitle: 'TezRider delivery location',
                  notificationText:
                      'Sharing location for your active delivery. Stop sharing in the TEST app.',
                  notificationChannelName: 'Active delivery location',
                  enableWakeLock: true,
                  setOngoing: true,
                )
              : null,
        ),
      ).map(
        (p) =>
            DeviceFix(p.latitude, p.longitude, p.accuracy, p.timestamp.toUtc()),
      );
}

class SupabaseDeliveryLocationBackend implements DeliveryLocationBackend {
  SupabaseClient get client => Supabase.instance.client;
  Future<void> _freshSession() async {
    final session = client.auth.currentSession;
    if (session == null) throw StateError('Session required');
    final expiry = session.expiresAt;
    if (expiry != null &&
        expiry * 1000 <= DateTime.now().millisecondsSinceEpoch + 60000) {
      await client.auth.refreshSession().timeout(const Duration(seconds: 10));
      if (client.auth.currentUser?.id != session.user.id) {
        throw StateError('Account changed');
      }
    }
  }

  @override
  String get accountId => client.auth.currentUser?.id ?? '';
  @override
  Future<Map<String, dynamic>> context(int order, {bool? enable}) async {
    await _freshSession();
    return Map<String, dynamic>.from(
      await client
          .rpc(
            'fr13_tracking_context',
            params: {
              'p_order_id': order,
              if (enable != null) 'p_enable': enable,
            },
          )
          .timeout(const Duration(seconds: 10)),
    );
  }

  @override
  Future<String> publish(int order, DeviceFix fix, String request) async {
    try {
      await _freshSession();
      final response = await client.functions
          .invoke(
            'fr13-location',
            body: {
              'order_id': order,
              'latitude': fix.latitude,
              'longitude': fix.longitude,
              'accuracy': fix.accuracy,
              'device_at': fix.at.toUtc().toIso8601String(),
              'request_id': request,
            },
          )
          .timeout(const Duration(seconds: 15));
      return response.data is Map
          ? response.data['code']?.toString() ?? 'UNAVAILABLE'
          : 'UNAVAILABLE';
    } on FunctionException catch (error) {
      return error.details is Map
          ? (error.details as Map)['code']?.toString() ?? 'UNAVAILABLE'
          : 'UNAVAILABLE';
    }
  }

  @override
  Future<void> idle(DeviceFix fix) async {
    await _freshSession();
    await client
        .rpc(
          'fr21_update_location',
          params: {'p_lat': fix.latitude, 'p_lng': fix.longitude},
        )
        .timeout(const Duration(seconds: 8));
  }
}

class _SupabaseTrackingSubscription implements TrackingSubscription {
  _SupabaseTrackingSubscription(this.client, this.channel);
  final SupabaseClient client;
  final RealtimeChannel channel;
  @override
  Future<void> close() async {
    await client.removeChannel(channel);
  }
}

class SupabaseCustomerTrackingBackend implements CustomerTrackingBackend {
  final SupabaseClient client = Supabase.instance.client;
  @override
  Future<Map<String, dynamic>> context(int order) async {
    final result = await SupabaseDeliveryLocationBackend().context(order);
    if (result['code'] == 'INELIGIBLE') {
      final row = await client
          .from('orders')
          .select('order_status')
          .eq('id', order)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (row == null ||
          const ['delivered', 'cancelled'].contains(row['order_status'])) {
        return {'code': 'ENDED'};
      }
    }
    return result;
  }

  @override
  Future<TrackingSubscription> subscribe(
    String topic,
    int order,
    void Function(Map<String, dynamic>) receive,
    void Function() connected,
    void Function() disconnected,
  ) async {
    final channel = client
        .channel(topic, opts: const RealtimeChannelConfig(private: true))
        .onBroadcast(event: 'location', callback: receive)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: order,
          ),
          callback: (_) => connected(),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            connected();
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            disconnected();
          }
        });
    return _SupabaseTrackingSubscription(client, channel);
  }
}

class CustomerLocationFeed with WidgetsBindingObserver {
  CustomerLocationFeed(int order, {CustomerLocationState? state})
    : session = CustomerTrackingSession(
        order,
        SupabaseCustomerTrackingBackend(),
        state: state,
      );
  final CustomerTrackingSession session;
  CustomerLocationState get state => session.state;
  StreamSubscription<AuthState>? _auth;
  bool _closed = false;
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    final account = Supabase.instance.client.auth.currentUser?.id;
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((change) {
      if (change.event == AuthChangeEvent.signedOut ||
          change.session?.user.id != account) {
        unawaited(dispose());
      } else if (change.event == AuthChangeEvent.tokenRefreshed) {
        unawaited(refresh());
      }
    });
    await session.start();
  }

  Future<void> refresh() => session.refresh();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      session.state.checkFreshness();
      unawaited(refresh());
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    await _auth?.cancel();
    await session.dispose();
  }
}
