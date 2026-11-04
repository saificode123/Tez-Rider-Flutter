import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/spatial_surface.dart';

void main() {
  for (final rtl in [false, true]) {
    testWidgets(
      'spatial surfaces fit 320px at 200% text ${rtl ? "RTL" : "LTR"}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          SpatialPageHeader(
                            title: rtl
                                ? 'آپ کے آرڈرز'
                                : 'Your delivery overview',
                            subtitle: rtl
                                ? 'اپنے آرڈر کی تفصیل دیکھیں'
                                : 'Track existing order details',
                            icon: Icons.delivery_dining,
                          ),
                          const SpatialSectionHeading(
                            title: 'Order details',
                            subtitle: 'Confirmed information',
                          ),
                          const SpatialSurface(
                            child: SpatialStatusBadge(
                              label: 'Awaiting confirmation',
                              icon: Icons.schedule,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  bottomNavigationBar: SpatialBottomBar(
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('Existing action'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Existing action'));
        expect(taps, 1);
      },
    );
  }
  test('action and secondary text tokens retain readable contrast', () {
    double contrast(Color a, Color b) {
      final one = a.computeLuminance(), two = b.computeLuminance();
      return (one > two ? one + .05 : two + .05) /
          (one > two ? two + .05 : one + .05);
    }

    expect(
      contrast(AppColors.primary, Colors.white),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(AppColors.primary, AppColors.bgLight),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(AppColors.primaryDark, AppColors.primarySurface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(AppColors.textSecondary, AppColors.bgLight),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(AppColors.textPrimary, AppColors.coral),
      greaterThanOrEqualTo(4.5),
    );
  });
}
