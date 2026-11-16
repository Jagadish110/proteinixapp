import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'food_icon.dart';

/// The foods logged to one meal slot, as icons rather than a run-on list of
/// names — "Boiled Egg, Chicken, Soy Chunks…" told you almost nothing once it
/// ellipsised, and the icons read at a glance.
///
/// Shows as many as fit and collapses the rest into a "+n" chip.
class FoodIconStrip extends StatelessWidget {
  const FoodIconStrip({super.key, required this.foodNames});

  /// Names only — the strip derives every icon from the name, so it needs
  /// nothing else from the meal row and can be laid out in isolation.
  final List<String> foodNames;

  static const _icon = 26.0;
  static const _gap = 5.0;

  /// Width reserved for the "+n" chip when not everything fits, at a text
  /// scale of 1. The icons are a fixed size but the chip is text, so this has
  /// to follow the user's font scaling or the reserve is too small exactly
  /// where the row is already tightest.
  static const _overflowChipAt1x = 26.0;

  /// A hard cap of five decided this, which overflowed its row by a few pixels
  /// on a narrow screen — how many fit depends on the width the meal title and
  /// calorie figure leave behind, not on a constant. Measuring also means it
  /// adapts to large text scales rather than clipping at them.
  @override
  Widget build(BuildContext context) {
    if (foodNames.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;

        // Unbounded width means there is nothing to fit to and nothing to
        // overflow, so show everything. Returning empty here instead would
        // trade a few pixels of overflow for silently losing the whole strip
        // — much worse, and invisible in review.
        var fits = available.isFinite
            ? ((available + _gap) / (_icon + _gap)).floor()
            : foodNames.length;

        // Re-measure against the narrower budget a "+n" chip would leave.
        // Without this second pass, dropping icons to make room for the chip
        // could make the chip itself overflow.
        if (available.isFinite && fits < foodNames.length) {
          final chip =
              MediaQuery.textScalerOf(context).scale(_overflowChipAt1x);
          fits = ((available - chip + _gap) / (_icon + _gap)).floor();
        }
        fits = fits.clamp(0, foodNames.length);

        final hidden = foodNames.length - fits;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < fits; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              FoodIcon(foodName: foodNames[i], size: _icon),
            ],
            if (hidden > 0) ...[
              if (fits > 0) const SizedBox(width: _gap),
              Text('+$hidden',
                  style: AppText.labelCaps(
                      color: AppColors.onSurfaceVariant, size: 11)),
            ],
          ],
        );
      },
    );
  }
}
