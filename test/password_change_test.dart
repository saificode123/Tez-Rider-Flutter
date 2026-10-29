import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/services/password_change.dart';
import 'package:flutter_application_1/screens/password_change_screen.dart';
import 'package:flutter_application_1/core/app_translations.dart';

void main() {
  tearDown(Get.reset);
  for (final locale in [const Locale('en', 'US'), const Locale('ur', 'PK')]) {
    testWidgets(
      'new password stays obscured and clears after confirmed Auth update: $locale',
      (tester) async {
        Get.testMode = true;
        final service = PasswordChangeService(
          identity: () => 'synthetic-owner',
          verify: () async => 'synthetic-owner',
          update: (_) async => 'synthetic-owner',
        );
        await tester.pumpWidget(
          GetMaterialApp(
            translations: AppTranslations(),
            locale: locale,
            home: PasswordChangeScreen(service: service),
          ),
        );
        final fields = tester
            .widgetList<TextField>(find.byType(TextField))
            .toList();
        expect(fields.length, 2);
        expect(
          fields.every(
            (field) =>
                field.obscureText &&
                field.autocorrect == false &&
                !field.enableSuggestions,
          ),
          true,
        );
        for (final field in fields) {
          field.controller!.text = 'Synthetic-New-Value-123!';
        }
        await tester.ensureVisible(find.text('Update password'.tr));
        await tester.tap(find.text('Update password'.tr));
        await tester.pumpAndSettle();
        expect(fields.every((field) => field.controller!.text.isEmpty), true);
        expect(find.text('Sign out all sessions'.tr), findsOneWidget);
        expect(find.text('Synthetic-New-Value-123!'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  test(
    'another account cannot inherit an already open password form',
    () async {
      String? account = 'synthetic-owner';
      var updates = 0;
      final service = PasswordChangeService(
        identity: () => account,
        verify: () async => account,
        update: (_) async {
          updates++;
          return account;
        },
      );
      account = 'synthetic-other';
      expect(
        await service.change(
          'Synthetic-New-Value-123!',
          'Synthetic-New-Value-123!',
        ),
        'ACCOUNT_CHANGED',
      );
      expect(updates, 0);
    },
  );
  test(
    'update requires live same account and matching strong new fields',
    () async {
      var updates = 0;
      final service = PasswordChangeService(
        identity: () => 'synthetic-owner',
        verify: () async => 'synthetic-owner',
        update: (value) async {
          updates++;
          expect(value.length, greaterThanOrEqualTo(12));
          return 'synthetic-owner';
        },
      );
      expect(await service.change('short', 'short'), 'WEAK_PASSWORD');
      expect(
        await service.change('Synthetic-New-Value-123!', 'different'),
        'MISMATCH',
      );
      expect(updates, 0);
      expect(
        await service.change(
          'Synthetic-New-Value-123!',
          'Synthetic-New-Value-123!',
        ),
        'UPDATED',
      );
      expect(updates, 1);
    },
  );
  test(
    'account switch during verification never submits a new password',
    () async {
      String? account = 'synthetic-owner';
      var updates = 0;
      final service = PasswordChangeService(
        identity: () => account,
        verify: () async {
          account = null;
          return 'synthetic-owner';
        },
        update: (_) async {
          updates++;
          return null;
        },
      );
      expect(
        await service.change(
          'Synthetic-New-Value-123!',
          'Synthetic-New-Value-123!',
        ),
        'ACCOUNT_CHANGED',
      );
      expect(updates, 0);
    },
  );
  test('duplicate password updates are rejected while awaiting Auth', () async {
    final wait = Completer<String?>();
    final service = PasswordChangeService(
      identity: () => 'synthetic-owner',
      verify: () async => 'synthetic-owner',
      update: (_) => wait.future,
    );
    final first = service.change(
      'Synthetic-New-Value-123!',
      'Synthetic-New-Value-123!',
    );
    expect(
      await service.change(
        'Synthetic-New-Value-123!',
        'Synthetic-New-Value-123!',
      ),
      'BUSY',
    );
    wait.complete('synthetic-owner');
    expect(await first, 'UPDATED');
  });
  test('provider errors never expose secrets or claim success', () async {
    final service = PasswordChangeService(
      identity: () => 'synthetic-owner',
      verify: () async => 'synthetic-owner',
      update: (_) async =>
          throw StateError('synthetic-provider-private-detail'),
    );
    expect(
      await service.change(
        'Synthetic-New-Value-123!',
        'Synthetic-New-Value-123!',
      ),
      'UNCONFIRMED',
    );
    expect(service.busy, false);
  });
}
