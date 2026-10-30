import 'dart:async';

import 'package:get/get.dart';

import 'delivery_otp_service.dart' show deliveryRequestId;

const unavailableRiderLocation = 'Rider location temporarily unavailable.';

class DeviceFix {
  const DeviceFix(this.latitude, this.longitude, this.accuracy, this.at);
  final double latitude, longitude, accuracy;
  final DateTime at;
  bool valid(DateTime now) =>
      latitude.isFinite &&
      longitude.isFinite &&
      accuracy.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      accuracy >= 0 &&
      accuracy <= 100 &&
      !at.isBefore(now.subtract(const Duration(seconds: 30))) &&
      !at.isAfter(now.add(const Duration(seconds: 5)));
}

abstract class RiderLocationSource {
  /// Returns a safe user-facing problem, or null when ready.
  Future<String?> prepare({
    required bool requestPermission,
    bool delivery = false,
  });
  Stream<DeviceFix> positions({required bool delivery});
  Stream<bool> get serviceEnabled;
}

/// Optional platform guidance; the accepted Android source stays unchanged.
abstract class RiderLocationGuidance {
  String? get notice;
  String get waitingForFixMessage;
  Future<bool> openSettings();
}

abstract class DeliveryLocationBackend {
  String get accountId;
  Future<Map<String, dynamic>> context(int order, {bool? enable});
  Future<String> publish(int order, DeviceFix fix, String request);
  Future<void> idle(DeviceFix fix);
}

/// One owned device stream: low-frequency foreground idle OR delivery foreground
/// service. No timer requests GPS and no missing fix is synthesized.
class RiderLocationService extends GetxService {
  RiderLocationService(
    this.source,
    this.backend, {
    DateTime Function()? now,
    Duration Function()? elapsed,
    this.onMetric,
  }) : now = now ?? DateTime.now,
       elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter;
  final RiderLocationSource source;
  final DeliveryLocationBackend backend;
  final DateTime Function() now;
  final Duration Function() elapsed;

  /// Numeric stage timings only; no positions, identities or credentials.
  final void Function(String, num)? onMetric;
  final sharing = false.obs, busy = false.obs;
  final message = 'Location sharing is off.'.obs;
  final latestFix = Rxn<DeviceFix>();

  /// Delivery routing starts only after the server confirms this genuine fix.
  /// Native fixes can arrive before fr13_submit_location has committed them.
  final publishedFix = Rxn<DeviceFix>();
  StreamSubscription<DeviceFix>? _positions;
  StreamSubscription<bool>? _services;
  int? _order, _sharingOrder;
  bool _online = false, _foreground = true, _closed = false, _sending = false;
  bool _presenceSuspended = false, _resumingPresence = false;
  String _account = '';
  int _generation = 0, _failures = 0, _operation = 0;
  Future<void>? _stopWork;
  (int, String, Future<Map<String, dynamic>>)? _pendingEnable;
  bool _nativeStopConfirmed = true;
  Duration? _lastSent, _retryAt;
  (DeviceFix, int, bool)? _pendingFix;
  Timer? _pendingTimer;
  (DeviceFix, Duration)? _receivedFix;

  RiderLocationGuidance? get _guidance =>
      source is RiderLocationGuidance ? source as RiderLocationGuidance : null;
  bool get hasSettingsLink => _guidance != null;
  Future<void> openSettings() async {
    if (_closed || !_foreground || _guidance == null) return;
    try {
      if (!await _guidance!.openSettings() && !_closed) {
        message.value =
            'Settings could not be opened. Open TezRider location settings manually.';
      }
    } catch (_) {
      if (!_closed) {
        message.value =
            'Settings could not be opened. Open TezRider location settings manually.';
      }
    }
  }

