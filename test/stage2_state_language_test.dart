import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/controllers/admin_broadcast_controller.dart';
import 'package:flutter_application_1/controllers/admin_controller.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'package:flutter_application_1/core/stage2_ui_translations.dart';
import 'package:flutter_application_1/screens/admin_broadcasts_screen.dart';
import 'package:flutter_application_1/screens/admin_users_screen.dart';
import 'package:flutter_application_1/screens/customer/dispute_screen.dart';
import 'package:flutter_application_1/services/delivery_otp_service.dart';
import 'admin_broadcast_test.dart' show FakeBroadcastBackend;
import 'admin_users_test.dart' show Backend, WidgetAdmin;

Widget localized(Widget child) => GetMaterialApp(
  locale: const Locale('ur', 'PK'),
  translations: AppTranslations(),
  supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: child,
);

void main() {
  setUp(() {
    Get.testMode = true;
  });
  tearDown(Get.reset);
  test(
    'dispute status translation preserves the original server state code',
    () {
      Get.addTranslations(AppTranslations().keys);
      const status = 'UNDER_REVIEW';
      Get.locale = const Locale('ur', 'PK');
      expect(disputeStatusLabel(status), 'زیر جائزہ');
      expect(status, 'UNDER_REVIEW');
      Get.locale = const Locale('en', 'US');
      expect(disputeStatusLabel(status), 'Under Review');
    },
  );
  test(
    'cached OTP state follows display locale without changing its outcome',
    () {
      Get.addTranslations(AppTranslations().keys);
      final result = {'code': 'INVALID', 'remaining': 3};
      final state = deliveryOtpMessage(result);
      Get.locale = const Locale('ur', 'PK');
      expect(state.uiMessage, 'OTP غلط ہے۔ 3 کوششیں باقی ہیں۔');
      expect(result, {'code': 'INVALID', 'remaining': 3});
      Get.locale = const Locale('en', 'US');
      expect(state.uiMessage, 'Incorrect OTP. 3 attempts remaining.');
      expect(state, 'Incorrect OTP. 3 attempts remaining.');
    },
  );
  test('all six numeric message forms preserve their exact server number', () {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('ur', 'PK');
    const templates = [
      'Incorrect OTP. @slot0end attempts remaining.',
      'Wait @slot0end seconds before requesting another code.',
      'Please wait @slot0end seconds before another broadcast.',
      'Accepted for @slot0end recipients. In-app delivery is available when they connect.',
      'Approximately @slot0end min',
      'Arriving in @slot0end min',
    ];
    for (final template in templates) {
      final english = template.replaceAll('@slot0end', '17');
      expect(
        english.uiMessage,
        stage2UiUrdu[template]!.replaceAll('@slot0end', '17'),
      );
      Get.locale = const Locale('en', 'US');
      expect(english.uiMessage, english);
      Get.locale = const Locale('ur', 'PK');
    }
  });
  test(
    'unknown text and near matches remain literal, with no token evaluation',
    () {
      Get.addTranslations(AppTranslations().keys);
      Get.locale = const Locale('ur', 'PK');
      for (final value in [
        r'@slot0end $name <b>unchanged</b>',
        'Incorrect OTP. @slot0end attempts remaining.',
        'Prefix Incorrect OTP. 3 attempts remaining.',
        'Wait -1 seconds before requesting another code.',
      ]) {
        // An exact known template may translate but never expands its token.
        expect(value.uiMessage, value.tr);
      }
    },
  );
  testWidgets(
    'Urdu broadcast Cancel and Confirm preserve the audience code and literal body',
    (t) async {
      final backend = FakeBroadcastBackend();
      final controller = AdminBroadcastController(backend: backend);
      await t.pumpWidget(
        localized(AdminBroadcastsScreen(controller: controller)),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).at(0), '@slot1end title');
      await t.enterText(
        find.byType(TextFormField).at(1),
        '<b>literal body</b>',
      );
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('گاہک').last);
      await t.pumpAndSettle();
      expect(backend.audiences.last, 'CUSTOMERS');
      await t.ensureVisible(find.text('اعلان کا جائزہ لیں'));
      await t.tap(find.text('اعلان کا جائزہ لیں'));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('@slot1end title')), findsOneWidget);
      await t.tap(find.text('منسوخ کریں'));
      await t.pumpAndSettle();
      expect(backend.calls, 0);
      await t.tap(find.text('اعلان کا جائزہ لیں'));
      await t.pumpAndSettle();
      await t.tap(find.text('بھیجنے کی تصدیق کریں'));
      await t.pumpAndSettle();
      expect(backend.calls, 1);
      expect(backend.requests.single['p_audience'], 'CUSTOMERS');
      expect(backend.requests.single['p_title'], '@slot1end title');
      expect(backend.requests.single['p_message'], '<b>literal body</b>');
      expect(
        find.textContaining('7 وصول کنندگان کے لیے قبول ہوا'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      controller.onClose();
    },
  );
  testWidgets(
    'Urdu account block preserves Cancel and pending Auth enforcement',
    (t) async {
      final backend = Backend()..code = 'AUTH_SYNC_PENDING';
      Get.put<AdminController>(WidgetAdmin(backend));
      await t.pumpWidget(localized(const AdminUsersScreen()));
      await t.pumpAndSettle();
      await t.tap(find.text('بند کریں').first);
      await t.pumpAndSettle();
      await t.tap(find.text('منسوخ کریں'));
      await t.pumpAndSettle();
      expect(backend.requests, isEmpty);
      await t.tap(find.text('بند کریں').first);
      await t.pumpAndSettle();
      await t.tap(find.text('صارف بند کریں'));
      await t.pumpAndSettle();
      expect(backend.requests.length, 1);
      expect(
        find.textContaining('اکاؤنٹ بند رہے گا۔ Auth ہم آہنگی'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
}
