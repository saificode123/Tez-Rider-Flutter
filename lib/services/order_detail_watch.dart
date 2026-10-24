import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef OrderDetailWatcher =
    void Function() Function(int orderId, void Function() changed);

/// Parent/portion rows retain their existing RLS. The private event ledger is
/// never published; every refresh reads the approved owned projection again.
void Function() watchOrderDetail(int orderId, void Function() changed) {
  final client = Supabase.instance.client;
  final account = client.auth.currentUser?.id;
  if (account == null) return () {};
  var disposed = false;
  Timer? timer;
  void schedule() {
    if (disposed) return;
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 250), () {
      if (!disposed) changed();
    });
  }

  final channel = client
      .channel('order-detail:$orderId:${DateTime.now().microsecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: orderId,
        ),
        callback: (_) => schedule(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'vendor_orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'order_id',
          value: orderId,
        ),
        callback: (_) => schedule(),
      )
      .subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) schedule();
      });
  StreamSubscription<AuthState>? auth;
  void dispose() {
    if (disposed) return;
    disposed = true;
    timer?.cancel();
    unawaited(auth?.cancel());
    unawaited(client.removeChannel(channel));
  }

  auth = client.auth.onAuthStateChange.listen((state) {
    if (state.session?.user.id != account) {
      dispose();
      changed();
    } else if (state.event == AuthChangeEvent.tokenRefreshed) {
      schedule();
    }
  });
  return dispose;
}
