import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;

typedef FeedbackRpc =
    Future<dynamic> Function(String name, Map<String, dynamic> parameters);

class FeedbackService {
  FeedbackService({
    FeedbackRpc? rpc,
    String? Function()? identity,
    Stream<void>? accountChanges,
  }) : _rpc =
           rpc ??
           ((name, params) => Supabase.instance.client
               .rpc(name, params: params)
               .timeout(const Duration(seconds: 15))),
       accountChanges =
           accountChanges ??
           (identity != null
               ? const Stream<void>.empty()
               : Supabase.instance.client.auth.onAuthStateChange.map((_) {})),
       _identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id);
  final FeedbackRpc _rpc;
  final String? Function() _identity;
  String? get account => _identity();
  final Stream<void> accountChanges;
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> params,
  ) async {
    final account = _identity();
    if (account == null) throw StateError('Sign in to view feedback.');
    final value = await _rpc(name, params);
    if (_identity() != account) {
      throw StateError('Account changed. Open feedback again.');
    }
    if (value is! Map) {
      throw const FormatException('Feedback was not confirmed.');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<List<Map<String, dynamic>>> context(int orderId) async {
    final value = await call('final2_feedback_context', {
      'p_order_id': orderId,
    });
    if (value['code'] != 'OK' ||
        value['order_id'] != orderId ||
        value['targets'] is! List) {
      throw const FormatException('Delivery feedback was not confirmed.');
    }
    final ids = <int>{};
    return (value['targets'] as List).map((row) {
      if (row is! Map ||
          row['target_id'] is! int ||
          row['target_id'] <= 0 ||
          !ids.add(row['target_id']) ||
          !['vendor', 'rider'].contains(row['role']) ||
          row['name'] is! String) {
        throw const FormatException('Feedback recipient was not confirmed.');
      }
      final review = row['review'];
      if (review != null &&
          (review is! Map || !validRating(review['rating']))) {
        throw const FormatException('Saved feedback was not confirmed.');
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  static bool validRating(dynamic value) =>
      value is int && value >= 1 && value <= 5;

  Future<Map<String, dynamic>> summary(int targetId) async {
    final value = await call('final2_rating_summary', {
      'p_target_id': targetId,
    });
    final count = value['count'];
    final average = value['average'];
    if (value['code'] != 'OK' ||
        value['target_id'] != targetId ||
        !['vendor', 'rider'].contains(value['role']) ||
        count is! int ||
        count < 0 ||
        (count == 0
            ? average != null
            : average is! num ||
                  !average.isFinite ||
                  average < 1 ||
                  average > 5) ||
        value['recent'] is! List ||
        (value['recent'] as List).length > 10) {
      throw const FormatException('Rating summary was not confirmed.');
    }
    for (final row in value['recent']) {
      if (row is! Map ||
          !validRating(row['rating']) ||
          row['created_at'] is! String ||
          (row['comment'] != null && row['comment'] is! String)) {
        throw const FormatException('Rating history was not confirmed.');
      }
    }
    return value;
  }
}

/// Retries preserve the exact request while its outcome is uncertain.
class FeedbackSubmission {
  FeedbackSubmission(this.service, this.orderId, this.targetId);
  final FeedbackService service;
  final int orderId, targetId;
  bool busy = false;
  Map<String, dynamic>? _pending;
  String? _account;
  bool get uncertain => _pending != null;
  Future<Map<String, dynamic>> submit(int rating, String comment) async {
    if (busy) throw StateError('Feedback is being submitted.');
    if (service.account == null) throw StateError('Sign in required.');
    if (_account != null && service.account != _account) {
      throw StateError('Account changed. Open feedback again.');
    }
    if (_pending == null) {
      if (!FeedbackService.validRating(rating) || comment.length > 2000) {
        throw const FormatException(
          'Choose 1–5 stars and at most 2000 characters.',
        );
      }
      _pending = {
        'p_order_id': orderId,
        'p_target_id': targetId,
        'p_rating': rating,
        'p_comment': comment.trim(),
        'p_request_id': blockRequestId(),
      };
      _account = service.account;
    }
    busy = true;
    try {
      final result = await service.call(
        'final2_submit_feedback',
        Map.of(_pending!),
      );
      if (![
            'SUBMITTED',
            'ALREADY_APPLIED',
            'ALREADY_REVIEWED',
          ].contains(result['code']) ||
          result['order_id'] != orderId ||
          result['target_id'] != targetId ||
          result['id'] is! String ||
          !FeedbackService.validRating(result['rating'])) {
        throw const FormatException(
          'Feedback result was not confirmed. Retry the same request.',
        );
      }
      _pending = null;
      return result;
    } on PostgrestException catch (error) {
      if (['22023', '42501', 'PT409'].contains(error.code)) _pending = null;
      rethrow;
    } finally {
      busy = false;
    }
  }
}
