import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/onboarding_service.dart';
import 'package:flutter_application_1/widgets/account_review_dialog.dart';

void main() {
  const vendor = RegistrationData(
    name: 'Unit Vendor',
    phone: '+92 300 1234567',
    role: 'vendor',
    storeName: 'Unit store',
    storeAddress: 'Unit street, city',
  );
  test(
    'registration metadata preserves store details through email verification without CNIC or credentials',
    () {
      expect(vendor.error, isNull);
      final restored = OnboardingService.fromMetadata(vendor.metadata);
      expect(restored.parameters, vendor.parameters);
      expect(vendor.metadata.keys, isNot(contains('password')));
      expect(vendor.metadata.keys, isNot(contains('cnic')));
      expect(vendor.parameters.keys, isNot(contains('auth_user_id')));
    },
  );
  for (final data in [
    const RegistrationData(name: 'Owner', phone: '1234', role: 'admin'),
    const RegistrationData(name: ' ', phone: '1234', role: 'customer'),
    const RegistrationData(name: 'Owner', phone: '---', role: 'customer'),
    const RegistrationData(
      name: 'Owner',
      phone: 'secret@example.test',
      role: 'vendor',
    ),
    const RegistrationData(
      name: 'Owner',
      phone: '1234',
      role: 'vendor',
      storeName: 'Store',
    ),
    const RegistrationData(
      name: 'Owner',
      phone: '1234',
      role: 'vendor',
      storeName: 'Store',
      storeAddress: '\u0000city',
    ),
  ]) {
    test(
      'invalid registration input rejected in UI: ${data.role}/${data.name}/${data.phone}/${data.storeAddress}',
      () {
        expect(data.error, isNotNull);
      },
    );
  }
  test(
    'new vendor details reach one confirmed RPC; canonical role/status come from backend',
    () async {
      final sent = <Map<String, dynamic>>[];
      final service = OnboardingService(
        call: (params) async {
          sent.add(params);
          return {
            'code': 'OK',
            'id': 10,
            'role': 'vendor',
            'verification_status': 'pending',
            'store_id': 20,
          };
        },
      );
      final result = await service.complete(vendor);
      expect(sent, [vendor.parameters]);
      expect(result['verification_status'], 'pending');
    },
  );
  for (final code in ['PROFILE_REQUIRED', 'STORE_REQUIRED']) {
    test(
      '$code is recoverable incompletion, never a saved-store success',
      () async {
        final service = OnboardingService(
          call: (_) async => {'code': code, 'role': 'vendor'},
        );
        await expectLater(
          service.complete(vendor),
          throwsA(
            isA<RegistrationRequired>().having((x) => x.code, 'code', code),
          ),
        );
      },
    );
  }
  for (final response in [
    null,
    [],
    {'code': 'OK'},
    {'code': 'OK', 'id': 1, 'role': 'vendor', 'verification_status': 'pending'},
    {
      'code': 'OK',
      'id': 1,
      'role': 'vendor',
      'verification_status': 'invented',
      'store_id': 2,
    },
  ]) {
    test(
      'unconfirmed registration response never succeeds: $response',
      () async {
        final service = OnboardingService(call: (_) async => response);
        await expectLater(service.complete(vendor), throwsStateError);
      },
    );
  }
  test(
    'network failure remains a failure and retry uses identical registration identity fields',
    () async {
      final sent = <Map<String, dynamic>>[];
      var count = 0;
      final service = OnboardingService(
        call: (params) async {
          sent.add(params);
          if (count++ == 0) throw TimeoutException('injected');
          return {
            'code': 'OK',
            'id': 10,
            'role': 'vendor',
            'verification_status': 'pending',
            'store_id': 20,
          };
        },
      );
      await expectLater(
        service.complete(vendor),
        throwsA(isA<TimeoutException>()),
      );
      await service.complete(vendor);
      expect(sent.length, 2);
      expect(sent[0], sent[1]);
    },
  );
  test(
    'only an explicit profile completion marks saved name/phone for update',
    () async {
      Map<String, dynamic>? sent;
      final service = OnboardingService(
        call: (params) async {
          sent = params;
          return {
            'code': 'OK',
            'id': 10,
            'role': 'vendor',
            'verification_status': 'pending',
            'store_id': 20,
          };
        },
      );
      await service.complete(vendor);
      expect(sent!['p_update_profile'], isFalse);
      await service.complete(vendor, updateProfile: true);
      expect(sent!['p_update_profile'], isTrue);
      expect(sent!.containsKey('auth_user_id'), isFalse);
    },
  );
  test(
    'malformed editable metadata cannot select an Admin registration role',
    () {
      final data = OnboardingService.fromMetadata({
        'role': 'admin',
        'name': [],
        'phone': {},
      });
      expect(data.role, 'customer');
      expect(data.name, isEmpty);
      expect(data.phone, isEmpty);
    },
  );
  for (final approved in [false, true]) {
    testWidgets('review Cancel changes nothing: approved=$approved', (
      tester,
    ) async {
      String? outcome;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  outcome = await showDialog<String>(
                    context: context,
                    builder: (_) => AccountReviewDialog(
                      approved: approved,
                      requireReason: !approved,
                    ),
                  );
                  completed = true;
                },
                child: const Text('Review'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(outcome, isNull);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'reasoned vendor rejection cannot confirm empty text; returns trimmed reason after confirmation',
    (tester) async {
      String? outcome;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  outcome = await showDialog<String>(
                    context: context,
                    builder: (_) => const AccountReviewDialog(
                      approved: false,
                      requireReason: true,
                    ),
                  );
                },
                child: const Text('Review'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a rejection reason (one line, up to 500 characters).'),
        findsOneWidget,
      );
      expect(outcome, isNull);
      await tester.enterText(
        find.byType(TextField),
        '  Missing store details  ',
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(outcome, 'Missing store details');
      expect(tester.takeException(), isNull);
    },
  );
}
