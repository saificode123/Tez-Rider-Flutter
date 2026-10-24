import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/controllers/language_controller.dart';
import 'package:flutter_application_1/screens/customer/profile_screen.dart';
import 'package:flutter_application_1/services/profile_service.dart';

class MemoryPreference implements LanguagePreferenceStore {
  @override
  Future<String?> read() async => 'en';
  @override
  Future<void> write(String value) async {}
}

void main() {
  setUp(() {
    Get.put(
      LanguageController(
        store: MemoryPreference(),
        appReady: () => false,
        applyLocale: (_) async {},
      ),
    );
  });
  tearDown(Get.reset);
  Map<String, dynamic> profile() => {
    'id': 1,
    'name': 'Owner',
    'phone': '1234',
    'email': 'owner@example.test',
    'role': 'rider',
  };
  Future<void> open(WidgetTester t, ProfileService service) async {
    await t.pumpWidget(GetMaterialApp(home: ProfileScreen(service: service)));
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'actual Save calls trusted profile service with edited fields and locks pending controls',
    (t) async {
      final pending = Completer<dynamic>();
      Map<String, dynamic>? sent;
      await open(
        t,
        ProfileService(
          identity: () => 'a',
          read: (_) async => profile(),
          write: (value) {
            sent = value;
            return pending.future;
          },
        ),
      );
      await t.enterText(find.byType(TextField).first, 'Updated Owner');
      await t.tap(find.text('Save'));
      await t.pump();
      expect(sent, {
        'p_name': 'Updated Owner',
        'p_phone': '1234',
        'p_update_profile': true,
      });
      expect(
        t.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse,
      );
      expect(find.text('Profile updated successfully.'), findsNothing);
      pending.complete({'code': 'OK', ...profile(), 'name': 'Updated Owner'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Profile updated successfully.'), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField).first).enabled, isTrue);
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 1));
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'network failure shows Retry without exposing editable unloaded profile',
    (t) async {
      var reads = 0;
      await open(
        t,
        ProfileService(
          identity: () => 'a',
          read: (_) async {
            if (++reads == 1) throw TimeoutException('injected');
            return profile();
          },
        ),
      );
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.text('Retry'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Owner'), findsOneWidget);
      expect(reads, 2);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account switch clears rendered personal details before old save resolves',
    (t) async {
      String? account = 'a';
      final changes = StreamController<void>.broadcast(sync: true),
          pending = Completer<dynamic>();
      await open(
        t,
        ProfileService(
          identity: () => account,
          accountChanges: changes.stream,
          read: (_) async => profile(),
          write: (_) => pending.future,
        ),
      );
      await t.tap(find.text('Save'));
      await t.pump();
      account = 'b';
      changes.add(null);
      await t.pump();
      expect(find.text('owner@example.test'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      pending.complete({'code': 'OK', ...profile()});
      await t.pump();
      expect(find.text('Profile updated successfully.'), findsNothing);
      expect(
        find.text('Account changed. Open your profile again.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await changes.close();
    },
  );
}
