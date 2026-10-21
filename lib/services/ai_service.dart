import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef RecommendationRequest = Future<Map<String, dynamic>> Function(String);

/// Provider credentials and provider calls belong exclusively to the server.
class AIService extends GetxService {
  AIService({RecommendationRequest? request}) : _request = request ?? _invoke;
  final RecommendationRequest _request;

  static Future<Map<String, dynamic>> _invoke(String prompt) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke('shopping-assistant', body: {'prompt': prompt})
          .timeout(const Duration(seconds: 25));
      if (response.status == 429) return {'code': 'RATE_LIMITED'};
      if (response.status != 200 || response.data is! Map) {
        throw StateError('Recommendation unavailable');
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (error) {
      if (error.status == 429) return {'code': 'RATE_LIMITED'};
      rethrow;
    }
  }

  Future<String> getRecommendation(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty || text.runes.length > 2000) {
      return 'Please enter a question of up to 2,000 characters.';
    }
    try {
      final result = await _request(text);
      final reply = result['text'];
      if (result['code'] == 'OK' &&
          reply is String &&
          reply.trim().isNotEmpty) {
        return reply;
      }
      if (result['code'] == 'RATE_LIMITED') {
        return 'Too many requests. Please try again in a minute.';
      }
    } catch (_) {
      // Never display provider errors, credentials, or backend internals.
    }
    return 'The assistant is unavailable. Please try again later.';
  }
}