  Future<void> reconcile({
    required bool online,
    required int? activeOrder,
    required bool foreground,
    bool presenceInterrupted = false,
  }) async {
    final account = backend.accountId;
    final sameDelivery =
        !_closed &&
        _account == account &&
        account.isNotEmpty &&
        _order == activeOrder &&
        activeOrder != null &&
        _sharingOrder == activeOrder &&
        sharing.value;
    if (presenceInterrupted && sameDelivery) {
      _foreground = foreground;
      _presenceSuspended = true;
      publishedFix.value = null;
      _pendingFix = null;
      _pendingTimer?.cancel();
      _pendingTimer = null;
      message.value =
          'Connection lost. Waiting for confirmed delivery availability.';
      return;
    }
    if (_presenceSuspended && sameDelivery && online) {
      if (_resumingPresence) return;
      _resumingPresence = true;
      final generation = _generation;
      try {
        final problem = await source.prepare(
          requestPermission: false,
          delivery: true,
        );
        if (!_valid(generation)) return;
        if (problem != null) {
          await _halt(problem);
          return;
        }
        final context = await _enableTracking(activeOrder);
        if (!_valid(generation)) return;
        if (context['code'] != 'OK' || context['sharing'] != true) {
          await _halt(
            'Location sharing stopped: delivery is no longer eligible.',
          );
          return;
        }
        _presenceSuspended = false;
        _retryAt = null;
        _lastSent = null;
        message.value = 'Sharing your live location.';
      } catch (_) {
        // Preserve only the existing consent; no publishing until server checks
        // succeed. A later presence update retries this reconciliation.
        return;
      } finally {
        _resumingPresence = false;
      }
    }
    final changed =
        _account != account || _order != activeOrder || _online != online;
    final resumed = foreground && !_foreground;
    _foreground = foreground;
    if (changed) {
      await _cancel();
      _account = account;
      _order = activeOrder;
      _online = online;
      _sharingOrder = null;
    }
    if (_closed || !online || account.isEmpty) {
      await _cancel();
      message.value = 'Location sharing is off.';
      return;
    }
    if (sharing.value && _sharingOrder == activeOrder) {
      // iOS Settings can change authorization/accuracy while the stream exists.
      // Recheck without prompting or creating a duplicate subscription.
      if (resumed && _guidance != null) {
        final generation = _generation;
        try {
          final problem = await source.prepare(
            requestPermission: false,
            delivery: true,
          );
          if (!_valid(generation)) return;
          if (problem != null) {
            await _halt(problem);
          } else {
            message.value =
                _guidance?.notice ??
                'Sharing your live location. Keep GPS enabled.';
          }
        } catch (_) {
          if (_valid(generation)) {
            await _halt(
              'Location access could not be checked. Check Settings and retry sharing.',
            );
          }
        }
      }
      return;
    }
    if (!foreground) {
      await _cancel();
      return;
    }
    if (_positions == null && !busy.value) await _startIdle();
  }

  Future<void> _startIdle() async {
    final operation = ++_operation;
    busy.value = true;
    final generation = _generation;
    var failed = false;
    try {
      if (!_nativeStopConfirmed) {
        message.value =
            'Sharing stopped. Reopen the app to reset the location service.';
        return;
      }
      final problem = await source.prepare(requestPermission: false);
      if (!_valid(generation)) return;
      if (problem != null) {
        message.value = problem;
        return;
      }
      _listen(delivery: false);
      message.value =
          _guidance?.notice ??
          'Online: location refreshes once a minute for delivery matching.';
    } catch (_) {
      failed = true;
      if (_valid(generation)) {
        await _cancel();
        message.value = 'Location is unavailable. Check permission and GPS.';
      }
    } finally {
      if (!_closed && operation == _operation) busy.value = false;
      if (!failed &&
          operation == _operation &&
          !_closed &&
          generation != _generation &&
          _online &&
          _foreground &&
          _account == backend.accountId &&
          _positions == null) {
        unawaited(_startIdle());
      }
    }
  }

