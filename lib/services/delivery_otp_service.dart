import 'dart:async';
import 'dart:math';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String deliveryRequestId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

bool validDeliveryOtp(String value) => RegExp(r'^[0-9]{6}$').hasMatch(value);
String deliveryOtpMessage(
  Map<String, dynamic> result,
) => switch (result['code']) {
  'OK' || 'ALREADY_DELIVERED' => 'Your order has been delivered.',
  'INVALID' => 'Incorrect OTP. ${result['remaining']} attempts remaining.',
  'LOCKED' || 'EXPIRED' => 'OTP expired. Request a new code.',
  'NO_OTP' => 'Request a delivery code first.',
  'FORBIDDEN' => 'Only the assigned approved rider can verify this delivery.',
  'COOLDOWN' =>
    'Wait ${result['retry_after'] ?? 60} seconds before requesting another code.',
  'ISSUANCE_LIMIT' =>
    'The five-code limit for this order has been reached. Contact Admin.',
  'QUOTA_EXCEEDED' =>
    'Daily email limit reached. Contact Admin; no email was sent.',
  'RATE_LIMIT' => 'Too many requests. Wait and retry.',
  'EMAIL_ACCEPTED' =>
    'Email request accepted. Ask the customer to check their inbox and spam folder.',
  'EMAIL_PENDING' =>
    'Email request is pending. Retry this request to check its outcome.',
  'EMAIL_UNKNOWN' =>
    'Email outcome is unconfirmed. Retry this request; it will not send twice.',
  'EMAIL_FAILED' =>
    'Email provider rejected the request. A previous unexpired code remains usable.',
  'ADMIN_UNAVAILABLE' =>
    'Admin review routing is unavailable. Contact support.',
  'EMAIL_UNAVAILABLE' =>
    'The customer needs a confirmed registered email. Contact Admin.',
  'WRONG_STATE' => 'This order is not eligible for delivery verification.',
  'CHECKLIST_REQUIRED' =>
    'Complete and submit the pickup checklist, then start delivery before confirming the OTP.',
  'FORMAT' => 'Enter exactly six numeric digits.',
  'REQUEST_CONFLICT' =>
    'Retry the unchanged verification before entering a different code.',
  _ => 'The operation was not confirmed. Check your connection and Retry.',
};

abstract class DeliveryOtpBackend {
  String get accountId;
  Future<Map<String, dynamic>> issue(int order, String request);
  Future<Map<String, dynamic>> status(int order);
  Future<Map<String, dynamic>> verify(int order, String value, String request);
}

