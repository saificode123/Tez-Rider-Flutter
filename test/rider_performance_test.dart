import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/rider_performance_service.dart';
import 'package:flutter_application_1/widgets/rider_performance_panel.dart';

Map<String, dynamic> metrics() => {
  'code': 'OK',
  'rider_id': 20,
  'accepted_assignments': 2,
  'completed_deliveries': 1,
  'timed_deliveries': 1,
  'average_duration_seconds': 120.5,
  'completion_rate': 50,
  'rating_count': 2,
  'average_rating': 4.5,
  'legacy_assignments': 1,
  'unlinked_deliveries': 0,
  'fee_status': 'POLICY_REQUIRED',
  'earned_fee_cents': null,
};
void main() {
  test(
    'owned stored values preserve exact counts, duration and unknown fee',
    () async {
      final service = RiderPerformanceService(
        identity: () => 'a',
        read: () async => metrics(),
      );
      expect(await service.load(), metrics());
    },
  );
  test(
    'invalid counts, impossible rates and fabricated compensation fail closed',
    () async {
      for (final value in [
        {...metrics(), 'completed_deliveries': 3},
        {...metrics(), 'completion_rate': double.nan},
        {...metrics(), 'average_duration_seconds': -1},
        {...metrics(), 'rating_count': 0},
        {...metrics(), 'earned_fee_cents': 100},
        {...metrics(), 'timed_deliveries': 2},
      ]) {
        await expectLater(
          RiderPerformanceService(
            identity: () => 'a',
            read: () async => value,
          ).load(),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'zero history keeps unknown averages instead of fake zero measurements',
    () async {
      final value = {
        ...metrics(),
        'accepted_assignments': 0,
        'completed_deliveries': 0,
        'timed_deliveries': 0,
        'average_duration_seconds': null,
        'completion_rate': null,
        'rating_count': 0,
        'average_rating': null,
      };
      expect(
        await RiderPerformanceService(
          identity: () => 'a',
          read: () async => value,
        ).load(),
        value,
      );
    },
  );
  test(
    'account changed during read cannot expose the old Rider performance',
    () async {
      String? account = 'a';
      final pending = Completer<dynamic>();
      final result = expectLater(
        RiderPerformanceService(
          identity: () => account,
          read: () => pending.future,
        ).load(),
        throwsStateError,
      );
      account = 'b';
      pending.complete(metrics());
      await result;
    },
  );
  testWidgets(
    'actual panel Retry recovers and renders historical limitations without invented wages',
    (t) async {
      var reads = 0;
      final service = RiderPerformanceService(
        identity: () => 'a',
        read: () async {
          if (++reads == 1) throw TimeoutException('injected');
          return metrics();
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RiderPerformancePanel(service: service)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(
        find.text('Completed: 1 / 2 accepted assignments'),
        findsOneWidget,
      );
      expect(find.text('Average delivery time: 2.0 min'), findsOneWidget);
      expect(
        find.textContaining('Unknown times are excluded.'),
        findsOneWidget,
      );
      expect(reads, 2);
      expect(find.textContaining('PKR'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual panel removes rendered data immediately on account change',
    (t) async {
      String? account = 'a';
      final changes = StreamController<void>.broadcast(sync: true);
      final service = RiderPerformanceService(
        identity: () => account,
        accountChanges: changes.stream,
        read: () async => metrics(),
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RiderPerformancePanel(service: service)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Completed: 1'), findsOneWidget);
      account = null;
      changes.add(null);
      await t.pump();
      expect(find.textContaining('Completed: 1'), findsNothing);
      expect(find.textContaining('Account changed.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await changes.close();
    },
  );
}
