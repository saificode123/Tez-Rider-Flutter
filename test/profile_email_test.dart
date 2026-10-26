import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/services/profile_email_service.dart';
import 'package:flutter_application_1/widgets/profile_email_panel.dart';

Map<String, dynamic> emailState({
  String account = 'a',
  String email = 'original@example.test',
  String? pending,
}) => {
  'code': 'OK',
  'account': account,
  'email': email,
  'pending_email': pending,
  'verified': true,
};
User owner() => const User(
  id: 'a',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-26T00:00:00Z',
  email: 'original@example.test',
);

void main() {
  tearDown(Get.reset);
  test(
    'request acceptance preserves original email and represents only pending Auth confirmation',
    () async {
      String? sent;
      final service = ProfileEmailService(
        identity: () => 'a',
        read: () async =>
            emailState(pending: sent == null ? null : 'next@example.test'),
        request: (email) async {
          sent = email;
          return owner();
        },
      );
      final result = await service.request('next@example.test');
      expect(sent, 'next@example.test');
      expect(result.email, 'original@example.test');
      expect(result.pendingEmail, 'next@example.test');
    },
  );
  test(
    'server-confirmed canonical email is required before reporting confirmed change',
    () async {
      var requested = false;
      final service = ProfileEmailService(
        identity: () => 'a',
        read: () async => emailState(
          email: requested ? 'next@example.test' : 'original@example.test',
        ),
        request: (_) async {
          requested = true;
          return owner();
        },
      );
      expect(
        (await service.request('next@example.test')).email,
        'next@example.test',
      );
      await expectLater(
        ProfileEmailService(
          identity: () => 'a',
          read: () async => emailState(),
          request: (_) async => owner(),
        ).request('next@example.test'),
        throwsFormatException,
      );
    },
  );
  test(
    'invalid target and duplicate pending submission do not issue extra Auth calls',
    () async {
      var calls = 0;
      final pending = Completer<User?>();
      final service = ProfileEmailService(
        identity: () => 'a',
        read: () async =>
            emailState(pending: calls == 0 ? null : 'next@example.test'),
        request: (_) {
          calls++;
          return pending.future;
        },
      );
      await expectLater(service.request('bad email'), throwsFormatException);
      expect(calls, 0);
      final first = service.request('next@example.test');
      await expectLater(service.request('next@example.test'), throwsStateError);
      expect(calls, 1);
      pending.complete(owner());
      await first;
    },
  );
  test(
    'already pending same target is recovered without resending an Auth email request',
    () async {
      var calls = 0;
      final service = ProfileEmailService(
        identity: () => 'a',
        read: () async => emailState(pending: 'next@example.test'),
        request: (_) async {
          calls++;
          return owner();
        },
      );
      expect(
        (await service.request('next@example.test')).pendingEmail,
        'next@example.test',
      );
      expect(calls, 0);
      await expectLater(
        service.request('different@example.test'),
        throwsStateError,
      );
      expect(calls, 0);
    },
  );
  test(
    'wrong account and unverified/mismatched canonical status fail closed',
    () async {
      for (final value in [
        {...emailState(), 'account': 'b'},
        {...emailState(), 'verified': false},
        {...emailState(), 'code': 'PROFILE_SYNC_REQUIRED'},
        {...emailState(), 'pending_email': 'malformed'},
      ]) {
        await expectLater(
          ProfileEmailService(
            identity: () => 'a',
            read: () async => value,
          ).load(),
          throwsFormatException,
        );
      }
      var account = 'a';
      final pending = Completer<User?>();
      final service = ProfileEmailService(
        identity: () => account,
        read: () async => emailState(pending: 'next@example.test'),
        request: (_) => pending.future,
      );
      final denied = expectLater(
        service.request('next@example.test'),
        throwsStateError,
      );
      account = 'b';
      pending.complete(owner());
      await denied;
    },
  );

  Future<void> show(
    WidgetTester tester,
    ProfileEmailService service, {
    ValueChanged<String>? confirmed,
    bool urdu = false,
  }) async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: Locale(urdu ? 'ur' : 'en', urdu ? 'PK' : 'US'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileEmailPanel(service: service, onConfirmed: confirmed),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'next@example.test');
    await tester.tap(find.text('Request email change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request change'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Cancel never sends email and pending acceptance never shows confirmed success',
    (tester) async {
      var calls = 0;
      String? pending;
      final service = ProfileEmailService(
        identity: () => 'a',
        read: () async => emailState(pending: pending),
        request: (email) async {
          calls++;
          pending = email;
          return owner();
        },
      );
      await show(tester, service);
      await tester.enterText(find.byType(TextField), 'next@example.test');
      await tester.tap(find.text('Request email change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await submit(tester);
      expect(calls, 1);
      expect(find.text('original@example.test'), findsOneWidget);
      expect(find.text('Awaiting Auth confirmation'), findsOneWidget);
      expect(
        find.textContaining(
          'Email delivery and the change are not yet confirmed.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Confirmed email change is now saved to your profile.'),
        findsNothing,
      );
    },
  );
  testWidgets(
    'Check status detects actual confirmation and updates only canonical email',
    (tester) async {
      var confirmed = false;
      String? callback;
      final service = ProfileEmailService(
        identity: () => 'a',
        read: () async => confirmed
            ? emailState(email: 'next@example.test')
            : emailState(pending: 'next@example.test'),
      );
      await show(tester, service, confirmed: (email) => callback = email);
      expect(callback, 'original@example.test');
      confirmed = true;
      await tester.tap(find.text('Check email status'));
      await tester.pumpAndSettle();
      expect(callback, 'next@example.test');
      expect(
        find.text('Confirmed email change is now saved to your profile.'),
        findsOneWidget,
      );
      expect(find.text('original@example.test'), findsNothing);
    },
  );
  testWidgets(
    'uncertain request requires a fresh status check before any retry',
    (tester) async {
      var calls = 0;
      final service = ProfileEmailService(
        identity: () => 'a',
        read: () async => emailState(),
        request: (_) async {
          calls++;
          throw TimeoutException('offline');
        },
      );
      await show(tester, service);
      await submit(tester);
      expect(calls, 1);
      expect(
        find.text(
          'Email change was not confirmed. Check email status before retrying.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.tap(find.text('Check email status'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    },
  );
  testWidgets(
    'account switch immediately clears pending address and ignores late response',
    (tester) async {
      String? account = 'a';
      final changes = StreamController<void>.broadcast(sync: true);
      final service = ProfileEmailService(
        identity: () => account,
        accountChanges: changes.stream,
        read: () async => emailState(pending: 'next@example.test'),
      );
      await show(tester, service);
      expect(find.text('next@example.test'), findsOneWidget);
      account = 'b';
      changes.add(null);
      await tester.pump();
      expect(find.text('next@example.test'), findsNothing);
      expect(find.text('original@example.test'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await changes.close();
    },
  );
  testWidgets(
    'Urdu email controls remain readable on narrow large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await show(
        tester,
        ProfileEmailService(
          identity: () => 'a',
          read: () async => emailState(),
        ),
        urdu: true,
      );
      expect(find.text('سائن اِن ای میل'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
