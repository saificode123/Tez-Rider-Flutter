import 'dart:async';
import 'dart:math';

typedef PresenceCall =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> parameters,
    );

class PresenceFailure implements Exception {
  const PresenceFailure(this.message, {this.retryable = false});
  final String message;
  final bool retryable;
}

/// A server-issued epoch rejects requests from a previous app session; sequence
/// numbers reject late requests and make retries safe after a lost response.
class RiderPresence {
  RiderPresence(this.call, this.changed, {this.allowTransportRecovery});

  final PresenceCall call;
  final void Function() changed;
  // Opt-in only for a delivery whose live-sharing consent is still active.
  final bool Function()? allowTransportRecovery;
  bool transportInterrupted = false;
  bool online = false;
  bool busy = false;
  bool ready = false;
  String? error;
  int? _epoch;
  int _sequence = 0;
  int _generation = 0;
  bool _closed = false;
  bool _active = true;
  bool _restorePending = false;
  Timer? _heartbeat;
  DateTime? _lastTap;

  Future<Map<String, dynamic>> _request(
    String name,
    Map<String, dynamic> parameters,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await call(name, parameters).timeout(const Duration(seconds: 8));
      } catch (e) {
        if (attempt == 2 || _closed || (e is PresenceFailure && !e.retryable)) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 300 * (1 << attempt)),
        );
      }
    }
  }

  Future<void> restore() async {
    if (_closed) return;
    _active = true;
    if (busy) {
      _restorePending = true;
      return;
    }
    _restorePending = false;
    transportInterrupted = false;
    busy = true;
    ready = false;
    _heartbeat?.cancel();
    changed();
    final generation = _generation;
    try {
      // Do not retry session creation: each call invalidates the preceding epoch.
      final result = await call(
        'fr21_begin_presence',
        {},
      ).timeout(const Duration(seconds: 8));
      _epoch = (result['epoch'] as num).toInt();
      _sequence = 0;
      if (_closed || generation != _generation || !_active) {
        // Background/logout can occur before startup returns its epoch.
        // Release that newly returned lease rather than leaving it online.
        try {
          await _write(false);
        } catch (_) {}
        return;
      }
      online = result['is_online'] == true;
      ready = true;
      error = null;
      _scheduleHeartbeat();
    } catch (e) {
      if (!_closed && generation == _generation) {
        error = e is PresenceFailure
            ? e.message
            : 'Could not restore availability. Tap Retry.';
        online = false;
      }
    } finally {
      busy = false;
      if (!_closed) changed();
      _runPendingRestore();
    }
  }

  Future<void> setOnline(bool value) async {
    final now = DateTime.now();
    if (_closed ||
        !ready ||
        !_active ||
        busy ||
        value == online ||
        (_lastTap != null &&
            now.difference(_lastTap!) < const Duration(milliseconds: 500))) {
      return;
    }
    _lastTap = now;
    busy = true;
    final previous = online;
    final generation = _generation;
    online = value;
    _heartbeat?.cancel();
    changed();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (_closed || generation != _generation) return;
      final result = await _write(value);
      if (_closed || generation != _generation) return;
      online = result['is_online'] == true;
      error = null;
    } catch (e) {
      if (generation == _generation) {
        online = previous;
        ready = false;
        error = e is PresenceFailure
            ? e.message
            : 'Availability was not confirmed. Check your connection and retry.';
      }
    } finally {
      busy = false;
      if (!_closed && generation == _generation) {
        _scheduleHeartbeat();
        changed();
      }
      _runPendingRestore();
    }
  }

  Future<Map<String, dynamic>> _write(bool value) => _request(
    'fr21_set_presence',
    {'p_online': value, 'p_epoch': _epoch, 'p_sequence': ++_sequence},
  );

  void _scheduleHeartbeat() {
    _heartbeat?.cancel();
    if (!online || !ready || !_active || _closed) return;
    // One-shot scheduling prevents overlapping heartbeats; jitter spreads load.
    _heartbeat = Timer(Duration(seconds: 45 + Random().nextInt(11)), _renew);
  }

  void _scheduleRecovery() {
    _heartbeat?.cancel();
    if (_closed || !_active || allowTransportRecovery?.call() != true) {
      transportInterrupted = false;
      return;
    }
    _heartbeat = Timer(const Duration(seconds: 10), _renew);
  }

  Future<void> _renew() async {
    if (transportInterrupted && allowTransportRecovery?.call() != true) {
      transportInterrupted = false;
      changed();
      return;
    }
    if (busy || _closed) {
      if (transportInterrupted) {
        _scheduleRecovery();
      } else {
        _scheduleHeartbeat();
      }
      return;
    }
    busy = true;
    final generation = _generation;
    final recovering = transportInterrupted;
    changed();
    try {
      final result = await _write(true);
      if (!_closed && generation == _generation) {
        if (recovering && allowTransportRecovery?.call() != true) {
          // Consent may be withdrawn while renewal is in flight. A newer
          // offline sequence supersedes that response; never resurrect it.
          online = false;
          ready = false;
          transportInterrupted = false;
          try {
            await _write(false);
          } catch (_) {}
          return;
        }
        online = result['is_online'] == true;
        ready = true;
        transportInterrupted = false;
        error = null;
      }
    } catch (e) {
      if (generation == _generation) {
        online = false;
        ready = false;
        transportInterrupted =
            _active &&
            allowTransportRecovery?.call() == true &&
            (e is! PresenceFailure || e.retryable);
        error = transportInterrupted
            ? 'Connection lost. Delivery sharing will retry after availability is confirmed.'
            : 'Connection lost. Go online again when connected.';
      }
    } finally {
      busy = false;
      if (!_closed && generation == _generation) {
        if (transportInterrupted) {
          _scheduleRecovery();
        } else {
          _scheduleHeartbeat();
        }
        changed();
      }
      _runPendingRestore();
    }
  }

  Future<void> offline() async {
    _active = false;
    transportInterrupted = false;
    _restorePending = false;
    _generation++;
    _heartbeat?.cancel();
    online = false;
    ready = false;
    if (!_closed) changed();
    if (_epoch == null) return;
    try {
      // Higher sequence wins even when an older online request arrives late.
      await _write(false);
    } catch (_) {
      // Abrupt termination/network failure is handled by the server's 2m lease.
    }
  }

  void _runPendingRestore() {
    if (_restorePending && _active && !_closed && !busy) {
      unawaited(restore());
    }
  }

  void dispose() {
    _closed = true;
    _heartbeat?.cancel();
  }
}
