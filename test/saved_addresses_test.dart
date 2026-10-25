import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/services/saved_addresses_service.dart';
import 'package:flutter_application_1/screens/customer/saved_addresses_screen.dart';

Map<String, dynamic> row({
  int id = 10,
  String label = 'Home',
  int revision = 0,
}) => {
  'id': id,
  'label': label,
  'address': 'OWNED SYNTHETIC ADDRESS',
  'revision': revision,
};
Map<String, dynamic> page(
  List<Map<String, dynamic>> rows, {
  bool more = false,
}) => {
  'items': rows,
  'has_more': more,
  'cursor': rows.isEmpty ? null : rows.last['id'],
};
Map<String, dynamic> applied(String operation, {String code = 'APPLIED'}) => {
  'code': code,
  'address_id': 10,
  'operation': operation,
  'changed': true,
};
void main() {
  setUp(() => Get.locale = const Locale('en', 'US'));
  tearDown(Get.reset);
  test(
    'lost address create keeps UUID and rejects replacement before retry',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = SavedAddressesService(
        identity: () => 'c',
        rpc: (_, p) async {
          calls.add(p);
          if (calls.length == 1) throw TimeoutException('lost');
          return applied('create', code: 'ALREADY_APPLIED');
        },
      );
      await expectLater(
        service.change(operation: 'create', label: 'Home', address: 'Address'),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        service.change(operation: 'create', label: 'Other', address: 'Address'),
        throwsStateError,
      );
      expect((await service.retry())['code'], 'ALREADY_APPLIED');
      expect(calls.length, 2);
      expect(calls[0], calls[1]);
    },
  );
  test('pending address results cannot cross accounts', () async {
    String? actor = 'a';
    var calls = 0;
    final pending = Completer<dynamic>();
    final service = SavedAddressesService(
      identity: () => actor,
      rpc: (_, p) {
        calls++;
        return pending.future;
      },
    );
    final first = service.change(operation: 'delete', id: 10, revision: 0);
    await expectLater(service.retry(), throwsStateError);
    actor = 'b';
    pending.complete(applied('delete'));
    await expectLater(first, throwsStateError);
    await expectLater(service.retry(), throwsStateError);
    expect(calls, 1);
  });
  test(
    'malformed paging and mismatched address acknowledgement are rejected',
    () async {
      final bad = SavedAddressesService(
        identity: () => 'c',
        rpc: (_, p) async => page([row(id: 10), row(id: 11)]),
      );
      await expectLater(bad.load(), throwsFormatException);
      final service = SavedAddressesService(
        identity: () => 'c',
        rpc: (_, p) async => {...applied('delete'), 'address_id': 11},
      );
      await expectLater(
        service.change(operation: 'delete', id: 10, revision: 0),
        throwsFormatException,
      );
      expect(service.pending, true);
    },
  );
  testWidgets(
    'actual Add and Save wait for backend confirmation then display the new owned row',
    (t) async {
      final pending = Completer<dynamic>();
      Map? sent;
      var saved = false;
      final service = SavedAddressesService(
        identity: () => 'c',
        rpc: (name, p) async {
          if (name == 'final2_saved_addresses') {
            return page(saved ? [row()] : []);
          }
          sent = p;
          final result = await pending.future;
          saved = true;
          return result;
        },
      );
      await t.pumpWidget(
        MaterialApp(home: SavedAddressesScreen(service: service)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.add_rounded));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'Home');
      await t.enterText(find.byType(TextField).last, 'Address');
      await t.ensureVisible(find.text('Save Address'));
      await t.tap(find.text('Save Address'));
      await t.pump();
      expect(sent?['p_operation'], 'create');
      expect(t.widget<TextField>(find.byType(TextField).first).enabled, false);
      pending.complete(applied('create'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('OWNED SYNTHETIC ADDRESS'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual delete Cancel has no effect and Confirm invokes versioned owner mutation',
    (t) async {
      var deleted = false;
      Map? sent;
      final service = SavedAddressesService(
        identity: () => 'c',
        rpc: (name, p) async {
          if (name == 'final2_saved_addresses') {
            return page(deleted ? [] : [row()]);
          }
          sent = p;
          deleted = true;
          return applied('delete');
        },
      );
      await t.pumpWidget(
        MaterialApp(home: SavedAddressesScreen(service: service)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.delete_outline_rounded));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(sent, isNull);
      expect(find.text('Home'), findsOneWidget);
      await t.tap(find.byIcon(Icons.delete_outline_rounded));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(sent?['p_operation'], 'delete');
      expect(sent?['p_id'], 10);
      expect(sent?['p_expected_revision'], 0);
      expect(find.text('Home'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual Edit sends the original revision and reloads only confirmed data',
    (t) async {
      Map? sent;
      var updated = false;
      final service = SavedAddressesService(
        identity: () => 'c',
        rpc: (name, p) async {
          if (name == 'final2_saved_addresses') {
            return page([
              row(label: updated ? 'Work' : 'Home', revision: updated ? 1 : 0),
            ]);
          }
          sent = p;
          updated = true;
          return applied('edit');
        },
      );
      await t.pumpWidget(
        MaterialApp(home: SavedAddressesScreen(service: service)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.edit_outlined));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'Work');
      await t.ensureVisible(find.text('Save Address'));
      await t.tap(find.text('Save Address'));
      await t.pumpAndSettle();
      expect(sent?['p_operation'], 'edit');
      expect(sent?['p_expected_revision'], 0);
      expect(find.text('Work'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'lost delete response exposes actual Retry with unchanged request and no false removal',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      var deleted = false;
      final service = SavedAddressesService(
        identity: () => 'c',
        rpc: (name, p) async {
          if (name == 'final2_saved_addresses') {
            return page(deleted ? [] : [row()]);
          }
          calls.add(p);
          if (calls.length == 1) throw TimeoutException('lost');
          deleted = true;
          return applied('delete', code: 'ALREADY_APPLIED');
        },
      );
      await t.pumpWidget(
        MaterialApp(home: SavedAddressesScreen(service: service)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.delete_outline_rounded));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Retry original change'), findsOneWidget);
      await t.tap(find.text('Retry original change'));
      await t.pumpAndSettle();
      expect(calls[0], calls[1]);
      expect(find.text('Home'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account switch closes private delete confirmation and clears rendered addresses',
    (t) async {
      String? actor = 'a';
      final auth = StreamController<void>.broadcast(sync: true);
      final service = SavedAddressesService(
        identity: () => actor,
        accountChanges: auth.stream,
        rpc: (_, p) async => page([row()]),
      );
      await t.pumpWidget(
        MaterialApp(home: SavedAddressesScreen(service: service)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.delete_outline_rounded));
      await t.pumpAndSettle();
      actor = 'b';
      auth.add(null);
      await t.pumpAndSettle();
      expect(find.text('Delete Address?'), findsNothing);
      expect(find.text('Home'), findsNothing);
      expect(find.text('OWNED SYNTHETIC ADDRESS'), findsNothing);
      expect(
        find.text('Account changed. Open saved addresses again.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await auth.close();
    },
  );
  testWidgets(
    'owned paging loads subsequent rows without replacing the first page',
    (t) async {
      final cursors = <int?>[];
      final service = SavedAddressesService(
        identity: () => 'c',
        rpc: (_, p) async {
          cursors.add(p['p_before']);
          return p['p_before'] == null
              ? page([row()], more: true)
              : page([row(id: 9, label: 'Work')]);
        },
      );
      await t.pumpWidget(
        MaterialApp(home: SavedAddressesScreen(service: service)),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Load more addresses'));
      await t.pumpAndSettle();
      expect(cursors, [null, 10]);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Urdu address controls preserve user data and real RTL', (
    t,
  ) async {
    final service = SavedAddressesService(
      identity: () => 'c',
      rpc: (_, p) async => page([row()]),
    );
    await t.pumpWidget(
      GetMaterialApp(
        locale: const Locale('ur', 'PK'),
        translations: AppTranslations(),
        supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: SavedAddressesScreen(service: service),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('محفوظ پتے'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(
      Directionality.of(t.element(find.text('محفوظ پتے'))),
      TextDirection.rtl,
    );
    await t.pumpWidget(const SizedBox());
  });
}