  Future<void> share(int order) async {
    if (_closed ||
        busy.value ||
        !_online ||
        !_foreground ||
        backend.accountId.isEmpty) {
      return;
    }
    if (sharing.value && _sharingOrder == order) return;
    final operation = ++_operation;
    busy.value = true;
    await _cancel();
    final generation = _generation;
    _account = backend.accountId;
    try {
      if (!_nativeStopConfirmed) {
        message.value =
            'Sharing stopped. Reopen the app to reset the location service.';
        return;
      }
      final problem = await source.prepare(
        requestPermission: true,
        delivery: true,
      );
      if (!_valid(generation)) return;
      if (problem != null) {
        message.value = problem;
        return;
      }
      final context = await _enableTracking(order);
      if (!_valid(generation)) return;
      if (context['code'] != 'OK' ||
          context['sharing'] != true ||
          context['order_id'] != order) {
        message.value =
            'Sharing requires an online rider, completed checklist and started delivery.';
        return;
      }
      _order = order;
      _sharingOrder = order;
      sharing.value = true;
      message.value =
          _guidance?.notice ?? 'Sharing your live location. Keep GPS enabled.';
      _listen(delivery: true);
    } catch (_) {
      if (_valid(generation)) {
        await stop();
        message.value =
            'Sharing was not confirmed. Check your connection and retry.';
      }
    } finally {
      if (!_closed && operation == _operation) busy.value = false;
    }
  }

  Future<void> allowIdlePermission() async {
    if (_closed || !_foreground) return;
    try {
      final problem = await source.prepare(requestPermission: true);
      if (!_closed && problem != null) message.value = problem;
    } catch (_) {
      if (!_closed) {
        message.value =
            'Location permission could not be checked. Retry when the app is open.';
      }
    }
  }

  Future<Map<String, dynamic>> _enableTracking(int order) async {
    final enable = (order, _account, backend.context(order, enable: true));
    _pendingEnable = enable;
    try {
      return await enable.$3;
    } finally {
      if (identical(_pendingEnable?.$3, enable.$3)) _pendingEnable = null;
    }
  }

  bool _valid(int generation) =>
      !_closed && generation == _generation && _account == backend.accountId;
  void _listen({required bool delivery}) {
    final generation = _generation;
    DateTime? previousDeviceAt;
    Duration? previousArrival;
    _lastSent = null;
    _retryAt = null;
    _failures = 0;
    _services = source.serviceEnabled.listen(
      (enabled) {
        if (!enabled && _valid(generation)) {
          unawaited(
            _halt('Location services are disabled. Enable GPS and retry.'),
          );
        }
      },
      onError: (Object _) {
        if (_valid(generation)) {
          unawaited(
            _halt('GPS status is unavailable. Retry location sharing.'),
          );
        }
      },
    );
    _positions = source
        .positions(delivery: delivery)
        .listen(
          (fix) {
            if (_valid(generation)) {
              final arrival = elapsed();
              if (delivery) {
                if (previousDeviceAt != null) {
                  onMetric?.call(
                    'fix_device_interval',
                    fix.at.difference(previousDeviceAt!).inMilliseconds,
                  );
                }
                if (previousArrival != null) {
                  onMetric?.call(
                    'fix_arrival_interval',
                    (arrival - previousArrival!).inMilliseconds,
                  );
                }
                previousDeviceAt = fix.at;
                previousArrival = arrival;
                _receivedFix = (fix, arrival);
              }
              unawaited(_send(fix, generation, delivery));
            }
          },
          onError: (Object _) {
            if (_valid(generation)) {
              unawaited(
                _halt(
                  'Location permission or GPS was interrupted. Check settings and retry.',
                ),
              );
            }
          },
          onDone: () {
            if (_valid(generation)) {
              unawaited(
                _halt(
                  'Location service stopped. Reopen the app and retry sharing.',
                ),
              );
            }
          },
        );
  }

