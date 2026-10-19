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
  }) : now = now ?? DateTime.now,
       elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter;
  final RiderLocationSource source;
  final DeliveryLocationBackend backend;
  final DateTime Function() now;
  final Duration Function() elapsed;
  final sharing = false.obs, busy = false.obs;
  final message = 'Location sharing is off.'.obs;
  final latestFix = Rxn<DeviceFix>();
  StreamSubscription<DeviceFix>? _positions;
  StreamSubscription<bool>? _services;
  int? _order, _sharingOrder;
  bool _online = false, _foreground = true, _closed = false, _sending = false;
  String _account = '';
  int _generation = 0, _failures = 0, _operation = 0;
  Future<void>? _stopWork;
  bool _nativeStopConfirmed = true;
  Duration? _lastSent, _retryAt;
  (DeviceFix, int, bool)? _pendingFix;

  Future<void> reconcile({
    required bool online,
    required int? activeOrder,
    required bool foreground,
  }) async {
    final account = backend.accountId;
    final changed =
        _account != account || _order != activeOrder || _online != online;
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
    if (sharing.value && _sharingOrder == activeOrder) return;
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
      final context = await backend.context(order, enable: true);
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
      message.value = 'Sharing your live location. Keep GPS enabled.';
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

  bool _valid(int generation) =>
      !_closed && generation == _generation && _account == backend.accountId;
  void _listen({required bool delivery}) {
    final generation = _generation;
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
            if (_valid(generation)) unawaited(_send(fix, generation, delivery));
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
    if (!_valid(generation) || !_online) return;
    if (!fix.valid(now().toUtc())) {
      message.value = 'Waiting for a fresh, accurate GPS fix.';
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
    if ((_lastSent != null && tick - _lastSent! < interval) ||
        (_retryAt != null && tick < _retryAt!)) {
      return;
    }
    _lastSent = tick;
    _sending = true;
    try {
      if (delivery) {
        final code = await backend.publish(
          _sharingOrder!,
          fix,
          deliveryRequestId(),
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
        message.value = code == 'PUBLISHED'
            ? 'Sharing your live location.'
            : 'Waiting for the next fresh GPS fix.';
      } else {
        await backend.idle(fix);
      }
      _failures = 0;
      _retryAt = null;
    } catch (_) {
      if (_valid(generation)) {
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
      final order = _sharingOrder;
      await _cancel();
      _sharingOrder = null;
      message.value = _nativeStopConfirmed
          ? 'Location sharing is off.'
          : 'Sharing stopped. Reopen the app to reset the location service.';
      if (order != null &&
          backend.accountId == _account &&
          _account.isNotEmpty) {
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
    _pendingFix = null;
    sharing.value = false;
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
  }

  bool receive(Map<String, dynamic> data) {
    if (data['order_id'] != order || data['assignment_id'] != assignment) {
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
    stale.value = false;
    return true;
  }

  void checkFreshness() {
    if (_expires != null && elapsed() > _expires!) clear();
  }

  void clear() {
    _expires = null;
    position.value = null;
    stale.value = true;
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
        state.clear();
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
    await _remove();
    state.clear();
  }
}
