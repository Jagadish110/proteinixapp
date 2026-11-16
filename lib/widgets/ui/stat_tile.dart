import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import 'terra_card.dart';

/// Small metric card: tinted icon, editable affordance, caps label, big value.
/// Used in the profile "Health Goals" grid.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.unit,
    this.onEdit,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color accent;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return TerraCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: onEdit,
      // Icon pinned to the top, figures to the bottom, and the figures allowed
      // to shrink rather than overflow.
      //
      // The tile is laid out in a grid cell whose height comes from the
      // caller's aspect ratio, and it used to assert a fixed minimum: a 22pt
      // value under an 18px gap. Any cell shorter than that silently clipped
      // the value off the bottom — which is how the sleep grid shipped with
      // every number half-cut, and how the profile grid overflows by 2px on a
      // 320dp phone. Scaling down is a far better failure than truncating.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: accent, size: 22),
              if (onEdit != null)
                const Icon(Icons.edit_outlined,
                    color: AppColors.onSurfaceVariant, size: 16),
            ],
          ),
          Flexible(
            // LayoutBuilder because FittedBox hands its child *unbounded*
            // width, and an unbounded Row cannot flex or ellipsize — it throws.
            // Clamping back to the tile's own width keeps the label truncating
            // horizontally as normal, leaving FittedBox to solve only the
            // vertical problem it is here for.
            child: LayoutBuilder(
              builder: (context, box) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.labelCaps(size: 10)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(value,
                                maxLines: 1,
                                style: AppText.data(),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (unit != null) ...[
                            const SizedBox(width: 4),
                            Text(unit!,
                                style: AppText.bodySm(
                                    color: AppColors.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Row of a leading icon bubble, title/subtitle, and a trailing widget.
class TerraListRow extends StatelessWidget {
  const TerraListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = AppColors.primary,
    this.iconBackground,
    this.leading,
    this.subtitleWidget,
    this.trailing,
    this.onTap,
    this.dimmed = false,
  }) : assert(icon != null || leading != null,
            'TerraListRow needs either an icon or a leading widget');

  final String title;
  final String? subtitle;

  /// Rendered under the title in place of [subtitle] — used for rows that
  /// summarise with icons rather than words.
  final Widget? subtitleWidget;
  final IconData? icon;
  final Color iconColor;
  final Color? iconBackground;

  /// Replaces the built-in icon bubble — used to drop a [FoodIcon] in.
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return TerraCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      dimmed: dimmed,
      elevated: false,
      child: Row(
        children: [
          leading ??
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBackground ?? AppColors.surfaceContainerHigh,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.bodyBold(
                    color: dimmed
                        ? AppColors.onSurfaceVariant
                        : AppColors.onSurface,
                  ),
                ),
                if (subtitleWidget != null) ...[
                  const SizedBox(height: 5),
                  subtitleWidget!,
                ] else if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Centred placeholder for empty lists and failed loads.
class TerraEmptyState extends StatelessWidget {
  const TerraEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.accent = AppColors.onSurfaceVariant,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg, horizontal: AppSpacing.md),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 28),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, textAlign: TextAlign.center, style: AppText.headlineMd()),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.onSurfaceVariant),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.sm),
            action!
          ],
        ],
      ),
    );
  }
}

/// Pill badge used for streaks, "AI VERIFIED", "+12% vs last week".
class TerraBadge extends StatelessWidget {
  const TerraBadge({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.primary,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: filled ? AppColors.onPrimary : color),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: AppText.labelCaps(
              color: filled ? AppColors.onPrimary : color,
              size: 11,
            ),
          ),
        ],
      ),
    );
  }
}
