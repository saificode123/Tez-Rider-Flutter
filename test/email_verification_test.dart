import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/email_verification.dart';
import 'package:flutter_application_1/screens/email_verification_screen.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'support/closure_harness.dart' show TestPkce;

void main() {
  test('422 email validation is never misreported as an existing account', () {
    expect(
      registrationEmailError(
        '422',
        'synthetic detail',
        code: 'email_address_invalid',
      ),
      'Invalid email address. Please check and try again.',
    );
    expect(
      registrationEmailError('422', 'synthetic detail'),
      'Sign up could not be confirmed. Retry.',
    );
  });
  test(
    'submission failures and duplicate errors stay accurate without raw provider details',
    () {
      expect(
        registrationEmailError(
          '500',
          'Error sending confirmation email: synthetic-private-detail',
        ),
        'Verification email could not be submitted. Contact support before retrying.',
      );
      expect(
        registrationEmailError(
          '422',
          'synthetic detail',
          code: 'user_already_exists',
        ),
        'This email is already registered. Try signing in instead.',
      );
    },
  );
  tearDown(() {
    AuthEmailLink.consume();
    Get.reset();
  });
  test('signup resend uses real SDK type and configured callback', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(pkceAsyncStorage: TestPkce()),
      httpClient: MockClient((request) async {
        calls++;
        expect(request.url.path, '/auth/v1/resend');
        expect(
          request.url.queryParameters['redirect_to'],
          testAuthEmailRedirect,
        );
        final body = jsonDecode(request.body) as Map;
        expect(body['type'], 'signup');
        expect(body['email'], 'owner@example.test');
        expect(body.keys, isNot(contains('password')));
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await EmailVerificationService.resendWith(client, 'owner@example.test');
    expect(calls, 1);
    await client.dispose();
  });
  test('duplicate requests and uncertain outcome retain cooldown', () async {
    final wait = Completer<void>();
    var elapsed = Duration.zero, calls = 0;
    final service = EmailVerificationService(
      send: (_) {
        calls++;
        return wait.future;
      },
      elapsed: () => elapsed,
    );
    final first = service.request('owner@example.test');
    expect(await service.request('owner@example.test'), 'BUSY');
    wait.completeError(TimeoutException('synthetic uncertain submission'));
    expect(await first, 'SEND_UNCONFIRMED');
    expect(await service.request('owner@example.test'), 'COOLDOWN');
    expect(calls, 1);
    elapsed = const Duration(seconds: 61);
    expect(service.remainingSeconds, 0);
  });
  test('initial signup cooldown does not send a second email', () async {
    var calls = 0;
    final service = EmailVerificationService(
      send: (_) async {
        calls++;
      },
      recentlyRequested: true,
    );
    expect(await service.request('owner@example.test'), 'COOLDOWN');
    expect(calls, 0);
  });
  test('invalid email never invokes Auth', () async {
    var calls = 0;
    final service = EmailVerificationService(
      send: (_) async {
        calls++;
      },
    );
    expect(await service.request('invalid'), 'INVALID_EMAIL');
    expect(calls, 0);
  });
  test('provider details never leak and rate limits remain explicit', () async {
    final service = EmailVerificationService(
      send: (_) async => throw const AuthException(
        'synthetic-private-SMTP-detail',
        statusCode: '429',
        code: 'over_email_send_rate_limit',
      ),
    );
    expect(await service.request('owner@example.test'), 'RATE_LIMIT');
    expect(service.remainingSeconds, greaterThan(0));
  });
  for (final uri in [
    'other://login-callback/?code=synthetic',
    'tezrider-fr21-test://wrong/?code=synthetic',
    'tezrider-fr21-test://login-callback:99/?code=synthetic',
    'tezrider-fr21-test://login-callback/?unrelated=synthetic',
  ]) {
    test('untrusted or unrelated callback rejected: $uri', () {
      expect(AuthEmailLink.accept(Uri.parse(uri)), false);
      expect(AuthEmailLink.consume(), false);
    });
  }
  test(
    'success and expired callback signals consumed once; no token returned',
    () {
      expect(
        AuthEmailLink.accept(
          Uri.parse('$testAuthEmailRedirect?code=synthetic'),
        ),
        true,
      );
      expect(AuthEmailLink.consume(), true);
      expect(AuthEmailLink.consume(), false);
      expect(
        AuthEmailLink.accept(
          Uri.parse(
            '$testAuthEmailRedirect#error=access_denied&error_code=otp_expired',
          ),
        ),
        true,
      );
      expect(AuthEmailLink.consume(), true);
    },
  );
  for (final locale in [const Locale('en', 'US'), const Locale('ur', 'PK')]) {
    testWidgets(
      'resend screen shows accurate localized result and countdown: $locale',
      (tester) async {
        Get.testMode = true;
        var calls = 0;
        final service = EmailVerificationService(
          send: (_) async {
            calls++;
          },
        );
        await tester.pumpWidget(
          GetMaterialApp(
            translations: AppTranslations(),
            locale: locale,
            home: EmailVerificationScreen(
              email: 'owner@example.test',
              service: service,
            ),
          ),
        );
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        await tester.pump();
        expect(calls, 1);
        expect(
          find.text(
            'Verification requested. Check your inbox and spam folder. Delivery is not yet confirmed.'
                .tr,
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
