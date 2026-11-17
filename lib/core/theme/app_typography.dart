import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Two-family type scale: Space Grotesk for headings and the big numbers,
/// Inter for everything people read.
///
/// The display face carries the brand — its squared, slightly technical
/// numerals are what make "62 / 110 g" look like a measurement rather than a
/// sentence. Inter keeps body copy, labels and buttons quiet and legible at
/// small sizes.
class AppText {
  const AppText._();

  /// Headings and numbers.
  static TextStyle _display({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        height: height == null ? null : height / size,
        letterSpacing: letterSpacing,
        color: color ?? AppColors.onSurface,
      );

  /// Body, labels and buttons.
  static TextStyle _base({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        height: height == null ? null : height / size,
        letterSpacing: letterSpacing,
        color: color ?? AppColors.onSurface,
      );

  /// Oversized hero numbers (calories, consistency score).
  static TextStyle display({Color? color}) => _display(
      size: 48,
      weight: FontWeight.w700,
      height: 52,
      letterSpacing: -1,
      color: color);

  /// Page titles — heavy and grounded.
  static TextStyle headlineLg({Color? color}) => _display(
      size: 26,
      weight: FontWeight.w700,
      height: 32,
      letterSpacing: -0.5,
      color: color);

  /// Card titles / section titles.
  static TextStyle headlineMd({Color? color}) =>
      _display(size: 18, weight: FontWeight.w700, height: 24, color: color);

  /// Big at-a-glance metrics (macro grams, step counts).
  static TextStyle data({Color? color}) =>
      _display(size: 24, weight: FontWeight.w700, height: 28, color: color);

  /// Default reading text.
  static TextStyle body({Color? color}) =>
      _base(size: 14, weight: FontWeight.w400, height: 20, color: color);

  static TextStyle bodyBold({Color? color}) =>
      _base(size: 14, weight: FontWeight.w600, height: 20, color: color);

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
      letterSpacing: 0.1,
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
