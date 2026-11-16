import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Hanken Grotesk type scale.
///
/// Hierarchy is carried by weight and colour rather than large size jumps —
/// bold/extrabold headings, muted regular body, and an uppercase tracked
/// `labelCaps` style that gives the UI its "cockpit" feel.
class AppText {
  const AppText._();

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: weight,
        height: height == null ? null : height / size,
        letterSpacing: letterSpacing,
        color: color ?? AppColors.onSurface,
      );

  /// Oversized hero numbers (calories, consistency score).
  static TextStyle display({Color? color}) => _base(
      size: 48,
      weight: FontWeight.w800,
      height: 52,
      letterSpacing: -1,
      color: color);

  /// Page titles — heavy and grounded.
  static TextStyle headlineLg({Color? color}) =>
      _base(size: 24, weight: FontWeight.w800, height: 32, color: color);

  /// Card titles / section titles.
  static TextStyle headlineMd({Color? color}) =>
      _base(size: 18, weight: FontWeight.w700, height: 24, color: color);

  /// Big at-a-glance metrics (macro grams, step counts).
  static TextStyle data({Color? color}) =>
      _base(size: 22, weight: FontWeight.w700, height: 28, color: color);

  /// Default reading text.
  static TextStyle body({Color? color}) =>
      _base(size: 14, weight: FontWeight.w400, height: 20, color: color);

  static TextStyle bodyBold({Color? color}) =>
      _base(size: 14, weight: FontWeight.w700, height: 20, color: color);

  static TextStyle bodySm({Color? color}) =>
      _base(size: 12, weight: FontWeight.w400, height: 16, color: color);

  /// Uppercase tracked micro-labels ("DAILY ENERGY", "LEFT", "EATEN").
  static TextStyle labelCaps({Color? color, double size = 10}) => _base(
        size: size,
        weight: FontWeight.w700,
        height: size * 1.2,
        letterSpacing: size * 0.05,
        color: color ?? AppColors.onSurfaceVariant,
      );

  /// Button text — pill buttons are always bold and slightly tracked.
  static TextStyle button({Color? color}) => _base(
      size: 15,
      weight: FontWeight.w700,
      height: 20,
      letterSpacing: 0.3,
      color: color);

  static TextTheme get theme => TextTheme(
        displayLarge: display(),
        displayMedium: display().copyWith(fontSize: 36, height: 40 / 36),
        headlineLarge: headlineLg(),
        headlineMedium: headlineMd(),
        headlineSmall: headlineMd().copyWith(fontSize: 16),
        titleLarge: headlineMd(),
        titleMedium: bodyBold(),
        titleSmall: labelCaps(size: 12),
        bodyLarge: body().copyWith(fontSize: 16, height: 22 / 16),
        bodyMedium: body(),
        bodySmall: bodySm(color: AppColors.onSurfaceVariant),
        labelLarge: button(),
        labelMedium: labelCaps(size: 12),
        labelSmall: labelCaps(),
      );
}
