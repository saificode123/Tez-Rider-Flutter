import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/related_favorites_service.dart';
import 'package:flutter_application_1/widgets/related_favorites.dart';

void main() {
  test('lost save is safely retried as the same desired state', () async {
    final calls = <Map<String, dynamic>>[];
    final service = RelatedFavoritesService(
      identity: () => 'customer',
      rpc: (name, params) async {
        calls.add(Map.from(params));
        if (calls.length == 1) throw TimeoutException('lost');
        return {'target_id': 12, 'role': 'vendor', 'saved': true};
      },
    );
    await expectLater(
      service.set(12, 'vendor', true),
      throwsA(isA<TimeoutException>()),
    );
    await service.set(12, 'vendor', true);
    expect(calls[0], calls[1]);
  });
  test('an account switch cannot expose a pending history response', () async {
    String? account = 'a';
    final pending = Completer<dynamic>();
    final service = RelatedFavoritesService(
      identity: () => account,
      rpc: (_, params) => pending.future,
    );
    final result = service.targets(3180);
    account = 'b';
    pending.complete({'items': []});
    await expectLater(result, throwsStateError);
    await expectLater(service.targets(3180), throwsStateError);
  });
  test('unconfirmed or wrong-target mutation receipts are rejected', () async {
    final service = RelatedFavoritesService(
      identity: () => 'a',
      rpc: (_, params) async => {
        'target_id': 13,
        'role': 'vendor',
        'saved': true,
      },
    );
    await expectLater(service.set(12, 'vendor', true), throwsFormatException);
    await expectLater(service.set(12, 'admin', true), throwsFormatException);
  });
  test('duplicate busy mutations do not reach the backend twice', () async {
    var count = 0;
    final pending = Completer<dynamic>();
    final service = RelatedFavoritesService(
      identity: () => 'a',
      rpc: (_, params) {
        count++;
        return pending.future;
      },
    );
    final first = service.set(12, 'vendor', true);
    await expectLater(service.set(12, 'vendor', true), throwsStateError);
    expect(count, 1);
    pending.complete({'target_id': 12, 'role': 'vendor', 'saved': true});
    await first;
  });
  testWidgets(
    'history save waits for confirmation and never reports a failed save',
    (t) async {
      var saved = false, fail = true, writes = 0;
      final service = RelatedFavoritesService(
        identity: () => 'a',
        rpc: (name, params) async {
          if (name == 'final_customer_order_favorite_targets') {
            return {
              'items': [
                {
                  'target_id': 12,
                  'role': 'vendor',
                  'display_name': 'Existing order Vendor',
                  'saved': saved,
                },
              ],
            };
          }
          writes++;
          if (fail) throw TimeoutException('offline');
          saved = params['p_saved'] as bool;
          return {'target_id': 12, 'role': 'vendor', 'saved': saved};
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RelatedFavorites(orderId: 3180, service: service),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Add to Favorites'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(
        find.text(
          'The change was not confirmed. Check your connection and retry.',
        ),
        findsOneWidget,
      );
      fail = false;
      await t.tap(find.byTooltip('Add to Favorites'));
      await t.pumpAndSettle();
      expect(writes, 2);
      expect(find.byTooltip('Remove from Favorites'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    },
  );
}
