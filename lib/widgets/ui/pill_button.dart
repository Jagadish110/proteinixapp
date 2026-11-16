import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';

enum PillTone {
  /// Peach fill, dark text — the default call to action.
  primary,

  /// Electric orange fill — high-heat actions (activate, capture).
  hot,

  /// Acid lime fill — positive progression (next, complete).
  lime,

  /// Transparent with hairline outline.
  outline,

  /// Filled neutral surface.
  neutral,

  /// Coral outline for destructive actions.
  danger,
}

/// Full-width pill CTA with press-scale feedback and a colour glow instead of
/// a black drop shadow.
class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.tone = PillTone.primary,
    this.icon,
    this.leading,
    this.trailingIcon,
    this.loading = false,
    this.expand = true,
    this.height = 56,
    this.glow = true,
    this.uppercase = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final PillTone tone;
  final IconData? icon;

  /// Custom leading widget (e.g. a brand logo) shown instead of [icon] when
  /// set — for cases like "Continue with Google" where the mark isn't a
  /// Material icon.
  final Widget? leading;
  final IconData? trailingIcon;
  final bool loading;
  final bool expand;
  final double height;
  final bool glow;
  final bool uppercase;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _down = false;

  ({Color bg, Color fg, Color? border}) get _palette {
    switch (widget.tone) {
      case PillTone.primary:
        return (bg: AppColors.primary, fg: AppColors.onPrimary, border: null);
      case PillTone.hot:
        return (bg: AppColors.primaryContainer, fg: Colors.white, border: null);
      case PillTone.lime:
        return (
          bg: AppColors.secondaryContainer,
          fg: AppColors.onSecondaryContainer,
          border: null
        );
      case PillTone.outline:
        return (
          bg: Colors.transparent,
          fg: AppColors.onSurface,
          border: AppColors.outline
        );
      case PillTone.neutral:
        return (
          bg: AppColors.surfaceContainerHigh,
          fg: AppColors.onSurface,
          border: AppColors.outline
        );
      case PillTone.danger:
        return (
          bg: Colors.transparent,
          fg: AppColors.tertiaryContainer,
          border: AppColors.tertiaryContainer
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    final enabled = widget.onPressed != null && !widget.loading;
    final showGlow = widget.glow &&
        enabled &&
        (widget.tone == PillTone.primary ||
            widget.tone == PillTone.hot ||
            widget.tone == PillTone.lime);

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: widget.height,
            width: widget.expand ? double.infinity : null,
            padding: widget.expand
                ? null
                : const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: p.bg,
              borderRadius: AppRadius.pill,
              border: p.border == null ? null : Border.all(color: p.border!),
              boxShadow: showGlow
                  ? AppColors.glow(p.bg, blur: 28, opacity: 0.3)
                  : null,
            ),
            child: Center(
              child: widget.loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(p.fg),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.leading != null) ...[
                          SizedBox(
                              width: 20, height: 20, child: widget.leading),
                          const SizedBox(width: 10),
                        ] else if (widget.icon != null) ...[
                          Icon(widget.icon, size: 20, color: p.fg),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            widget.uppercase
                                ? widget.label.toUpperCase()
                                : widget.label,
                            style: AppText.button(color: p.fg).copyWith(
                              letterSpacing: widget.uppercase ? 1.2 : 0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.trailingIcon != null) ...[
                          const SizedBox(width: 10),
                          Icon(widget.trailingIcon, size: 20, color: p.fg),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact inline pill used inside card headers ("Configure", "+ 250ml").
class MiniPill extends StatelessWidget {
  const MiniPill({
    super.key,
    required this.label,
    this.onTap,
    this.background,
    this.foreground,
    this.icon,
    this.border,
  });

  final String label;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;
  final Color? border;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? AppColors.onSurface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: background ?? AppColors.surfaceContainerHigh,
          borderRadius: AppRadius.pill,
          border: Border.all(color: border ?? AppColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
            ],
            Text(label, style: AppText.labelCaps(color: fg, size: 11)),
          ],
        ),
      ),
    );
  }
}

/// Circular icon enclosure — the 40–48px anchor used beside labels everywhere.
class IconBubble extends StatelessWidget {
  const IconBubble({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.background,
    this.size = 48,
    this.onTap,
    this.tinted = false,
    this.glow = false,
  });

  final IconData icon;
  final Color color;
  final Color? background;
  final double size;
  final VoidCallback? onTap;

  /// Fill the bubble with a 15% wash of [color] instead of a neutral surface.
  final bool tinted;

  /// Soft [color] halo behind the bubble, for when it needs to read as the
  /// card's focal point rather than a supporting label icon.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ??
            (tinted
                ? color.withValues(alpha: 0.15)
                : AppColors.surfaceContainerHigh),
        shape: BoxShape.circle,
        border: tinted ? null : Border.all(color: AppColors.outline),
        boxShadow: glow ? AppColors.glow(color, blur: 20, opacity: 0.25) : null,
      ),
      child: Icon(icon, color: color, size: size * 0.45),
    );

    if (onTap == null) return bubble;
    return GestureDetector(
        onTap: onTap, behavior: HitTestBehavior.opaque, child: bubble);
  }
}
