import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_motion.dart';

/// ============================================================
/// DESIGN SYSTEM — TezRider
/// Modern, premium delivery-marketplace visual language.
/// This file is purely visual (colors/type/spacing/component
/// themes) — no business logic, API, or auth code lives here.
/// ============================================================

class AppColors {
  // ---- Brand ----
  // Deep coral carries accessible white labels; coral is decorative.
  static const coral = Color(0xFFFF625E);
  static const primary = Color(0xFFC9413D);
  static const primaryDark = Color(0xFFA6322F);
  static const primaryLight = Color(0xFFFF625E);
  static const primarySurface = Color(0xFFFFE8E5);

  // Warm terracotta detail, distinct from semantic warning and error.
  static const accent = Color(0xFFAD4936);
  static const accentLight = Color(0xFFFFB3A1);
  static const accentSurface = Color(0xFFFFF0E9);

  static const success = Color(0xFF217B5B);
  static const warning = Color(0xFF996512);
  static const error = Color(0xFFE0342A);
  static const info = Color(0xFF2563EB);

  // Warm paper canvas with lifted white surfaces.
  static const bgLight = Color(0xFFFFF9F5);
  static const bgCard = Color(0xFFFFFFFF);
  static const bgSection = Color(0xFFFFF0EA);

  // Warm charcoal and readable secondary text.
  static const textPrimary = Color(0xFF242424);
  static const textSecondary = Color(0xFF69615E);
  static const textHint = Color(0xFF69615E);
  static const divider = Color(0xFFF0E4DD);

  static const bgDark = Color(0xFF1B1615);
  static const bgCardDark = Color(0xFF292220);
  static const bgSectionDark = Color(0xFF362B28);
  static const textPrimaryDark = Color(0xFFFFF5EF);
  static const textSecondaryDark = Color(0xFFD1BEB5);
  static const dividerDark = Color(0xFF4A3933);

  // ---- Category accents ----
  static const catFood = Color(0xFFE8715A);
  static const catGrocery = Color(0xFF0D9488);
  static const catPharmacy = Color(0xFFEAB308);
  static const catThrift = Color(0xFFEC4899);
  static const catTailoring = Color(0xFF8B5CF6);
  static const catElectronics = Color(0xFF2563EB);
  static const catGifts = Color(0xFFDB2777);

  // ---- Role identity colors ----
  static const roleCustomer = Color(0xFFC9413D);
  static const roleCustomerAccent = Color(0xFFB83C38);
  static const roleCustomerSoft = Color(0xFFA6322F);

  static const roleVendor = Color(0xFFB83C38);
  static const roleVendorAccent = Color(0xFFA6322F);
  static const roleVendorSoft = Color(0xFF96312C);

  static const roleRider = Color(0xFFC9413D);
  static const roleRiderAccent = Color(0xFFB83C38);
  static const roleRiderSoft = Color(0xFFA6322F);

  static const roleAdmin = Color(0xFF96312C);

  static final List<Color> gradientPrimary = [primary, primaryDark];
  static final List<Color> gradientDark = [primaryDark, primary];
  static final List<Color> gradientSuccess = [success, const Color(0xFF059669)];
  static final List<Color> gradientAccent = [accent, primaryDark];

  static final List<Color> customerGradient = [
    roleCustomer,
    roleCustomerAccent,
    roleCustomerSoft,
  ];
  static final List<Color> vendorGradient = [
    roleVendor,
    roleVendorAccent,
    roleVendorSoft,
  ];
  static final List<Color> riderGradient = [
    roleRider,
    roleRiderAccent,
    roleRiderSoft,
  ];

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
  static const xxl = 24.0;
  static const section = 32.0;
  static const xxxl = 40.0;
}

/// Consistent corner-radius scale.
class AppRadius {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const pill = 999.0;
}

