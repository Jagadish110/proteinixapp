import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';

/// Blurred, hairline-bottomed top bar used by every pushed screen.
class TerraAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TerraAppBar({
    super.key,
    this.title,
    this.titleColor,
    this.leading,
    this.actions = const [],
    this.showBack = true,
    this.centerTitle = true,
    this.onBack,
    this.bottom,
  });

  final String? title;
  final Color? titleColor;
  final Widget? leading;
  final List<Widget> actions;
  final bool showBack;
  final bool centerTitle;
  final VoidCallback? onBack;
  final PreferredSizeWidget? bottom;

  /// Stroke width of the hairline under the bar.
  ///
  /// A [Border] insets its child by the stroke, so this pixel is part of the
  /// bar's real height and has to be in [preferredSize] too. Leaving it out is
  /// what made every screen using this bar report "A RenderFlex overflowed by
  /// 1.00 pixels on the bottom" — the [ClipRect] hid the stripe in release,
  /// but the error still fired on every rebuild.
  static const double _hairline = 1;

  @override
  Size get preferredSize =>
      Size.fromHeight(56 + _hairline + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    // Opaque rather than blurred: a BackdropFilter over a scrolling list has to
    // re-read the backdrop every frame, which is what makes scrolling stutter.
    return RepaintBoundary(
      child: ClipRect(
        child: SizedBox(
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(
                bottom: BorderSide(color: AppColors.outline, width: _hairline),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        if (leading != null)
                          leading!
                        else if (showBack)
                          _CircleAction(
                            icon: Icons.arrow_back_rounded,
                            onTap: onBack ?? () => Navigator.maybePop(context),
                          )
                        else
                          const SizedBox(width: 48),
                        Expanded(
                          child: Text(
                            title ?? '',
                            textAlign: centerTitle
                                ? TextAlign.center
                                : TextAlign.start,
                            style: AppText.headlineMd(color: titleColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (actions.isEmpty)
                          const SizedBox(width: 48)
                        else
                          ...actions,
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  if (bottom != null) bottom!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 40px round icon button used in app bars and card headers.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = AppColors.onSurface,
    this.background,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color? background;
  final bool badge;

  @override
  Widget build(BuildContext context) => _CircleAction(
        icon: icon,
        onTap: onTap,
        color: color,
        background: background,
        badge: badge,
      );
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.onTap,
    this.color = AppColors.onSurface,
    this.background,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color? background;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: background ?? AppColors.surfaceContainer,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 20, color: color),
                if (badge)
                  Positioned(
                    top: 9,
                    right: 10,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.tertiaryContainer,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar + brand/streak block used as the dashboard header leading widget.
class ProfileBadge extends StatefulWidget {
  const ProfileBadge({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 48,
    this.onTap,
    this.ringColor = AppColors.primaryContainer,
  });

  final String? name;
  final String? avatarUrl;
  final double size;
  final VoidCallback? onTap;
  final Color ringColor;

  @override
  State<ProfileBadge> createState() => _ProfileBadgeState();
}

class _ProfileBadgeState extends State<ProfileBadge> {
  bool _failed = false;

  @override
  void didUpdateWidget(covariant ProfileBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) _failed = false;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final initial = (name != null && name.trim().isNotEmpty)
        ? name.trim()[0].toUpperCase()
        : 'T';
    final hasAvatar =
        !_failed && widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceContainerHigh,
          border: Border.all(color: widget.ringColor, width: 2),
          image: hasAvatar
              ? DecorationImage(
                  image: NetworkImage(widget.avatarUrl!),
                  fit: BoxFit.cover,
                  // Avatar fetches from Supabase storage can drop mid-download
                  // on a flaky connection; without this the framework has no
                  // handler and the failure surfaces as an uncaught error
                  // (see Diagnostics) while the circle stays blank. Falling
                  // back to the initial keeps it recoverable and silent.
                  onError: (_, __) {
                    if (mounted) setState(() => _failed = true);
                  },
                )
              : null,
        ),
        alignment: Alignment.center,
        child: hasAvatar
            ? null
            : Text(
                initial,
                style: AppText.headlineMd(color: AppColors.primary)
                    .copyWith(fontSize: widget.size * 0.4),
              ),
      ),
    );
  }
}

/// Thin determinate bar used for onboarding steps and macro compliance.
class LinearMeter extends StatelessWidget {
  const LinearMeter({
    super.key,
    required this.value,
    this.color = AppColors.secondary,
    this.height = 8,
    this.trackColor = AppColors.track,
    this.glow = false,
  });

  final double value;
  final Color color;
  final double height;
  final Color trackColor;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: AppRadius.pill,
      child: Container(
        height: height,
        color: trackColor,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: v),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => FractionallySizedBox(
              widthFactor: t == 0 ? 0.001 : t,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: AppRadius.pill,
                  boxShadow: glow
                      ? AppColors.glow(color, blur: 10, opacity: 0.5)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
