import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/food_icon_resolver.dart';

/// Circular icon for a logged food, derived from its name alone.
///
/// Shape and sizing mirror [IconBubble] so the two can sit in the same list.
class FoodIcon extends StatelessWidget {
  const FoodIcon({
    super.key,
    required this.foodName,
    this.size = 44,
    this.tinted = true,
  });

  /// Which OpenMoji set the whole app draws from.
  ///
  /// [FoodIconStyle.color] keeps the glyph's own colours, which read faster at
  /// list size; [FoodIconStyle.mono] is line art tinted with the category's
  /// macro colour, which sits closer to the Obsidian palette. The bubble wash
  /// carries the macro colour either way.
  static const FoodIconStyle style = FoodIconStyle.color;

  final String foodName;
  final double size;

  /// Fill the bubble with a 15% wash of the category tint instead of a
  /// neutral surface.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final category = FoodIconResolver.resolve(foodName);
    final photo = FoodIconResolver.photoFor(foodName);
    final tint = category.tint;
    final glyphSize = size * 0.58;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // A photo fills the whole circle itself (see the crop step that
        // produced these assets) — any macro-tint wash behind it only shows
        // through the sliver of transparent corner the crop couldn't reach,
        // which reads as a stray colour patch (an orange wash showing as
        // "brown" was exactly the bug) rather than a deliberate backdrop. No
        // wash at all there; it's just the surface behind, same as the row.
        color: photo != null
            ? null
            : (tinted
                ? tint.withValues(alpha: 0.15)
                : AppColors.surfaceContainerHigh),
        shape: BoxShape.circle,
        border: (tinted || photo != null)
            ? null
            : Border.all(color: AppColors.outline),
      ),
      child: photo != null
          ? ClipOval(
              child: Image.asset(
                photo,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // A missing/corrupt photo asset shouldn't leave a hole in the
                // row — drop back to the tinted glyph exactly as if this dish
                // had no photo match at all.
                errorBuilder: (_, __, ___) => SvgPicture.asset(
                  category.assetFor(style),
                  width: glyphSize,
                  height: glyphSize,
                  colorFilter: style == FoodIconStyle.mono
                      ? ColorFilter.mode(tint, BlendMode.srcIn)
                      : null,
                ),
              ),
            )
          : SvgPicture.asset(
              category.assetFor(style),
              width: glyphSize,
              height: glyphSize,
              colorFilter: style == FoodIconStyle.mono
                  ? ColorFilter.mode(tint, BlendMode.srcIn)
                  : null,
              // A decode failure shouldn't leave a hole in the row.
              placeholderBuilder: (_) =>
                  Icon(category.icon, color: tint, size: glyphSize),
            ),
    );
  }
}
