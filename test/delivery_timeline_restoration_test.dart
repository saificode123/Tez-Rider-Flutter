import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/widgets/order_timeline.dart';
import 'package:lottie/lottie.dart';

Widget timeline(List<Map<String, dynamic>> events, {bool animate = true}) =>
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: SingleChildScrollView(
            child: OrderTimeline(
              currentStep: 0,
              events: events,
              showDeliveryAnimation: animate,
            ),
          ),
        ),
      ),
    );

Map<String, dynamic> event(String status, int minute) => {
  'status': status,
  'created_at': '2026-11-04T10:${minute.toString().padLeft(2, '0')}:00Z',
};

void main() {
  testWidgets(
    'confirmed moving order restores bundled cyclist with reduced motion',
    (tester) async {
      await tester.pumpWidget(timeline([event('on_the_way', 1)]));
      await tester.pumpAndSettle();
      final asset = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
      expect(asset.animate, isFalse);
      expect(asset.repeat, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a Vendor pickup reservation cannot animate a moving Rider', (
    tester,
  ) async {
    await tester.pumpWidget(timeline([event('on_the_way', 1)], animate: false));
    expect(find.byType(LottieBuilder), findsNothing);
    expect(find.text('on the way'), findsOneWidget);
  });

  testWidgets(
    'delivered backend event stops animation without hiding evidence',
    (tester) async {
      await tester.pumpWidget(
        timeline([event('on_the_way', 1), event('delivered', 2)]),
      );
      expect(find.byType(LottieBuilder), findsNothing);
      expect(find.text('delivered'), findsOneWidget);
      expect(find.text('on the way'), findsOneWidget);
    },
  );

  testWidgets(
    'cancellation stops animation even when events arrive unordered',
    (tester) async {
      await tester.pumpWidget(
        timeline([event('cancelled', 3), event('on_the_way', 1)]),
      );
      expect(find.byType(LottieBuilder), findsNothing);
      expect(find.text('cancelled'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing lifecycle events never infer delivered or start animation',
    (tester) async {
      await tester.pumpWidget(timeline([]));
      expect(find.byType(LottieBuilder), findsNothing);
      expect(find.text('Delivered'), findsNothing);
    },
  );
}
