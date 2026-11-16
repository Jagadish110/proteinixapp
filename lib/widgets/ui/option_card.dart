import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';

/// Large tappable choice tile with a centred icon — onboarding goal picker.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.accent = AppColors.secondary,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : AppColors.surfaceContainer,
          borderRadius: AppRadius.cardR,
          border: Border.all(
            color: selected ? accent : AppColors.outline,
            width: selected ? 2 : 1,
          ),
          boxShadow:
              selected ? AppColors.glow(accent, blur: 20, opacity: 0.18) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 30,
                color: selected ? accent : AppColors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.headlineMd(
                color: selected ? AppColors.onSurface : AppColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Radio-style row with a title and a supporting description — activity level.
class RadioOptionCard extends StatelessWidget {
  const RadioOptionCard({
    super.key,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.accent = AppColors.secondary,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.10)
              : AppColors.surfaceContainer,
          borderRadius: AppRadius.cardR,
          border: Border.all(
            color: selected ? accent : AppColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accent : AppColors.outline,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: accent, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.headlineMd()),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppText.body(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact meal-type selector cell (Breakfast / Lunch / Snack / Dinner).
class MealTypeTile extends StatelessWidget {
  const MealTypeTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.accent = AppColors.primary,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? accent : AppColors.surfaceContainer,
          borderRadius: AppRadius.cardR,
          border: Border.all(color: selected ? accent : AppColors.outline),
          boxShadow:
              selected ? AppColors.glow(accent, blur: 18, opacity: 0.25) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 26, color: selected ? AppColors.onPrimary : accent),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppText.bodyBold(
                color: selected ? AppColors.onPrimary : AppColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One choice in a [MealTypeSelector].
class MealTypeOption {
  const MealTypeOption({required this.value, required this.icon, this.label});

  /// Stored form, e.g. "breakfast".
  final String value;
  final IconData icon;

  /// Defaults to [value] with its first letter capitalised.
  final String? label;

  String get displayLabel =>
      label ??
      (value.isEmpty ? '' : value[0].toUpperCase() + value.substring(1));
}

/// Grid of meal-type tiles, [columns] per row.
///
/// Rows are sized to their content rather than to a fixed aspect ratio. The
/// previous `childAspectRatio` gave each cell 63px at 320dp for a tile that
/// needs ~92px, so the icon and label overflowed the bottom by 29px — and any
/// text scaling above 1.0 pushed wider screens over the same edge.
class MealTypeSelector extends StatelessWidget {
  const MealTypeSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.columns = 2,
    this.spacing = AppSpacing.gutter,
    this.accent = AppColors.primary,
  });

  final List<MealTypeOption> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final int columns;
  final double spacing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final rows = <List<MealTypeOption>>[
      for (var i = 0; i < options.length; i += columns)
        options.sublist(i, math.min(i + columns, options.length)),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: spacing),
          // Stretch keeps both tiles in a row the same height when one label
          // wraps; IntrinsicHeight is what makes stretch legal in a Column.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) SizedBox(width: spacing),
                  Expanded(
                    child: c < rows[r].length
                        ? MealTypeTile(
                            label: rows[r][c].displayLabel,
                            icon: rows[r][c].icon,
                            selected: selected == rows[r][c].value,
                            accent: accent,
                            onTap: () => onSelected(rows[r][c].value),
                          )
                        // Keeps a short final row aligned with the ones above.
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