class SupabaseDeliveryOtpBackend implements DeliveryOtpBackend {
  SupabaseClient get client => Supabase.instance.client;
  @override
  String get accountId => client.auth.currentUser?.id ?? '';
  @override
  Future<Map<String, dynamic>> issue(int order, String request) async {
    try {
      final response = await client.functions
          .invoke(
            'send-delivery-otp',
            body: {'order_id': order, 'request_id': request},
          )
          .timeout(const Duration(seconds: 50));
      if (response.data is! Map) {
        throw StateError('Unconfirmed');
      }
      return Map<String, dynamic>.from(response.data);
    } on FunctionException catch (e) {
      if (e.details is Map && (e.details as Map)['code'] is String) {
        return Map<String, dynamic>.from(e.details);
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> status(int order) async =>
      Map<String, dynamic>.from(
        await client
            .rpc('delivery_otp_status', params: {'p_order_id': order})
            .timeout(const Duration(seconds: 15)),
      );
  @override
  Future<Map<String, dynamic>> verify(
    int order,
    String value,
    String request,
  ) async => Map<String, dynamic>.from(
    await client
        .rpc(
          'verify_delivery_otp',
          params: {
            'p_order_id': order,
            'p_otp': value,
            'p_request_id': request,
          },
        )
        .timeout(const Duration(seconds: 15)),
  );
}

class DeliveryOtpFlow {
  DeliveryOtpFlow(this.backend);
  final DeliveryOtpBackend backend;
  final busy = false.obs, uncertainVerification = false.obs;
  final result = <String, dynamic>{}.obs, status = <String, dynamic>{}.obs;
  int? orderId;
  String? _account, _issueId, _verifyId, _verifyValue;
  DateTime? cooldownUntil;
  int _generation = 0;
  bool _closed = false;
  String get message => deliveryOtpMessage(result);
  bool get delivered =>
      const ['OK', 'ALREADY_DELIVERED'].contains(result['code']);
  bool get active =>
      status['code'] == 'EMAIL_ACCEPTED' &&
      (DateTime.tryParse(
            status['expires_at']?.toString() ?? '',
          )?.isAfter(DateTime.now().toUtc()) ??
          false);
  int? get remainingAttempts {
    final remaining = status['remaining'];
    return active && remaining is int && remaining >= 0 && remaining <= 3
        ? remaining
        : null;
  }

  int get cooldownSeconds => max(
    0,
    (cooldownUntil?.difference(DateTime.now()).inMilliseconds ?? 0).ceil() ~/
            1000 +
        ((cooldownUntil?.isAfter(DateTime.now()) ?? false) ? 1 : 0),
  );
  bool begin(int order) {
    if (_closed || busy.value || backend.accountId.isEmpty) {
      return false;
    }
    if (orderId != order || _account != backend.accountId) {
      _generation++;
      orderId = order;
      _account = backend.accountId;
      _issueId = null;
      _verifyId = null;
      _verifyValue = null;
      uncertainVerification.value = false;
      cooldownUntil = null;
      result.clear();
      status.clear();
    }
    return true;
  }

  bool _valid(int generation) =>
      !_closed && generation == _generation && _account == backend.accountId;
  void _status(Map<String, dynamic> value) {
    status.assignAll(value);
    final seconds = (value['retry_after'] as num?)?.ceil() ?? 0;
    cooldownUntil = DateTime.now().add(Duration(seconds: seconds));
  }

  Future<void> refresh() async {
    if (_closed || busy.value || orderId == null) return;
    busy.value = true;
    final generation = _generation;
    try {
      final value = await backend.status(orderId!);
      if (_valid(generation)) {
        _status(value);
        if (result.isEmpty ||
            (result['code'] == 'UNAVAILABLE' && !uncertainVerification.value)) {
          result.assignAll(value);
        }
      }
    } catch (_) {
      if (_valid(generation)) result.assignAll({'code': 'UNAVAILABLE'});
    } finally {
      if (!_closed) busy.value = false;
    }
  }

  Future<void> requestEmail({bool newCode = false}) async {
    if (_closed || busy.value || orderId == null) return;
    if (newCode && cooldownSeconds > 0) {
      result.assignAll({'code': 'COOLDOWN', 'retry_after': cooldownSeconds});
      return;
    }
    busy.value = true;
    final generation = _generation;
    if (newCode) _issueId = null;
    _issueId ??= deliveryRequestId();
    try {
      final value = await _retry(() => backend.issue(orderId!, _issueId!));
      if (!_valid(generation)) return;
      result.assignAll(value);
      // Keep the request ID even after acceptance; only explicit Resend creates a new issuance.
      try {
        final safe = await backend.status(orderId!);
        if (_valid(generation)) _status(safe);
      } catch (_) {
        /* Preserve actual issuance outcome; status remains unconfirmed. */
      }
    } catch (_) {
      if (_valid(generation)) result.assignAll({'code': 'UNAVAILABLE'});
    } finally {
      if (!_closed) busy.value = false;
    }
  }

  Future<bool> verify(String value) async {
    if (_closed || busy.value || orderId == null) return false;
    if (!validDeliveryOtp(value)) {
      result.assignAll({'code': 'FORMAT'});
      return false;
    }
    if (_verifyId != null && _verifyValue != value) {
      result.assignAll({'code': 'REQUEST_CONFLICT'});
      return false;
    }
    busy.value = true;
    final generation = _generation;
    _verifyId ??= deliveryRequestId();
    _verifyValue = value;
    try {
      final outcome = await _retry(
        () => backend.verify(orderId!, value, _verifyId!),
      );
      if (!_valid(generation)) return false;
      result.assignAll(outcome);
      if (outcome['code'] == 'UNAVAILABLE') {
        uncertainVerification.value = true;
        return false;
      }
      _verifyId = null;
      _verifyValue = null;
      uncertainVerification.value = false;
      if (outcome['remaining'] is num) {
        status['remaining'] = outcome['remaining'];
      }
      if (const ['LOCKED', 'EXPIRED', 'NO_OTP'].contains(outcome['code'])) {
        status['code'] = outcome['code'];
      }
      return delivered;
    } catch (_) {
      if (_valid(generation)) {
        uncertainVerification.value = true;
        result.assignAll({'code': 'UNAVAILABLE'});
      }
      return false;
    } finally {
      if (!_closed) busy.value = false;
    }
  }

  Future<T> _retry<T>(Future<T> Function() work) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await work();
      } catch (error) {
        if (_closed ||
            attempt >= 2 ||
            (error is PostgrestException && error.code == '42501')) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 400 * (1 << attempt)),
        );
        if (_closed || _account != backend.accountId) {
          throw StateError('Session changed');
        }
      }
    }
  }

  void dispose() {
    _closed = true;
    _generation++;
    _verifyValue = null;
  }
}
