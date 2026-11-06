import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/controllers/rider_controller.dart';
import 'package:flutter_application_1/services/rider_earnings_service.dart';
import 'package:flutter_application_1/widgets/rider_earnings_panel.dart';

void main() {
  test(
    'unaccepted Vendor and foreign or terminal work is not offered as ready',
    () {
      expect(
        riderRequestVisible({'order_status': 'placed', 'rider_id': null}, 7),
        isFalse,
      );
      for (final status in ['accepted', 'ready']) {
        expect(
          riderRequestVisible({'order_status': status, 'rider_id': null}, 7),
          isTrue,
        );
        expect(
          riderRequestVisible({'order_status': status, 'rider_id': 8}, 7),
          isFalse,
        );
        expect(
          riderRequestVisible({'order_status': status, 'rider_id': null}, null),
          isFalse,
        );
      }
      for (final status in ['placed', 'accepted', 'ready', 'on_the_way']) {
        expect(
          riderRequestVisible({'order_status': status, 'rider_id': 7}, 7),
          isTrue,
        );
      }
      for (final status in ['delivered', 'cancelled', null]) {
        expect(
          riderRequestVisible({'order_status': status, 'rider_id': 7}, 7),
          isFalse,
        );
      }
      expect(
        riderRequestVisible({
          'order_status': 'on_the_way',
          'rider_id': null,
        }, 7),
        isFalse,
      );
    },
  );
  for (final reason in RiderEarningsUnavailable.reasons.keys) {
    test(
      'quote preserves a confirmed $reason prerequisite without a fake amount',
      () async {
        final service = RiderEarningsService(
          identity: () => 'owner',
          read: (_, __) async => {
            'code': 'DISTANCE_UNAVAILABLE',
            'order_id': 42,
            'reason': reason,
          },
        );
        await expectLater(
          service.quote(42),
          throwsA(
            isA<RiderEarningsUnavailable>().having(
              (e) => e.reason,
              'reason',
              reason,
            ),
          ),
        );
      },
    );
  }
  test('wrong-order or unrecognized unavailable data is rejected', () async {
    for (final value in [
      {
        'code': 'DISTANCE_UNAVAILABLE',
        'order_id': 43,
        'reason': 'PICKUP_LOCATION_REQUIRED',
      },
      {
        'code': 'DISTANCE_UNAVAILABLE',
        'order_id': 42,
        'reason': 'untrusted private server detail',
      },
    ]) {
      await expectLater(
        RiderEarningsService(
          identity: () => 'owner',
          read: (_, __) async => value,
        ).quote(42),
        throwsFormatException,
      );
    }
  });
  testWidgets(
    'missing Vendor pin explains the dependency and retains Retry without an estimate',
    (t) async {
      final service = RiderEarningsService(
        identity: () => 'owner',
        read: (_, __) async => {
          'code': 'DISTANCE_UNAVAILABLE',
          'order_id': 42,
          'reason': 'PICKUP_LOCATION_REQUIRED',
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RiderEarningsPanel(service: service, orderId: 42),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text(
          'Vendor pickup location is missing. Ask the Vendor to confirm it.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Earnings could not be loaded. Please retry.'),
        findsNothing,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('PKR'), findsNothing);
    },
  );
}
