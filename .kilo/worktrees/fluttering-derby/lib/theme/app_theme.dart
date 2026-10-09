import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// ============================================================
/// DESIGN SYSTEM — TezRider
/// Modern, premium delivery-marketplace visual language.
/// This file is purely visual (colors/type/spacing/component
/// themes) — no business logic, API, or auth code lives here.
/// ============================================================

class AppColors {
  // ---- Brand ----
  // A cleaner, slightly more vibrant forest green than before —
  // reads as "fresh/organic" (food+grocery) without going neon.
  static const primary        = Color(0xFF16803C);
  static const primaryDark    = Color(0xFF0B4D24);
  static const primaryLight   = Color(0xFF2FA85A);
  static const primarySurface = Color(0xFFE7F5EC);

  // Warm accent for CTAs/highlights — matches reference marketplace apps.
  static const accent        = Color(0xFFFF7A1A);
  static const accentLight   = Color(0xFFFFA35C);
  static const accentSurface = Color(0xFFFFF1E6);

  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const error   = Color(0xFFE0342A);
  static const info    = Color(0xFF2563EB);

  // Clean neutral background instead of a heavy cream tint —
  // reads as more "premium marketplace", less "handmade".
  static const bgLight    = Color(0xFFF7F8FA);
  static const bgCard     = Color(0xFFFFFFFF);
  static const bgSection  = Color(0xFFF1F4F2);

  // Neutral charcoal text instead of the old navy/purple tint —
  // more professional, higher legibility on white cards.
  static const textPrimary    = Color(0xFF14181B);
  static const textSecondary  = Color(0xFF667085);
  static const textHint       = Color(0xFFA0A8B4);
  static const divider        = Color(0xFFE7EAEE);

  static const bgDark        = Color(0xFF0B1410);
  static const bgCardDark    = Color(0xFF141F19);
  static const bgSectionDark = Color(0xFF1B2C22);
  static const textPrimaryDark   = Color(0xFFF3F6F4);
  static const textSecondaryDark = Color(0xFFA6B3AC);
  static const dividerDark   = Color(0xFF263329);

  // ---- Category accents ----
  static const catFood      = Color(0xFFE8715A);
  static const catGrocery   = Color(0xFF0D9488);
  static const catPharmacy  = Color(0xFFEAB308);
  static const catThrift    = Color(0xFFEC4899);
  static const catTailoring = Color(0xFF8B5CF6);
  static const catElectronics = Color(0xFF2563EB);
  static const catGifts     = Color(0xFFDB2777);

  // ---- Role identity colors ----
  static const roleCustomer       = Color(0xFFE91E63);
  static const roleCustomerAccent = Color(0xFFF06292);
  static const roleCustomerSoft   = Color(0xFFFFB199);

  static const roleVendor       = Color(0xFFFF7A00);
  static const roleVendorAccent = Color(0xFFFFB347);
  static const roleVendorSoft   = Color(0xFFFFE0B2);

  static const roleRider       = Color(0xFF7B2FF7);
  static const roleRiderAccent = Color(0xFF5C6CFF);
  static const roleRiderSoft   = Color(0xFFD9C6FF);

  static const roleAdmin = Color(0xFF2563EB);

  static final List<Color> gradientPrimary = [primary, primaryLight];
  static final List<Color> gradientDark    = [primaryDark, primary];
  static final List<Color> gradientSuccess = [success, const Color(0xFF059669)];
  static final List<Color> gradientAccent  = [accent, accentLight];

  static final List<Color> customerGradient = [roleCustomer, roleCustomerAccent, roleCustomerSoft];
  static final List<Color> vendorGradient   = [roleVendor, roleVendorAccent, roleVendorSoft];
  static final List<Color> riderGradient    = [roleRider, roleRiderAccent, roleRiderSoft];

  static const headerText = Color(0xFFFFFFFF);
  static final Color headerGlass = Colors.white.withValues(alpha: 0.14);
  static final Color headerShape = Colors.white.withValues(alpha: 0.06);
}

/// Consistent spacing scale — use instead of magic numbers where possible.
class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const xxxl = 40.0;
}

/// Consistent corner-radius scale.
class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

/// Soft, consistent elevation shadows (avoid ad-hoc BoxShadow everywhere).
class AppShadow {
  static List<BoxShadow> soft = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> card = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8)),
  ];
  static List<BoxShadow> floating = [
    BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8)),
  ];
}

class AppTextStyles {
  static TextStyle displayLarge(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15, color: AppColors.textPrimary);

  static TextStyle displayMedium(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 25, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.2, color: AppColors.textPrimary);

  static TextStyle headlineLarge(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.textPrimary);

  static TextStyle headlineMedium(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary);

  static TextStyle titleLarge(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary);

  static TextStyle titleMedium(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary);

  static TextStyle bodyLarge(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w400, height: 1.4, color: AppColors.textPrimary);

  static TextStyle bodyMedium(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400, height: 1.4, color: AppColors.textSecondary);

  static TextStyle bodySmall(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w400, color: AppColors.textHint);

  static TextStyle labelLarge(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2);

  static TextStyle caption(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w500, letterSpacing: 0.2, color: AppColors.textHint);

  static TextStyle price(BuildContext ctx) =>
      GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accent, letterSpacing: -0.2);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgLight,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.bgCard,
        error: AppColors.error,
        brightness: Brightness.light,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        shadowColor: Colors.black.withValues(alpha: 0.06),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgSection,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: AppSpace.lg),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 14),
        labelStyle: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.4),
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
          elevation: WidgetStateProperty.all(6),
          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 8, horizontal: 12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 0),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgSection,
        selectedColor: AppColors.primary,
        labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgDark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primaryLight,
        secondary: AppColors.accent,
        surface: AppColors.bgCardDark,
        error: AppColors.error,
        brightness: Brightness.dark,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimaryDark,
        displayColor: AppColors.textPrimaryDark,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimaryDark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgSectionDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: AppSpace.lg),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
        ),
        hintStyle: GoogleFonts.poppins(color: AppColors.textSecondaryDark, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.dividerDark, thickness: 1, space: 0),
    );
  }
}