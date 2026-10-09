import 'dart:async';
import 'dart:math';

typedef PresenceCall =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> parameters,
    );

/// A server-issued epoch rejects requests from a previous app session; sequence
/// numbers reject late requests and make retries safe after a lost response.
class RiderPresence {
  RiderPresence(this.call, this.changed);

  final PresenceCall call;
  final void Function() changed;
  bool online = false;
  bool busy = false;
  bool ready = false;
  String? error;
  int? _epoch;
  int _sequence = 0;
  int _generation = 0;
  bool _closed = false;
  Timer? _heartbeat;
  DateTime? _lastTap;

  Future<Map<String, dynamic>> _request(
    String name,
    Map<String, dynamic> parameters,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await call(name, parameters).timeout(const Duration(seconds: 8));
      } catch (_) {
        if (attempt == 2 || _closed) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 300 * (1 << attempt)),
        );
      }
    }
  }

  Future<void> restore() async {
    if (busy || _closed) return;
    busy = true;
    changed();
    final generation = _generation;
    try {
      // Do not retry session creation: each call invalidates the preceding epoch.
      final result = await call(
        'fr21_begin_presence',
        {},
      ).timeout(const Duration(seconds: 8));
      if (_closed || generation != _generation) return;
      _epoch = (result['epoch'] as num).toInt();
      _sequence = 0;
      online = result['is_online'] == true;
      ready = true;
      error = null;
      _scheduleHeartbeat();
    } catch (_) {
      error = 'Could not restore availability. Tap Retry.';
      online = false;
    } finally {
      busy = false;
      if (!_closed) changed();
    }
  }

  Future<void> setOnline(bool value) async {
    final now = DateTime.now();
    if (_closed ||
        !ready ||
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
    } catch (_) {
      if (generation == _generation) {
        online = previous;
        error =
            'Availability was not confirmed. Check your connection and retry.';
      }
    } finally {
      busy = false;
      if (!_closed && generation == _generation) {
        _scheduleHeartbeat();
        changed();
      }
    }
  }

  Future<Map<String, dynamic>> _write(bool value) => _request(
    'fr21_set_presence',
    {'p_online': value, 'p_epoch': _epoch, 'p_sequence': ++_sequence},
  );

  void _scheduleHeartbeat() {
    _heartbeat?.cancel();
    if (!online || _closed) return;
    // One-shot scheduling prevents overlapping heartbeats; jitter spreads load.
    _heartbeat = Timer(Duration(seconds: 45 + Random().nextInt(11)), () async {
      if (busy || _closed) {
        _scheduleHeartbeat();
        return;
      }
      busy = true;
      final generation = _generation;
      changed();
      try {
        final result = await _write(true);
        if (!_closed && generation == _generation) {
          online = result['is_online'] == true;
          error = null;
        }
      } catch (_) {
        if (generation == _generation) {
          online = false;
          error = 'Connection lost. Go online again when connected.';
        }
      } finally {
        busy = false;
        if (!_closed && generation == _generation) {
          _scheduleHeartbeat();
          changed();
        }
      }
    });
  }

  Future<void> offline() async {
    _generation++;
    _heartbeat?.cancel();
    online = false;
    if (!_closed) changed();
    if (_epoch == null) return;
    try {
      // Higher sequence wins even when an older online request arrives late.
      await _write(false);
    } catch (_) {
      // Abrupt termination/network failure is handled by the server's 2m lease.
    }
  }

  void dispose() {
    _closed = true;
    _heartbeat?.cancel();
  }
}