/// Soft, consistent elevation shadows (avoid ad-hoc BoxShadow everywhere).
class AppShadow {
  static List<BoxShadow> soft = [
    BoxShadow(
      color: const Color(0xFF6B3325).withValues(alpha: 0.045),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];
  static List<BoxShadow> card = [
    BoxShadow(
      color: const Color(0xFF6B3325).withValues(alpha: 0.06),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
  static List<BoxShadow> floating = [
    BoxShadow(
      color: const Color(0xFF6B3325).withValues(alpha: 0.12),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Poppins for English with a bundled Arabic-script fallback for Urdu.
/// GoogleFonts discovers both files in the existing declared asset directory.
abstract final class AppTypography {
  static final List<String> fallbacks = [
    GoogleFonts.notoNaskhArabic().fontFamily!,
    'sans-serif',
  ];

  static TextStyle poppins({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    Color? color,
  }) => GoogleFonts.poppins(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  ).copyWith(fontFamilyFallback: fallbacks);
}

class AppTextStyles {
  static TextStyle displayLarge(BuildContext ctx) => AppTypography.poppins(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    height: 1.15,
    color: AppColors.textPrimary,
  );

  static TextStyle displayMedium(BuildContext ctx) => AppTypography.poppins(
    fontSize: 25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  static TextStyle headlineLarge(BuildContext ctx) => AppTypography.poppins(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static TextStyle headlineMedium(BuildContext ctx) => AppTypography.poppins(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle titleLarge(BuildContext ctx) => AppTypography.poppins(
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle titleMedium(BuildContext ctx) => AppTypography.poppins(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle bodyLarge(BuildContext ctx) => AppTypography.poppins(
    fontSize: 14.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static TextStyle bodyMedium(BuildContext ctx) => AppTypography.poppins(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static TextStyle bodySmall(BuildContext ctx) => AppTypography.poppins(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textHint,
  );

  static TextStyle labelLarge(BuildContext ctx) => AppTypography.poppins(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static TextStyle caption(BuildContext ctx) => AppTypography.poppins(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: AppColors.textHint,
  );

  static TextStyle price(BuildContext ctx) => AppTypography.poppins(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: AppColors.accent,
    letterSpacing: -0.2,
  );
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitions(),
          TargetPlatform.iOS: AppPageTransitions(),
          TargetPlatform.windows: AppPageTransitions(),
        },
      ),
      scaffoldBackgroundColor: AppColors.bgLight,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.bgCard,
        error: AppColors.error,
        brightness: Brightness.light,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primarySurface,
        onPrimaryContainer: AppColors.primaryDark,
        onSurface: AppColors.textPrimary,
        outline: AppColors.divider,
        surfaceTint: Colors.transparent,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        fontFamilyFallback: AppTypography.fallbacks,
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
        titleTextStyle: AppTypography.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.divider),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.06),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: AppSpace.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        errorMaxLines: 3,
        floatingLabelStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: AppTypography.poppins(
          color: AppColors.textHint,
          fontSize: 14,
        ),
        labelStyle: AppTypography.poppins(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: AppTypography.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.4),
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: AppTypography.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
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
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          elevation: WidgetStateProperty.all(6),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        showDragHandle: true,
        clipBehavior: Clip.antiAlias,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTypography.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgSection,
        selectedColor: AppColors.primarySurface,
        labelStyle: AppTypography.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        side: const BorderSide(color: AppColors.divider),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: AppTypography.poppins(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitions(),
          TargetPlatform.iOS: AppPageTransitions(),
          TargetPlatform.windows: AppPageTransitions(),
        },
      ),
      scaffoldBackgroundColor: AppColors.bgDark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primaryLight,
        secondary: AppColors.accent,
        surface: AppColors.bgCardDark,
        error: AppColors.error,
        brightness: Brightness.dark,
        onPrimary: AppColors.textPrimary,
        onSurface: AppColors.textPrimaryDark,
        surfaceTint: Colors.transparent,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        fontFamilyFallback: AppTypography.fallbacks,
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
        titleTextStyle: AppTypography.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryDark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgSectionDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: AppSpace.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(
            color: AppColors.primaryLight,
            width: 1.5,
          ),
        ),
        hintStyle: AppTypography.poppins(
          color: AppColors.textSecondaryDark,
          fontSize: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: AppTypography.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.dividerDark,
        thickness: 1,
        space: 0,
      ),
    );
  }
}
