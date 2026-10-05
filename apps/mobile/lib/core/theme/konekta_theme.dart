import 'package:flutter/material.dart';

/// Design tokens lifted from DESIGN.md (Aruna Mobility System / KONEKTA).
/// Keep this file in sync with DESIGN.md if the design system changes --
/// it's the single source of truth every screen should read colors,
/// spacing and radius from instead of hardcoding values inline.
class AppColors {
  AppColors._();

  static const surface = Color(0xFFFCF8FF);
  static const surfaceDim = Color(0xFFDAD6FF);
  static const surfaceBright = Color(0xFFFCF8FF);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF6F1FF);
  static const surfaceContainer = Color(0xFFF0EBFF);
  static const surfaceContainerHigh = Color(0xFFEAE5FF);
  static const surfaceContainerHighest = Color(0xFFE3DFFF);
  static const onSurface = Color(0xFF191540);
  static const onSurfaceVariant = Color(0xFF494550);
  static const inverseSurface = Color(0xFF2E2B56);
  static const inverseOnSurface = Color(0xFFF3EEFF);
  static const outline = Color(0xFF7A7581);
  static const outlineVariant = Color(0xFFCBC4D1);
  static const surfaceTint = Color(0xFF685299);

  static const primary = Color(0xFF5E498F);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFF7761A9);
  static const onPrimaryContainer = Color(0xFFF6EDFF);
  static const inversePrimary = Color(0xFFD1BCFF);

  static const secondary = Color(0xFF006972);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFF95EEFA);
  static const onSecondaryContainer = Color(0xFF006D77);

  static const tertiary = Color(0xFF44518E);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFF5C6AA8);
  static const onTertiaryContainer = Color(0xFFF0F0FF);

  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);

  static const background = Color(0xFFFCF8FF);
  static const onBackground = Color(0xFF191540);

  static const inputFill = Color(0x80F0E7F6);
  static const inputFillBorder = Color.fromARGB(180, 202, 193, 211);
}

class AppSpacing {
  AppSpacing._();

  static const base = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const containerMargin = 20.0;
  static const gutter = 16.0;
}

class AppRadius {
  AppRadius._();

  static const sm = 4.0;
  static const standard = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 9999.0;
}

class AppTextStyles {
  AppTextStyles._();

  static const _headingFont = 'Hanken Grotesk';
  static const _bodyFont = 'Manrope';

  static const headlineXl = TextStyle(
    fontFamily: _headingFont,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
    letterSpacing: -0.02 * 32,
    color: AppColors.onSurface,
  );
  static const headlineLg = TextStyle(
    fontFamily: _headingFont,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 32 / 24,
    letterSpacing: -0.01 * 24,
    color: AppColors.onSurface,
  );
  static const headlineLgMobile = TextStyle(
    fontFamily: _headingFont,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 28 / 22,
    color: AppColors.onSurface,
  );
  static const headlineMd = TextStyle(
    fontFamily: _headingFont,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 28 / 20,
    color: AppColors.onSurface,
  );
  static const bodyLg = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 26 / 18,
    color: AppColors.onSurface,
  );
  static const bodyMd = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: AppColors.onSurface,
  );
  static const bodySm = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: AppColors.onSurfaceVariant,
  );
  static const labelMd = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 16 / 12,
    letterSpacing: 0.05 * 12,
    color: AppColors.onSurfaceVariant,
  );
}

class KonektaTheme {
  KonektaTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      inverseSurface: AppColors.inverseSurface,
      onInverseSurface: AppColors.inverseOnSurface,
      inversePrimary: AppColors.inversePrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Manrope',
      textTheme: const TextTheme(
        headlineLarge: AppTextStyles.headlineXl,
        headlineMedium: AppTextStyles.headlineLg,
        headlineSmall: AppTextStyles.headlineMd,
        bodyLarge: AppTextStyles.bodyLg,
        bodyMedium: AppTextStyles.bodyMd,
        bodySmall: AppTextStyles.bodySm,
        labelMedium: AppTextStyles.labelMd,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        errorMaxLines: 2,
        errorStyle: AppTextStyles.bodySm.copyWith(color: AppColors.error),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: const BorderSide(color: AppColors.inputFillBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: const BorderSide(color: AppColors.inputFillBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.standard),
          ),
          textStyle: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
