import 'package:flutter/material.dart';

/// Vigor Obsidian design tokens.
///
/// Dark-mode-first palette anchored on pure black for OLED efficiency, with
/// electric orange / peach as primary, acid lime as secondary and vivid pink
/// as tertiary. Every colour used across the app must come from here.
class AppColors {
  const AppColors._();

  // ── Base ───────────────────────────────────────────────────────────────
  static const Color background = Color(0xFF000000);
  static const Color onBackground = Color(0xFFE5E2E1);

  // ── Surfaces (tonal layering) ──────────────────────────────────────────
  static const Color surface = Color(0xFF131313);
  static const Color surfaceDim = Color(0xFF131313);
  static const Color surfaceBright = Color(0xFF393939);
  static const Color surfaceContainerLowest = Color(0xFF0E0E0E);
  static const Color surfaceContainerLow = Color(0xFF1C1B1B);
  static const Color surfaceContainer = Color(0xFF201F1F);
  static const Color surfaceContainerHigh = Color(0xFF2A2A2A);
  static const Color surfaceContainerHighest = Color(0xFF353534);

  /// Interactive sub-elements: icon enclosures, chips, inline buttons.
  static const Color surfaceVariant = Color(0xFF1B1B1B);

  /// Neutral track behind every progress ring / bar.
  static const Color track = Color(0xFF353534);

  // ── Text ───────────────────────────────────────────────────────────────
  static const Color onSurface = Color(0xFFE5E2E1);
  static const Color onSurfaceVariant = Color(0xFFA1A1A1);
  static const Color inverseSurface = Color(0xFFE5E2E1);
  static const Color inverseOnSurface = Color(0xFF313030);

  // ── Outlines ───────────────────────────────────────────────────────────
  static const Color outline = Color(0xFF393939);
  static const Color outlineVariant = Color(0xFF5B4138);

  // ── Primary (electric orange / peach) ──────────────────────────────────
  static const Color primary = Color(0xFFFFB59C);
  static const Color onPrimary = Color(0xFF5C1900);
  static const Color primaryContainer = Color(0xFFFF5F1F);
  static const Color onPrimaryContainer = Color(0xFF561700);
  static const Color primaryFixed = Color(0xFFFFDBCF);
  static const Color primaryFixedDim = Color(0xFFFFB59C);
  static const Color onPrimaryFixed = Color(0xFF390C00);
  static const Color onPrimaryFixedVariant = Color(0xFF832700);
  static const Color inversePrimary = Color(0xFFAB3600);

  // ── Secondary (acid lime) ──────────────────────────────────────────────
  static const Color secondary = Color(0xFFC4F030);
  static const Color onSecondary = Color(0xFF283500);
  static const Color secondaryContainer = Color(0xFFA9D300);
  static const Color onSecondaryContainer = Color(0xFF445700);
  static const Color secondaryFixed = Color(0xFFC6F333);
  static const Color secondaryFixedDim = Color(0xFFABD604);
  static const Color onSecondaryFixed = Color(0xFF161E00);
  static const Color onSecondaryFixedVariant = Color(0xFF3C4D00);

  // ── Tertiary (vivid pink) ──────────────────────────────────────────────
  static const Color tertiary = Color(0xFFFFB3B5);
  static const Color onTertiary = Color(0xFF680019);
  static const Color tertiaryContainer = Color(0xFFFF596C);
  static const Color onTertiaryContainer = Color(0xFF600017);
  static const Color tertiaryFixed = Color(0xFFFFDADA);
  static const Color tertiaryFixedDim = Color(0xFFFFB3B5);
  static const Color onTertiaryFixed = Color(0xFF40000C);
  static const Color onTertiaryFixedVariant = Color(0xFF920027);

  // ── Error ──────────────────────────────────────────────────────────────
  static const Color error = Color(0xFFFFB4AB);
  static const Color onError = Color(0xFF690005);
  static const Color errorContainer = Color(0xFF93000A);
  static const Color onErrorContainer = Color(0xFFFFDAD6);

  // ── Semantic accents ───────────────────────────────────────────────────
  static const Color hydrationBlue = Color(0xFF00A2FF);
  static const Color fiberTeal = Color(0xFF00D1B2);

  /// Sleep's own colour.
  ///
  /// It used to borrow [tertiary], the same pink dinner uses — so on the
  /// dashboard the sleep ring and the dinner row read as the same thing, and
  /// sleep had no identity of its own in a stack of four rings. Violet is the
  /// one hue the palette wasn't already using, and it is what night reads as.
  static const Color sleepViolet = Color(0xFFB388FF);

  // ── Macro mapping (dashboard rings) ────────────────────────────────────
  static const Color protein = secondary;
  static const Color carbs = primaryContainer;
  static const Color fat = tertiaryContainer;
  static const Color fiber = fiberTeal;
  static const Color water = hydrationBlue;
  static const Color sleep = sleepViolet;

  // ── Glow helpers ───────────────────────────────────────────────────────
  /// "Emitted light" shadow used instead of black drop shadows.
  static List<BoxShadow> glow(Color color,
          {double blur = 24, double opacity = 0.25}) =>
      [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: blur,
          spreadRadius: 1,
        ),
      ];

  /// Soft elevation for cards on pure black.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0xB3000000), blurRadius: 20, offset: Offset(0, 8)),
  ];
}
