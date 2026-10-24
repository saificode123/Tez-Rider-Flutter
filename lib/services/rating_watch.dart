import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Only the RLS-protected aggregate is published. Raw feedback and reviewer
/// identities never enter this channel. Reads still use authenticated RPCs.
abstract interface class RatingSubscription {
  bool get isClosed;
  void dispose();
}

typedef RatingWatcher =
    RatingSubscription Function(void Function() changed, {int? targetId});

class RatingWatch implements RatingSubscription {
  RatingWatch(void Function() changed, {int? targetId}) {
    final client = Supabase.instance.client;
    final account = client.auth.currentUser?.id;
    if (account == null) return;
    _channel = client
        .channel('ratings:${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rating_summaries',
          filter: targetId == null
              ? null
              : PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'target_user_id',
                  value: targetId,
                ),
          callback: (_) => _schedule(changed),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) _schedule(changed);
        });
    _auth = client.auth.onAuthStateChange.listen((state) {
      if (state.session?.user.id != account) {
        dispose();
        changed();
      } else if (state.event == AuthChangeEvent.tokenRefreshed) {
        _schedule(changed);
      }
    });
  }
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _auth;
  Timer? _timer;
  bool _closed = false;
  @override
  bool get isClosed => _closed;
  void _schedule(void Function() changed) {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      if (!_closed) changed();
    });
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    unawaited(_auth?.cancel());
    final channel = _channel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
  }
}
