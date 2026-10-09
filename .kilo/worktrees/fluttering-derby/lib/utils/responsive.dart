import 'package:flutter/material.dart';

/// App-wide responsive sizing helper.
/// Design baseline: 390 × 844 px (iPhone 14).
class R {
  R._();

  static double _w(BuildContext c) =>
      MediaQuery.sizeOf(c).width.clamp(280.0, 1440.0);
  static double _h(BuildContext c) =>
      MediaQuery.sizeOf(c).height.clamp(500.0, 1200.0);

  /// Scale a horizontal pixel value from the 390 px baseline.
  static double w(BuildContext c, double px) =>
      (_w(c) / 390.0 * px).clamp(px * 0.75, px * 1.5);

  /// Scale a vertical pixel value from the 844 px baseline.
  static double h(BuildContext c, double px) =>
      (_h(c) / 844.0 * px).clamp(px * 0.75, px * 1.5);

  /// Scale a font size (stays between 85 – 115 % of base).
  static double sp(BuildContext c, double size) =>
      (_w(c) / 390.0 * size).clamp(size * 0.85, size * 1.15);

  static bool isMobile(BuildContext c)  => _w(c) < 600;
  static bool isTablet(BuildContext c)  => _w(c) >= 600 && _w(c) < 900;
  static bool isDesktop(BuildContext c) => _w(c) >= 900;

  /// Grid cross-axis count that fits the screen.
  static int gridColumns(BuildContext c) {
    if (_w(c) >= 900) return 4;
    if (_w(c) >= 600) return 3;
    return 2;
  }

  /// Page-level horizontal padding.
  static double pagePadding(BuildContext c) =>
      isDesktop(c) ? 48.0 : isTablet(c) ? 32.0 : 20.0;

  static Size size(BuildContext c) => MediaQuery.sizeOf(c);
}