  Future<void> _send(DeviceFix fix, int generation, bool delivery) async {
    if (!_valid(generation) || !_online || _presenceSuspended) return;
    if (!fix.valid(now().toUtc())) {
      message.value =
          _guidance?.waitingForFixMessage ??
          'Waiting for a fresh, accurate GPS fix.';
      return;
    }
    latestFix.value = fix;
    if (_sending) {
      // Keep one newest genuine fix, never a backlog. It is revalidated after
      // the request completes, including rate, freshness and session checks.
      if (delivery) _pendingFix = (fix, generation, delivery);
      return;
    }
    final tick = elapsed();
    final interval = delivery
        ? const Duration(milliseconds: 2300)
        : const Duration(minutes: 1);
    if (_retryAt != null && tick < _retryAt!) return;
    if (_lastSent != null && tick - _lastSent! < interval) {
      if (delivery) {
        _pendingFix = (fix, generation, delivery);
        // Flush a genuine queued fix when the rate window opens, rather than
        // dropping it and waiting an entire additional native fix interval.
        // This timer never obtains, repeats or manufactures a device position.
        _pendingTimer ??= Timer(interval - (tick - _lastSent!), () {
          _pendingTimer = null;
          final pending = _pendingFix;
          _pendingFix = null;
          if (pending != null && _valid(pending.$2)) {
            unawaited(_send(pending.$1, pending.$2, pending.$3));
          }
        });
      }
      return;
    }
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingFix = null;
    _lastSent = tick;
    _sending = true;
    final sentAt = elapsed();
    try {
      if (delivery) {
        final received = _receivedFix;
        if (received != null && identical(received.$1, fix)) {
          onMetric?.call('client_queue', (sentAt - received.$2).inMilliseconds);
        }
        final code = await backend.publish(
          _sharingOrder!,
          fix,
          deliveryRequestId(),
        );
        onMetric?.call(
          'publish_roundtrip',
          (elapsed() - sentAt).inMilliseconds,
        );
        if (!_valid(generation)) return;
        if (const [
          'FORBIDDEN',
          'INELIGIBLE',
          'SHARING_STOPPED',
          'FR28_ACCOUNT_BLOCKED',
          'FR28_SESSION_REVOKED',
          'SESSION_EXPIRED',
        ].contains(code)) {
          await _halt(
            'Location sharing stopped: delivery or account is no longer eligible.',
          );
          return;
        }
        if (!const ['PUBLISHED', 'REPLAYED', 'RATE_LIMIT'].contains(code)) {
          if (const ['STALE_FIX', 'INVALID_LOCATION'].contains(code)) {
            message.value =
                'Waiting for a fresh, accurate GPS fix. Check the device date and time.';
            return;
          }
          throw StateError('Unconfirmed');
        }
        if (const ['PUBLISHED', 'REPLAYED'].contains(code) &&
            !_presenceSuspended &&
            sharing.value &&
            fix.valid(now().toUtc())) {
          publishedFix.value = fix;
        }
        message.value = code == 'PUBLISHED'
            ? _guidance?.notice ?? 'Sharing your live location.'
            : 'Waiting for the next fresh GPS fix.';
      } else {
        await backend.idle(fix);
      }
      _failures = 0;
      _retryAt = null;
    } catch (_) {
      if (_valid(generation)) {
        _pendingFix = null;
        _pendingTimer?.cancel();
        _pendingTimer = null;
        _failures = (_failures + 1).clamp(1, 4);
        _retryAt = elapsed() + Duration(seconds: 1 << _failures);
        message.value =
            'Location update not confirmed. Retrying when a fresh fix is available.';
      }
    } finally {
      _sending = false;
      final pending = _pendingFix;
      _pendingFix = null;
      if (pending != null && _valid(pending.$2)) {
        unawaited(_send(pending.$1, pending.$2, pending.$3));
      }
    }
  }

  Future<void> stop() =>
      _stopWork ??= _performStop().whenComplete(() => _stopWork = null);

  Future<void> _performStop() async {
    final operation = ++_operation;
    busy.value = true;
    try {
      final enabling = _pendingEnable;
      final account = enabling?.$2 ?? _account;
      final order = _sharingOrder ?? enabling?.$1;
      await _cancel();
      _sharingOrder = null;
      message.value = _nativeStopConfirmed
          ? 'Location sharing is off.'
          : 'Sharing stopped. Reopen the app to reset the location service.';
      // A Stop during enable must revoke after that request settles. Sending
      // disable first could let the late enable resurrect server-side consent.
      // Native collection is already cancelled and restart stays busy here.
      if (enabling != null) {
        try {
          await enabling.$3;
        } catch (_) {
          // An unconfirmed enable can still have reached the server.
        }
      }
      if (order != null && backend.accountId == account && account.isNotEmpty) {
        try {
          await backend.context(order, enable: false);
        } catch (_) {
          if (!_closed) {
            message.value =
                'Device sharing stopped. Server cleanup awaits reconnection or lease expiry.';
          }
        }
      }
    } finally {
      if (!_closed && operation == _operation) busy.value = false;
    }
  }

