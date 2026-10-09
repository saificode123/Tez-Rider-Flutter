import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AIService extends GetxService {
  String? _apiKey;
  final _supabase = Supabase.instance.client;

  Future<void> _loadApiKey() async {
    if (_apiKey != null) return;
    try {
      final response = await _supabase
          .from('app_settings')
          .select('setting_value')
          .eq('setting_key', 'groq_api_key')
          .maybeSingle();

      if (response != null && response['setting_value'] != null) {
        _apiKey = response['setting_value'];
      }
    } catch (e) {
      debugPrint('Failed to fetch API key from DB: $e');
    }
  }

  Future<String> getRecommendation(String prompt) async {
    await _loadApiKey();

    if (_apiKey == null || _apiKey!.isEmpty) {
      return "⚠️ The AI is currently unavailable. (Admin: Please add your Groq API Key to the 'app_settings' table in Supabase).";
    }

    try {
      final systemPrompt = """
You are TezRider's brilliant AI Shopping Assistant.
The app offers: Gifts delivery, Flower bouquets, Cakes, and Home Tailoring.
Your job is to recommend combinations of products based on occasions or user requests.
For example, if they ask for a birthday gift, suggest a specific cake flavor and a matching flower bouquet.
Be extremely friendly, very concise (keep it short), and use emojis and bullet points.
""";

      final res = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'openai/gpt-oss-120b',
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final text = data['choices']?[0]?['message']?['content'] as String?;
        return text ?? "I'm having trouble thinking of a recommendation right now.";
      } else {
        debugPrint('Groq API error ${res.statusCode}: ${res.body}');
        return "Sorry, I lost connection to the AI engine. Please try again.";
      }
    } catch (e) {
      debugPrint('Groq API exception: $e');
      return "Sorry, I lost connection to the AI engine. Please try again.";
    }
  }
}