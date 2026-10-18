import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/delivery_otp_service.dart';

class Backend implements DeliveryOtpBackend {
  @override
  String accountId = 'account';
  final issues = <String>[], verifications = <String>[];
  Map<String, dynamic> outcome = {'code': 'OK', 'order_status': 'delivered'};
  Map<String, dynamic> issued = {'code': 'EMAIL_ACCEPTED'};
  int failures = 0;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> issue(int order, String request) async {
    issues.add(request);
    return issued;
  }

  @override
  Future<Map<String, dynamic>> status(int order) async => {
    'code': 'EMAIL_ACCEPTED',
    'remaining': 3,
    'retry_after': 60,
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 10))
        .toIso8601String(),
  };
  @override
  Future<Map<String, dynamic>> verify(
    int order,
    String value,
    String request,
  ) async {
    verifications.add(request);
    if (failures-- > 0) throw TimeoutException('unconfirmed');
    return pending?.future ?? Future.value(outcome);
  }
}

void main() {
  test(
    'successful status refresh clears a resolved connection error',
    () async {
      final f = DeliveryOtpFlow(Backend())..begin(1);
      f.result['code'] = 'UNAVAILABLE';
      await f.refresh();
      expect(f.result['code'], 'EMAIL_ACCEPTED');
      expect(f.delivered, false);
    },
  );
  test('status refresh preserves uncertain verification until retry', () async {
    final f = DeliveryOtpFlow(Backend())..begin(1);
    f.result['code'] = 'UNAVAILABLE';
    f.uncertainVerification.value = true;
    await f.refresh();
    expect(f.result['code'], 'UNAVAILABLE');
    expect(f.uncertainVerification.value, true);
    expect(f.delivered, false);
  });
  test('six numeric digits preserve leading zero', () {
    expect(validDeliveryOtp('012345'), true);
    for (final code in ['12345', '1234567', 'ABCDEF', '１２３４５６', ' 01234']) {
      expect(validDeliveryOtp(code), false);
    }
  });
  test('idempotency request is UUID v4 and distinct', () {
    final one = deliveryRequestId();
    expect(
      one,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(deliveryRequestId(), isNot(one));
  });
  test('exact wrong-attempt and locked messages', () {
    expect(
      deliveryOtpMessage({'code': 'INVALID', 'remaining': 2}),
      'Incorrect OTP. 2 attempts remaining.',
    );
    for (final code in ['EXPIRED', 'LOCKED']) {
      expect(
        deliveryOtpMessage({'code': code}),
        'OTP expired. Request a new code.',
      );
    }
  });
  test('all business/error outcomes have meaningful mapping', () {
    for (final code in [
      'NO_OTP',
      'FORBIDDEN',
      'COOLDOWN',
      'ISSUANCE_LIMIT',
      'QUOTA_EXCEEDED',
      'RATE_LIMIT',
      'EMAIL_ACCEPTED',
      'EMAIL_PENDING',
      'EMAIL_UNKNOWN',
      'EMAIL_FAILED',
      'EMAIL_UNAVAILABLE',
      'WRONG_STATE',
      'FORMAT',
      'REQUEST_CONFLICT',
    ]) {
      expect(deliveryOtpMessage({'code': code, 'retry_after': 60}), isNotEmpty);
    }
  });
  test('empty account cannot start workflow', () {
    final b = Backend()..accountId = '';
    expect(DeliveryOtpFlow(b).begin(1), false);
  });
  test('confirmation precedes delivered state', () async {
    final b = Backend()..pending = Completer();
    final f = DeliveryOtpFlow(b)..begin(1);
    final work = f.verify('012345');
    expect(f.busy.value, true);
    expect(f.delivered, false);
    b.pending!.complete({'code': 'OK', 'order_status': 'delivered'});
    expect(await work, true);
    expect(f.delivered, true);
  });
  test('double verify tap cannot dispatch twice', () async {
    final b = Backend()..pending = Completer();
    final f = DeliveryOtpFlow(b)..begin(1);
    final work = f.verify('012345');
    expect(await f.verify('012345'), false);
    expect(b.verifications.length, 1);
    b.pending!.complete({'code': 'OK'});
    await work;
  });
  test('invalid input never reaches backend', () async {
    final b = Backend();
    final f = DeliveryOtpFlow(b)..begin(1);
    expect(await f.verify('abc'), false);
    expect(b.verifications, isEmpty);
    expect(f.result['code'], 'FORMAT');
  });
  test('invalid attempt displays server remaining count', () async {
    final b = Backend()..outcome = {'code': 'INVALID', 'remaining': 1};
    final f = DeliveryOtpFlow(b)..begin(1);
    await f.refresh();
    expect(await f.verify('012345'), false);
    expect(f.status['remaining'], 1);
    expect(f.remainingAttempts, 1);
    expect(f.message, 'Incorrect OTP. 1 attempts remaining.');
  });
  test('expired or locked response deactivates verification', () async {
    for (final code in ['EXPIRED', 'LOCKED', 'NO_OTP']) {
      final b = Backend()..outcome = {'code': code};
      final f = DeliveryOtpFlow(b)..begin(1);
      await f.refresh();
      await f.verify('012345');
      expect(f.active, false);
      expect(f.remainingAttempts, isNull);
    }
  });
  test(
    'expired status never presents a fresh three-attempt allowance',
    () async {
      final f = DeliveryOtpFlow(Backend())..begin(1);
      await f.refresh();
      expect(f.remainingAttempts, 3);
      f.status['expires_at'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      expect(f.remainingAttempts, isNull);
      f.status['code'] = 'EXPIRED';
      f.status['remaining'] = 3;
      expect(f.remainingAttempts, isNull);
    },
  );
  test('already delivered is confirmed idempotent outcome', () async {
    final b = Backend()..outcome = {'code': 'ALREADY_DELIVERED'};
    final f = DeliveryOtpFlow(b)..begin(1);
    expect(await f.verify('012345'), true);
  });
  test('bounded backoff retains same verification request', () async {
    final b = Backend()..failures = 1;
    final f = DeliveryOtpFlow(b)..begin(1);
    expect(await f.verify('012345'), true);
    expect(b.verifications.length, 2);
    expect(b.verifications.toSet().length, 1);
  });
  test('ambiguous exhaustion retains unchanged code/request', () async {
    final b = Backend()..failures = 3;
    final f = DeliveryOtpFlow(b)..begin(1);
    expect(await f.verify('012345'), false);
    expect(f.uncertainVerification.value, true);
    expect(await f.verify('111111'), false);
    expect(b.verifications.length, 3);
    expect(await f.verify('012345'), true);
    expect(b.verifications.toSet().length, 1);
  });
  test('known rejection allows next distinct attempt', () async {
    final b = Backend()..outcome = {'code': 'INVALID', 'remaining': 2};
    final f = DeliveryOtpFlow(b)..begin(1);
    await f.verify('012345');
    await f.verify('111111');
    expect(b.verifications.toSet().length, 2);
  });
  test('email HTTP retry preserves issuance even after acceptance', () async {
    final b = Backend();
    final f = DeliveryOtpFlow(b)..begin(1);
    await f.requestEmail();
    await f.requestEmail();
    expect(b.issues.toSet().length, 1);
  });
  test('explicit resend is blocked by server-derived cooldown', () async {
    final b = Backend();
    final f = DeliveryOtpFlow(b)..begin(1);
    await f.requestEmail();
    await f.requestEmail(newCode: true);
    expect(b.issues.length, 1);
    expect(f.result['code'], 'COOLDOWN');
  });
  test('provider failure never reports delivered or sent success', () async {
    final b = Backend()..issued = {'code': 'EMAIL_UNKNOWN'};
    final f = DeliveryOtpFlow(b)..begin(1);
    await f.requestEmail();
    expect(f.result['code'], 'EMAIL_UNKNOWN');
    expect(f.delivered, false);
  });
  test('account switch ignores late backend confirmation', () async {
    final b = Backend()..pending = Completer();
    final f = DeliveryOtpFlow(b)..begin(1);
    final work = f.verify('012345');
    b.accountId = 'other';
    b.pending!.complete({'code': 'OK'});
    expect(await work, false);
    expect(f.delivered, false);
  });
  test('dispose ignores late backend confirmation', () async {
    final b = Backend()..pending = Completer();
    final f = DeliveryOtpFlow(b)..begin(1);
    final work = f.verify('012345');
    f.dispose();
    b.pending!.complete({'code': 'OK'});
    expect(await work, false);
  });
}