  Future<void> _halt(String problem) async {
    await stop();
    if (!_closed) message.value = problem;
  }

  Future<void> _cancel() async {
    _generation++;
    _presenceSuspended = false;
    _pendingFix = null;
    _receivedFix = null;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    sharing.value = false;
    publishedFix.value = null;
    final position = _positions, services = _services;
    _positions = null;
    _services = null;
    latestFix.value = null;
    try {
      await position?.cancel();
    } catch (_) {
      _nativeStopConfirmed = false;
    }
    try {
      await services?.cancel();
    } catch (_) {
      _nativeStopConfirmed = false;
    }
  }

  @override
  void onClose() {
    unawaited(stop());
    _closed = true;
    _generation++;
    super.onClose();
  }
}

extension on Stopwatch {
  Duration elapsedGetter() => elapsed;
}

/// Customer freshness is anchored to local monotonic receive time, with the
/// authoritative server snapshot age applied immediately when opening a map.
class CustomerLocationState {
  CustomerLocationState({
    Duration Function()? elapsed,
    DateTime Function()? now,
  }) : elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter,
       now = now ?? DateTime.now;
  final Duration Function() elapsed;
  final DateTime Function() now;
  final position = Rxn<DeviceFix>();
  // Memory-only, scoped to this authorized order/assignment. A lost connection
  // can show a timestamped stale pin; explicit revocation always clears it.
  final lastKnown = Rxn<DeviceFix>();
  final authorized = false.obs;
  final availability = 'WAITING'.obs;
  final stale = true.obs;
  Duration? _expires;
  DateTime? _lastReceived;
  Duration _serverOffset = Duration.zero;
  int? order, assignment;
  void open(int? nextOrder, int? nextAssignment, DateTime serverNow) {
    if (order != nextOrder || assignment != nextAssignment) {
      _lastReceived = null;
      clear();
    }
    order = nextOrder;
    assignment = nextAssignment;
    _serverOffset = serverNow.difference(now().toUtc());
    authorized.value = true;
    availability.value = 'WAITING';
  }

  bool receive(Map<String, dynamic> data) {
    if (!authorized.value ||
        data['order_id'] != order ||
        data['assignment_id'] != assignment) {
      return false;
    }
    final lat = data['latitude'],
        lng = data['longitude'],
        accuracy = data['accuracy'];
    final received = DateTime.tryParse(data['received_at']?.toString() ?? '');
    final at = DateTime.tryParse(data['device_at']?.toString() ?? '');
    if (lat is! num ||
        lng is! num ||
        accuracy is! num ||
        received == null ||
        at == null ||
        (_lastReceived != null && !received.isAfter(_lastReceived!))) {
      return false;
    }
    final serverNow = now().toUtc().add(_serverOffset);
    final age = serverNow.difference(received);
    final fix = DeviceFix(
      lat.toDouble(),
      lng.toDouble(),
      accuracy.toDouble(),
      at,
    );
    if (age > const Duration(seconds: 30) ||
        age < const Duration(seconds: -5) ||
        !fix.valid(serverNow)) {
      return false;
    }
    _lastReceived = received;
    _expires =
        elapsed() +
        const Duration(seconds: 30) -
        (age.isNegative ? Duration.zero : age);
    position.value = fix;
    lastKnown.value = fix;
    stale.value = false;
    availability.value = 'LIVE';
    return true;
  }

  void checkFreshness() {
    if (_expires != null && elapsed() > _expires!) {
      _expires = null;
      position.value = null;
      stale.value = true;
      availability.value = 'STALE';
    }
  }

