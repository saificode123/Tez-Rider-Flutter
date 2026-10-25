import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/store_settings_service.dart';
import 'package:flutter_application_1/screens/vendor/store_settings_screen.dart';

Map<String, dynamic> store({String name = 'Original', int version = 0}) => {
  'store_id': 10,
  'store_name': name,
  'address': 'Owned address',
  'latitude': null,
  'longitude': null,
  'is_active': false,
  'version': version,
};
void main() {
  setUp(() => Get.locale = const Locale('en', 'US'));
  tearDown(Get.reset);
  testWidgets(
    'actual Urdu settings labels and confirmation retain owned values',
    (t) async {
      final service = StoreSettingsService(
        identity: () => 'v',
        rpc: (name, params) async => name == 'final2_store_settings'
            ? store()
            : {'code': 'SAVED', 'store': store()},
      );
      await t.pumpWidget(
        GetMaterialApp(
          locale: const Locale('ur', 'PK'),
          translations: AppTranslations(),
          supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: StoreSettingsPanel(service: service),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('دکان کی ترتیبات'), findsOneWidget);
      expect(find.text('دکان کا نام'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      expect(
        Directionality.of(t.element(find.byType(TextField).first)),
        TextDirection.rtl,
      );
      await t.tap(find.text('دکان کی معلومات محفوظ کریں'));
      await t.pumpAndSettle();
      expect(find.text('دکان کی معلومات محفوظ ہو گئیں۔'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      Get.reset();
    },
  );
  test(
    'uncertain store save reuses immutable UUID and rejects changed retry',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = StoreSettingsService(
        identity: () => 'v',
        rpc: (_, p) async {
          calls.add(p);
          if (calls.length == 1) throw TimeoutException('network');
          return {
            'code': 'ALREADY_APPLIED',
            'store': store(name: 'Edited', version: 1),
          };
        },
      );
      Future<Map<String, dynamic>> save(String name) =>
          service.save(version: 0, name: name, address: 'Owned address');
      await expectLater(save('Edited'), throwsA(isA<TimeoutException>()));
      await expectLater(save('Different'), throwsStateError);
      expect(calls.length, 1);
      expect((await save('Edited'))['code'], 'ALREADY_APPLIED');
      expect(calls[0], calls[1]);
      expect(service.pending, false);
    },
  );
  test('store save cannot cross account or duplicate a busy request', () async {
    String? actor = 'a';
    final pending = Completer<dynamic>();
    var calls = 0;
    final service = StoreSettingsService(
      identity: () => actor,
      rpc: (_, p) {
        calls++;
        return pending.future;
      },
    );
    final first = service.save(version: 0, name: 'Edited', address: 'Address');
    await expectLater(
      service.save(version: 0, name: 'Edited', address: 'Address'),
      throwsStateError,
    );
    actor = 'b';
    pending.complete({'code': 'SAVED', 'store': store()});
    await expectLater(first, throwsStateError);
    await expectLater(
      service.save(version: 0, name: 'Edited', address: 'Address'),
      throwsStateError,
    );
    expect(calls, 1);
  });
  test(
    'validation bounds and server conflict permit explicit reload',
    () async {
      var calls = 0;
      final service = StoreSettingsService(
        identity: () => 'v',
        rpc: (name, p) async {
          calls++;
          if (name == 'final2_save_store_settings') {
            throw const PostgrestException(message: 'conflict', code: 'PT409');
          }
          return store(version: 2);
        },
      );
      await expectLater(
        service.save(version: 0, name: '', address: 'Address'),
        throwsFormatException,
      );
      await expectLater(
        service.save(
          version: 0,
          name: 'Store',
          address: 'Address',
          lat: double.nan,
          lng: 0,
        ),
        throwsFormatException,
      );
      expect(calls, 0);
      await expectLater(
        service.save(version: 0, name: 'Store', address: 'Address'),
        throwsA(isA<PostgrestException>()),
      );
      expect(service.pending, false);
      expect((await service.load())['version'], 2);
    },
  );
  testWidgets(
    'actual store Save locks controls and confirms server returned values',
    (t) async {
      final pending = Completer<dynamic>();
      Map? sent;
      final service = StoreSettingsService(
        identity: () => 'v',
        rpc: (name, p) async {
          if (name == 'final2_store_settings') return store();
          sent = p;
          return pending.future;
        },
      );
      await t.pumpWidget(
        MaterialApp(home: StoreSettingsPanel(service: service)),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'Edited');
      await t.tap(find.text('Save store details'));
      await t.pump();
      expect(sent?['p_name'], 'Edited');
      expect(t.widget<TextField>(find.byType(TextField).first).enabled, false);
      expect(find.text('Store details saved.'), findsNothing);
      pending.complete({
        'code': 'SAVED',
        'store': store(name: 'Edited', version: 1),
      });
      await t.pumpAndSettle();
      expect(find.text('Store details saved.'), findsOneWidget);
      expect(find.text('Store inactive'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual unchanged retry and location denial never show false success',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      final service = StoreSettingsService(
        identity: () => 'v',
        rpc: (name, p) async {
          if (name == 'final2_store_settings') return store();
          calls.add(p);
          if (calls.length == 1) throw TimeoutException('offline');
          return {'code': 'ALREADY_APPLIED', 'store': store()};
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: StoreSettingsPanel(
            service: service,
            locate: () async => throw StateError('permission denied'),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Use my current pickup location'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Pickup location unavailable.'),
        findsOneWidget,
      );
      expect(find.text('Pickup location not set.'), findsOneWidget);
      await t.tap(find.text('Save store details'));
      await t.pumpAndSettle();
      expect(find.text('Store details saved.'), findsNothing);
      expect(find.text('Retry original save'), findsOneWidget);
      await t.tap(find.text('Retry original save'));
      await t.pumpAndSettle();
      expect(calls[0], calls[1]);
      expect(
        find.text('Original save confirmed. Current store details loaded.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('explicit current pickup fix is sent only on actual Save', (
    t,
  ) async {
    Map? sent;
    final service = StoreSettingsService(
      identity: () => 'v',
      rpc: (name, p) async {
        if (name == 'final2_store_settings') return store();
        sent = p;
        return {
          'code': 'SAVED',
          'store': {...store(version: 1), 'latitude': 12.25, 'longitude': 34.5},
        };
      },
    );
    await t.pumpWidget(
      MaterialApp(
        home: StoreSettingsPanel(
          service: service,
          locate: () async => (lat: 12.25, lng: 34.5),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Use my current pickup location'));
    await t.pumpAndSettle();
    expect(sent, isNull);
    await t.tap(find.text('Save store details'));
    await t.pumpAndSettle();
    expect(sent?['p_latitude'], 12.25);
    expect(sent?['p_longitude'], 34.5);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'account switch clears fields and ignores pending save response',
    (t) async {
      String? account = 'a';
      final auth = StreamController<void>.broadcast(sync: true);
      final pending = Completer<dynamic>();
      final service = StoreSettingsService(
        identity: () => account,
        accountChanges: auth.stream,
        rpc: (name, p) async =>
            name == 'final2_store_settings' ? store() : pending.future,
      );
      await t.pumpWidget(
        MaterialApp(home: StoreSettingsPanel(service: service)),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Save store details'));
      await t.pump();
      account = 'b';
      auth.add(null);
      await t.pump();
      expect(find.text('Owned address'), findsNothing);
      expect(
        find.text('Account changed. Open store settings again.'),
        findsOneWidget,
      );
      pending.complete({
        'code': 'SAVED',
        'store': store(name: 'Other account'),
      });
      await t.pumpAndSettle();
      expect(find.text('Other account'), findsNothing);
      expect(find.text('Store details saved.'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await auth.close();
    },
  );
  testWidgets('loading failure recovers only through actual Reload', (t) async {
    var calls = 0;
    final service = StoreSettingsService(
      identity: () => 'v',
      rpc: (_, p) async {
        if (++calls == 1) throw TimeoutException('offline');
        return store();
      },
    );
    await t.pumpWidget(MaterialApp(home: StoreSettingsPanel(service: service)));
    await t.pumpAndSettle();
    expect(
      find.text('Store details unavailable. Retry loading.'),
      findsOneWidget,
    );
    await t.tap(find.text('Reload store details'));
    await t.pumpAndSettle();
    expect(find.text('Original'), findsOneWidget);
    expect(calls, 2);
    await t.pumpWidget(const SizedBox());
  });
}
