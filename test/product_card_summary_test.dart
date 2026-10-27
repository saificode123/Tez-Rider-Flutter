import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/widgets/product_card_summary.dart';

void main() {
  for (final direction in TextDirection.values) {
    for (final width in [124.0, 156.0, 320.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('product summary $direction width=$width scale=$scale', (
          t,
        ) async {
          var taps = 0;
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Directionality(
                  textDirection: direction,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: ProductCardSummary(
                          price: direction == TextDirection.rtl
                              ? 'روپے 123456.75'
                              : 'Rs.123456.75',
                          rating: '4.9',
                          reviewCount: 12345,
                          favourite: false,
                          favouriteLabel: 'Favourite',
                          onFavourite: () => taps++,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(t.takeException(), isNull);
          expect(find.text('(12345)'), findsOneWidget);
          await t.tap(find.byType(IconButton));
          expect(taps, 1);
          expect(
            t.getSize(find.byType(IconButton)).height,
            greaterThanOrEqualTo(48),
          );
        });
      }
    }
  }
}
