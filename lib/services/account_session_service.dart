import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const blockedAccountMessage =
    'Your account has been blocked. Please contact support.';

enum AccountDisposition { allowed, missing, blocked, expired, unavailable }

abstract interface class AccountSessionBackend {
  String? get accountId;
  Future<Map<String, dynamic>> status();
  Future<void> subscribe(int profile, void Function() changed);
  Future<void> unsubscribe();
}

class SupabaseAccountSessionBackend implements AccountSessionBackend {
  SupabaseClient get client => Supabase.instance.client;
  RealtimeChannel? _channel;
  int _subscriptionGeneration = 0;
  @override
  String? get accountId => client.auth.currentUser?.id;
  @override
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
    await client.rpc('fr28_account_status').timeout(const Duration(seconds: 10))
        as Map,
  );
  @override
  Future<void> subscribe(int profile, void Function() changed) async {
    final account = accountId;
    final generation = ++_subscriptionGeneration;
    final previous = _channel;
    _channel = null;
    if (previous != null) await client.removeChannel(previous);
    if (generation != _subscriptionGeneration || account != accountId) return;
    _channel = client
        .channel('account-status-${accountId ?? 'none'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: profile,
          ),
          callback: (_) => changed(),
        )
        .subscribe();
  }

  @override
  Future<void> unsubscribe() async {
    _subscriptionGeneration++;
    final channel = _channel;
    _channel = null;
    if (channel != null) await client.removeChannel(channel);
  }
}

class AccountSessionGate {
  AccountSessionGate(this.backend, this.onDenied);
  final AccountSessionBackend backend;
  final Future<void> Function(AccountDisposition) onDenied;
  Timer? _coalesce;
  String? _account;
  int? _profile;
  bool _closed = false, _checking = false, _again = false;
  int _generation = 0;
  Future<AccountDisposition>? _pending;
  AccountDisposition current = AccountDisposition.unavailable;
  Future<AccountDisposition> check() {
    final pending = _pending;
    if (pending != null && _account == backend.accountId) return pending;
    _account = backend.accountId;
    final work = _check(_account, _generation);
    _pending = work;
    unawaited(
      work.whenComplete(() {
        if (identical(_pending, work)) _pending = null;
      }),
    );
    return work;
  }

  Future<AccountDisposition> _check(String? account, int generation) async {
    if (_closed || account == null) return AccountDisposition.expired;
    try {
      final value = await backend.status();
      if (_closed ||
          generation != _generation ||
          account != backend.accountId) {
        return AccountDisposition.expired;
      }
      current = switch (value['code']) {
        'OK' => AccountDisposition.allowed,
        'PROFILE_MISSING' => AccountDisposition.missing,
        'FR28_ACCOUNT_BLOCKED' => AccountDisposition.blocked,
        'FR28_SESSION_REVOKED' => AccountDisposition.expired,
        _ => AccountDisposition.unavailable,
      };
      if (current == AccountDisposition.blocked ||
          current == AccountDisposition.expired) {
        await backend.unsubscribe();
        if (generation != _generation || account != backend.accountId) {
          return AccountDisposition.expired;
        }
        _profile = null;
        await onDenied(current);
      } else if (current == AccountDisposition.allowed &&
          value['id'] is int &&
          _profile != value['id']) {
        final profile = value['id'] as int;
        await backend.subscribe(profile, _changed);
        if (generation != _generation || _closed) {
          return AccountDisposition.expired;
        }
        _profile = profile;
      }
      return current;
    } catch (_) {
      if (!_closed &&
          generation == _generation &&
          account == backend.accountId) {
        current = AccountDisposition.unavailable;
      }
      return AccountDisposition.unavailable;
    }
  }

  void _changed() {
    _coalesce?.cancel();
    _coalesce = Timer(const Duration(milliseconds: 150), () async {
      if (_closed) return;
      if (_checking) {
        _again = true;
        return;
      }
      _checking = true;
      try {
        do {
          _again = false;
          await check();
        } while (_again && !_closed);
      } finally {
        _checking = false;
      }
    });
  }

  Future<void> reset() async {
    _generation++;
    _pending = null;
    _account = null;
    _profile = null;
    _coalesce?.cancel();
    await backend.unsubscribe();
  }

  Future<void> dispose() async {
    _closed = true;
    await reset();
  }
}

// Only server-issued FR28 codes cause global session action. An arbitrary 403,
// network error or vendor permission denial never signs out a legitimate user.
class AccountHttpClient extends http.BaseClient {
  AccountHttpClient(this.onDenied, {http.Client? inner, this.gatewayBase})
    : _inner = inner ?? http.Client();
  final void Function(String code) onDenied;
  final http.Client _inner;
  final Uri? gatewayBase;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    http.BaseRequest outgoing = request;
    final gateway = gatewayBase;
    if (gateway != null &&
        request.url.origin == gateway.origin &&
        request.url.path.startsWith('/rest/v1/')) {
      final body = await request.finalize().toBytes();
      if (body.length > 900000) throw StateError('Request is too large.');
      const allowed = {
        'accept',
        'content-type',
        'prefer',
        'range',
        'range-unit',
        'accept-profile',
        'content-profile',
      };
      final headers = <String, String>{};
      for (final entry in request.headers.entries) {
        if (allowed.contains(entry.key.toLowerCase()))
          headers[entry.key.toLowerCase()] = entry.value;
      }
      outgoing =
          http.Request(
              'POST',
              gateway.resolve('/functions/v1/security-gateway'),
            )
            ..headers.addAll({
              'Content-Type': 'application/json',
              for (final entry in request.headers.entries)
                if (const {
                  'authorization',
                  'apikey',
                }.contains(entry.key.toLowerCase()))
                  entry.key: entry.value,
            })
            ..body = jsonEncode({
              'method': request.method,
              'path': request.url.path.substring('/rest/v1'.length),
              'query': request.url.query,
              'headers': headers,
              'body': utf8.decode(body),
            });
    }
    final response = await _inner.send(outgoing);
    if (!const [401, 403].contains(response.statusCode)) return response;
    final bytes = await response.stream.toBytes();
    try {
      final body = jsonDecode(utf8.decode(bytes));
      if (body is Map) {
        final code =
            (body['code'] == 'user_banned' &&
                request.url.path.startsWith('/auth/v1/'))
            ? 'FR28_ACCOUNT_BLOCKED'
            : body['message'] == 'FR28_ACCOUNT_BLOCKED'
            ? 'FR28_ACCOUNT_BLOCKED'
            : body['message'] == 'FR28_SESSION_REVOKED'
            ? 'FR28_SESSION_REVOKED'
            : body['code'];
        if (code == 'FR28_ACCOUNT_BLOCKED' || code == 'FR28_SESSION_REVOKED') {
          scheduleMicrotask(() => onDenied(code as String));
        }
      }
    } catch (_) {
      /* Preserve the original response and error category. */
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
