import 'package:flutter/material.dart';

/// Proteinix design tokens — the light theme.
///
/// A pale green-grey ground with white cards. Deep green is primary (buttons,
/// links, the selected state), amber is secondary (protein, highlights) and
/// rose is tertiary. Every colour used across the app must come from here.
///
/// The token *names* are unchanged from the earlier dark palette, so every
/// card and layout is exactly where it was; only the values differ. Colours
/// that double as text — [primary], [secondary], [tertiary], [error] and the
/// semantic accents — are all dark enough to read at 4.5:1 on a white card.
class AppColors {
  const AppColors._();

  // ── Base ───────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF3F6F0);
  static const Color onBackground = Color(0xFF10201A);

  // ── Surfaces (tonal layering) ──────────────────────────────────────────
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDim = Color(0xFFE6EBE3);
  static const Color surfaceBright = Color(0xFFFFFFFF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFFFFFFF);
  static const Color surfaceContainer = Color(0xFFFFFFFF);
  static const Color surfaceContainerHigh = Color(0xFFE9EFE6);
  static const Color surfaceContainerHighest = Color(0xFFDDE5DA);

  /// Interactive sub-elements: icon enclosures, chips, inline buttons.
  static const Color surfaceVariant = Color(0xFFE9EFE6);

  /// Neutral track behind every progress ring / bar.
  static const Color track = Color(0xFFDDE5DA);

  // ── Text ───────────────────────────────────────────────────────────────
  static const Color onSurface = Color(0xFF10201A);
  static const Color onSurfaceVariant = Color(0xFF4F6158);
  static const Color inverseSurface = Color(0xFF10201A);
  static const Color inverseOnSurface = Color(0xFFF3F6F0);

  // ── Outlines ───────────────────────────────────────────────────────────
  static const Color outline = Color(0xFFD5DDD1);
  static const Color outlineVariant = Color(0xFFC9D6CF);

  // ── Primary (deep green; container is the vivid orange accent) ──────────────────────────────────
  static const Color primary = Color(0xFF0B5D3F);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFC24E00);
  static const Color onPrimaryContainer = Color(0xFFFFFFFF);
  static const Color primaryFixed = Color(0xFFCFEBDD);
  static const Color primaryFixedDim = Color(0xFF8FE3B8);
  static const Color onPrimaryFixed = Color(0xFF06301F);
  static const Color onPrimaryFixedVariant = Color(0xFF0B5D3F);
  static const Color inversePrimary = Color(0xFF8FE3B8);

  // ── Secondary (amber) ──────────────────────────────────────────────
  static const Color secondary = Color(0xFF9A5700);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFFFB020);
  static const Color onSecondaryContainer = Color(0xFF3A2000);
  static const Color secondaryFixed = Color(0xFFFFE9C7);
  static const Color secondaryFixedDim = Color(0xFFFFB020);
  static const Color onSecondaryFixed = Color(0xFF2A1700);
  static const Color onSecondaryFixedVariant = Color(0xFF7A3E00);

  // ── Tertiary (rose) ──────────────────────────────────────────────
  static const Color tertiary = Color(0xFFB4234F);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFC92F5C);
  static const Color onTertiaryContainer = Color(0xFFFFFFFF);
  static const Color tertiaryFixed = Color(0xFFFFDADF);
  static const Color tertiaryFixedDim = Color(0xFFFFB3C0);
  static const Color onTertiaryFixed = Color(0xFF40000C);
  static const Color onTertiaryFixedVariant = Color(0xFF920027);

  // ── Error ──────────────────────────────────────────────────────────────
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF410002);

  // ── Semantic accents ───────────────────────────────────────────────────
  static const Color hydrationBlue = Color(0xFF1A70BC);
  static const Color fiberTeal = Color(0xFF7B5E3B);

  /// Sleep's own colour.
  ///
  /// It used to borrow [tertiary], the same pink dinner uses — so on the
  /// dashboard the sleep ring and the dinner row read as the same thing, and
  /// sleep had no identity of its own in a stack of four rings. Violet is the
  /// one hue the palette wasn't already using, and it is what night reads as.
  static const Color sleepViolet = Color(0xFF6D4AD6);

  // ── Macro mapping (dashboard rings) ────────────────────────────────────
  //
  // Chosen to be told apart by lightness as well as hue, since these four sit
  // side by side: dark green, mid amber, rose, brown. Protein takes the brand
  // green because it is the number the app is named after.
  static const Color protein = primary;
  static const Color carbs = Color(0xFFD67A00);
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

  /// Soft elevation for white cards on the pale ground. Tinted with the ink
  /// green rather than pure black, and kept faint: on a light theme a heavy
  /// shadow reads as dirt.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x1410201A), blurRadius: 18, offset: Offset(0, 6)),
  ];
}
