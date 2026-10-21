import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/ai_service.dart';
import 'package:flutter_application_1/screens/payment_screen.dart';
import 'package:flutter_application_1/widgets/role_access_gate.dart';

void main() {
  test('each role is admitted only to its own approved dashboard', () {
    for (final role in ['customer', 'vendor', 'rider', 'admin']) {
      final status = <String, dynamic>{
        'code': 'OK',
        'role': role,
        'verification_status': 'approved',
        'is_blocked': false,
      };
      for (final target in ['customer', 'vendor', 'rider', 'admin']) {
        expect(roleAccessAllowed(status, target), role == target);
      }
      expect(
        roleAccessAllowed({...status, 'code': 'FR28_ACCOUNT_BLOCKED'}, role),
        false,
      );
      expect(roleAccessAllowed({...status, 'is_blocked': true}, role), false);
      expect(
        roleAccessAllowed({...status, 'code': 'FR28_SESSION_REVOKED'}, role),
        false,
      );
      expect(
        roleAccessAllowed({...status, 'verification_status': 'pending'}, role),
        role == 'customer',
      );
    }
    expect(roleAccessAllowed({}, 'admin'), false);
    expect(
      roleAccessAllowed({'code': 'OK', 'role': 'invalid'}, 'admin'),
      false,
    );
  });
  test(
    'AI client only returns confirmed server content and private error text',
    () async {
      final service = AIService(
        request: (_) async => {'code': 'OK', 'text': 'Confirmed reply'},
      );
      expect(await service.getRecommendation('Question'), 'Confirmed reply');
      final failure = AIService(
        request: (_) async => throw StateError('private backend content'),
      );
      final text = await failure.getRecommendation('Question');
      expect(text, contains('unavailable'));
      expect(text, isNot(contains('private backend content')));
      final unavailable = AIService(
        request: (_) async => {'code': 'UNAVAILABLE', 'text': 'invented reply'},
      );
      expect(
        await unavailable.getRecommendation('Question'),
        isNot(contains('invented reply')),
      );
    },
  );
  test(
    'invalid AI input never leaves client; rate denial is truthful',
    () async {
      var calls = 0;
      final service = AIService(
        request: (_) async {
          calls++;
          return {'code': 'RATE_LIMITED'};
        },
      );
      await service.getRecommendation('');
      await service.getRecommendation('a' * 2001);
      expect(calls, 0);
      expect(
        await service.getRecommendation('Question'),
        contains('Too many requests'),
      );
      expect(calls, 1);
    },
  );
  testWidgets(
    'unconfigured payment never collects cards or calls paid callback',
    (tester) async {
      var captured = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentScreen(amount: 100, onPaymentSuccess: () => captured++),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('No payment has been taken'), findsOneWidget);
      await tester.tap(find.text('Return to checkout'));
      await tester.pump(const Duration(seconds: 3));
      expect(captured, 0);
    },
  );
}
