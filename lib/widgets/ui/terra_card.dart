import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';

/// Level-1 surface: the single card shape the whole app is built from.
///
/// 32px organic curve, `surface-container` fill, hairline outline and a soft
/// black lift. Never nest a TerraCard inside another TerraCard — use
/// [AppColors.surfaceContainerHigh] blocks for sub-elements instead.
class TerraCard extends StatelessWidget {
  const TerraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin,
    this.color,
    this.borderColor,
    this.radius = AppRadius.card,
    this.onTap,
    this.elevated = true,
    this.dimmed = false,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final bool elevated;

  /// Renders the card at reduced emphasis (e.g. a meal slot not logged yet).
  final bool dimmed;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    // Deliberately a plain Container: a screen holds a dozen of these and an
    // implicit-animation widget each would mean a dozen idle AnimationControllers.
    final card = Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ??
            (dimmed
                ? AppColors.surfaceContainer.withValues(alpha: 0.5)
                : AppColors.surfaceContainer),
        borderRadius: shape,
        border: Border.all(
          color: borderColor ??
              (dimmed
                  ? AppColors.outline.withValues(alpha: 0.3)
                  : AppColors.outline),
        ),
        boxShadow: elevated ? AppColors.cardShadow : null,
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: shape,
        child: card,
      ),
    );
  }
}

/// Uppercase tracked micro-heading that labels a card or a page section.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text,
      {super.key, this.color, this.trailing, this.icon});

  final String text;
  final Color? color;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: color ?? AppColors.primary),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: AppText.labelCaps(
                color: color ?? AppColors.onSurfaceVariant, size: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (trailing == null) return label;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Flexible(child: label), trailing!],
    );
  }
}

/// Larger "Today's Meals" style heading with an optional text action.
class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(title, style: AppText.headlineLg())),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                actionLabel!.toUpperCase(),
                style: AppText.labelCaps(color: AppColors.primary, size: 11),
              ),
            ),
          ),
      ],
    );
  }
}