  void clear({String reason = 'UNAVAILABLE'}) {
    authorized.value = false;
    _expires = null;
    position.value = null;
    lastKnown.value = null;
    stale.value = true;
    availability.value = reason;
  }
}

abstract class TrackingSubscription {
  Future<void> close();
}

abstract class CustomerTrackingBackend {
  Future<Map<String, dynamic>> context(int order);
  Future<TrackingSubscription> subscribe(
    String topic,
    int order,
    void Function(Map<String, dynamic>) receive,
    void Function() connected,
    void Function() disconnected,
  );
}

/// Owns one location channel, monotonic freshness and bounded reconnect work.
class CustomerTrackingSession {
  CustomerTrackingSession(
    this.order,
    this.backend, {
    CustomerLocationState? state,
  }) : state = state ?? CustomerLocationState();
  final int order;
  final CustomerTrackingBackend backend;
  final CustomerLocationState state;
  TrackingSubscription? _subscription;
  Timer? _freshness, _retry;
  String? _topic;
  bool _closed = false, _refreshing = false, _pending = false, _started = false;
  int _failures = 0, _generation = 0;
  Future<void> start() async {
    if (_started || _closed) return;
    _started = true;
    _freshness = Timer.periodic(const Duration(seconds: 1), (_) {
      final wasFresh = !state.stale.value;
      state.checkFreshness();
      if (wasFresh && state.stale.value) _scheduleRetry();
    });
    await refresh();
  }

  Future<void> refresh() async {
    if (_closed) return;
    if (_refreshing) {
      _pending = true;
      return;
    }
    _refreshing = true;
    final generation = _generation;
    try {
      final context = await backend.context(order);
      if (_closed || generation != _generation) return;
      if (context['code'] != 'OK' ||
          context['sharing'] != true ||
          context['topic'] is! String) {
        state.clear(
          reason: context['code'] == 'OK'
              ? 'STOPPED'
              : context['code']?.toString() ?? 'UNAVAILABLE',
        );
        await _remove();
        if (!const ['ENDED', 'FORBIDDEN'].contains(context['code'])) {
          _scheduleRetry();
        } else {
          _retry?.cancel();
        }
        return;
      }
      final serverNow = DateTime.tryParse(
        context['server_now']?.toString() ?? '',
      );
      if (serverNow == null || context['assignment_id'] is! int) {
        throw StateError('Unconfirmed');
      }
      state.open(order, context['assignment_id'] as int, serverNow);
      if (context['latest'] is Map) {
        state.receive(Map<String, dynamic>.from(context['latest'] as Map));
      }
      if (_topic != context['topic']) {
        await _remove();
        if (_closed) return;
        final topic = context['topic'] as String;
        _topic = topic;
        final subscription = await backend.subscribe(
          topic,
          order,
          (data) {
            if (!_closed && _topic == topic && state.receive(data)) {
              _failures = 0;
              _retry?.cancel();
            }
          },
          () {
            if (!_closed && _topic == topic) unawaited(refresh());
          },
          () {
            if (!_closed && _topic == topic) _scheduleRetry();
          },
        );
        if (_closed || generation != _generation || _topic != topic) {
          await subscription.close();
          return;
        }
        _subscription = subscription;
      }
      if (state.stale.value) {
        _scheduleRetry();
      } else {
        _failures = 0;
        _retry?.cancel();
      }
    } catch (_) {
      if (_subscription == null) _topic = null;
      _scheduleRetry();
    } finally {
      _refreshing = false;
      if (_pending && !_closed) {
        _pending = false;
        scheduleMicrotask(() => unawaited(refresh()));
      }
    }
  }

  void _scheduleRetry() {
    if (_closed || _retry?.isActive == true) return;
    _failures = (_failures + 1).clamp(1, 5);
    _retry = Timer(
      Duration(seconds: 1 << _failures),
      () => unawaited(refresh()),
    );
  }

  Future<void> _remove() async {
    final old = _subscription;
    _subscription = null;
    _topic = null;
    await old?.close();
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    _freshness?.cancel();
    _retry?.cancel();
    state.clear();
    await _remove();
  }
}
