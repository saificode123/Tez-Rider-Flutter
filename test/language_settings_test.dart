import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/controllers/language_controller.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/widgets/language_settings_tile.dart';

class PreferenceDouble implements LanguagePreferenceStore {
  String? value;
  int reads = 0;
  bool readFailure = false, writeFailure = false;
  Completer<String?>? pendingRead;
  final writes = <String>[];
  @override
  Future<String?> read() async {
    reads++;
    if (readFailure) throw StateError('injected inaccessible storage');
    return pendingRead?.future ?? value;
  }

  @override
  Future<void> write(String language) async {
    writes.add(language);
    if (writeFailure) throw StateError('injected inaccessible storage');
    value = language;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);
  testWidgets(
    'settings menu changes language without replacing the open route',
    (t) async {
      final store = PreferenceDouble()..value = 'en';
      final language = LanguageController(store: store, appReady: () => false);
      await language.restore();
      await t.pumpWidget(
        GetMaterialApp(
          locale: language.locale,
          supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
          translations: AppTranslations(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Existing profile')),
                      body: LanguageSettingsTile(controller: language),
                    ),
                  ),
                ),
                child: const Text('Open profile'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open profile'));
      await t.pumpAndSettle();
      await t.tap(find.byType(LanguageSettingsTile));
      await t.pumpAndSettle();
      await t.tap(find.text('اردو').last);
      await t.pumpAndSettle();
      expect(store.value, 'ur');
      expect(find.text('Existing profile'), findsOneWidget);
      expect(
        Directionality.of(t.element(find.byType(LanguageSettingsTile))),
        TextDirection.rtl,
      );
      // WidgetTester.pageBack searches for the English tooltip; this route
      // now has the actual Urdu Material tooltip.
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('Open profile'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  LanguageController controller(
    PreferenceDouble store, {
    Future<void> Function(Locale)? apply,
  }) => LanguageController(
    store: store,
    appReady: () => false,
    applyLocale: apply ?? (_) async {},
  );

  test(
    'saved Urdu is restored once before startup without touching an absent navigator',
    () async {
      final store = PreferenceDouble()..value = 'ur';
      var applies = 0;
      final language = controller(
        store,
        apply: (_) async {
          applies++;
        },
      );
      await Future.wait([language.restore(), language.restore()]);
      expect(language.locale, const Locale('ur', 'PK'));
      expect(language.isUrdu, isTrue);
      expect(store.reads, 1);
      expect(applies, 0);
    },
  );
  test(
    'default startup readiness safely handles an absent Get navigator',
    () async {
      final language = LanguageController(
        store: PreferenceDouble()..value = 'ur',
      );
      await language.restore();
      expect(language.isUrdu, isTrue);
      expect(language.persistenceError.value, isNull);
    },
  );
  test(
    'unreadable preference safely falls back to English and exposes restoration failure',
    () async {
      final store = PreferenceDouble()..readFailure = true;
      final language = controller(store);
      await language.restore();
      expect(language.locale, const Locale('en', 'US'));
      expect(language.persistenceError.value, isNotNull);
      expect(store.writes, isEmpty);
    },
  );
  test(
    'unsupported or corrupted stored preference cannot select an arbitrary locale',
    () async {
      for (final value in [null, 'garbage', 'ur_PK', '../../secret']) {
        final language = controller(PreferenceDouble()..value = value);
        await language.restore();
        expect(language.locale, const Locale('en', 'US'));
      }
    },
  );
  test(
    'late preference read never overrides a newer explicit selection',
    () async {
      final store = PreferenceDouble()..pendingRead = Completer<String?>();
      final language = controller(store);
      final restoring = language.restore();
      expect(await language.setEnglish(), isTrue);
      store.pendingRead!.complete('ur');
      await restoring;
      expect(language.locale, const Locale('en', 'US'));
      expect(store.value, 'en');
    },
  );
  test(
    'slow locale application preserves selection order of actual preference writes',
    () async {
      final store = PreferenceDouble();
      final slow = Completer<void>();
      var count = 0;
      final language = controller(
        store,
        apply: (_) {
          count++;
          return count == 1 ? slow.future : Future.value();
        },
      );
      final first = language.setUrdu();
      final last = language.setEnglish();
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, isEmpty);
      slow.complete();
      expect(await first, isTrue);
      expect(await last, isTrue);
      expect(store.writes, ['ur', 'en']);
      expect(store.value, 'en');
      expect(language.isUrdu, isFalse);
    },
  );
  test(
    'failed persistence does not claim saved state and a later change can recover',
    () async {
      final store = PreferenceDouble()..writeFailure = true;
      final language = controller(store);
      expect(await language.setUrdu(), isFalse);
      expect(language.isUrdu, isTrue);
      expect(language.persistenceError.value, isNotNull);
      expect(store.value, isNull);
      store.writeFailure = false;
      expect(await language.setEnglish(), isTrue);
      expect(language.persistenceError.value, isNull);
      expect(store.value, 'en');
    },
  );
  test(
    'failed locale application never persists an unapplied language',
    () async {
      final store = PreferenceDouble();
      final language = controller(
        store,
        apply: (_) async {
          throw StateError('injected locale failure');
        },
      );
      expect(await language.setUrdu(), isFalse);
      expect(language.isUrdu, isFalse);
      expect(store.writes, isEmpty);
      expect(language.persistenceError.value, isNotNull);
    },
  );
  testWidgets('Urdu startup uses real RTL and localized Material actions', (
    t,
  ) async {
    final store = PreferenceDouble()..value = 'ur';
    final language = controller(store);
    await language.restore();
    TextDirection? direction;
    String? cancel;
    await t.pumpWidget(
      GetMaterialApp(
        locale: language.locale,
        fallbackLocale: const Locale('en', 'US'),
        supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
        translations: AppTranslations(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) {
            direction = Directionality.of(context);
            cancel = MaterialLocalizations.of(context).cancelButtonLabel;
            return Scaffold(body: Text('my_orders'.tr));
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(direction, TextDirection.rtl);
    expect(cancel, isNot('Cancel'));
    expect(find.text('میرے آرڈرز'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'actual language toggle persists and switches RTL back to English LTR',
    (t) async {
      final store = PreferenceDouble()..value = 'en';
      final language = LanguageController(store: store, appReady: () => false);
      await language.restore();
      TextDirection? direction;
      Future<bool>? changing;
      await t.pumpWidget(
        GetMaterialApp(
          locale: language.locale,
          supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
          translations: AppTranslations(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) {
              direction = Directionality.of(context);
              return Scaffold(
                body: Column(
                  children: [
                    Text('my_orders'.tr),
                    ElevatedButton(
                      onPressed: () {
                        changing = language.toggle();
                      },
                      child: const Text('Switch language'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(direction, TextDirection.ltr);
      await t.tap(find.text('Switch language'));
      await t.pumpAndSettle();
      await changing;
      expect(direction, TextDirection.rtl);
      expect(store.value, 'ur');
      expect(find.text('میرے آرڈرز'), findsOneWidget);
      await t.tap(find.text('Switch language'));
      await t.pumpAndSettle();
      await changing;
      expect(direction, TextDirection.ltr);
      expect(store.value, 'en');
      expect(find.text('My Orders'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
}
