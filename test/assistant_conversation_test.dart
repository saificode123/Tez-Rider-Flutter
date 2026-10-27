import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/ai_service.dart';

void main() {
  test('only six bounded turns are sent; unicode is preserved', () async {
    final service = AIService(
      conversationRequest: (prompt, history) async {
        expect(prompt, 'follow up');
        expect(history.length, 6);
        expect(history.first['content'], '2');
        expect(history.last['content']!.runes.length, 600);
        return {'code': 'OK', 'text': 'Confirmed'};
      },
    );
    final reply = await service.getRecommendation(
      'follow up',
      history: [
        for (var i = 0; i < 7; i++) {'role': 'user', 'content': '$i'},
        {'role': 'assistant', 'content': '🎁' * 1000},
      ],
    );
    expect(reply, 'Confirmed');
  });
  test(
    'provider failure stays a failure and does not expose internals',
    () async {
      final service = AIService(
        conversationRequest: (_, history) async => throw StateError('private'),
      );
      expect(
        await service.getRecommendation('order 42'),
        'The assistant is unavailable. Please try again later.',
      );
    },
  );
}
