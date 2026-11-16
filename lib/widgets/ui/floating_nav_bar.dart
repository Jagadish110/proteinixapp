import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';

class NavDestination {
  const NavDestination({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Detached floating navigation bar.
///
/// A rounded-rectangle highlight slides between destinations on tab change.
/// The capture action sits inline in the middle slot rather than overhanging
/// the bar, so nothing can clip it.
///
/// Deliberately no BackdropFilter: a blur sitting over scrolling content has to
/// re-read the backdrop every frame, which is the main source of scroll jank on
/// mid-range hardware. A near-opaque fill costs nothing and reads the same.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    required this.captureIndex,
    required this.onCapture,
    this.captureIcon = Icons.photo_camera_rounded,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// Position in [destinations] occupied by the capture button.
  final int captureIndex;
  final VoidCallback onCapture;
  final IconData captureIcon;

  static const double _barHeight = 70;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: RepaintBoundary(
        child: Container(
          height: _barHeight,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: AppRadius.pill,
            border: Border.all(color: AppColors.outline),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x2610201A),
                  blurRadius: 24,
                  offset: Offset(0, 8)),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / destinations.length;
              const insetX = 6.0;
              const insetY = 9.0;

              return Stack(
                children: [
                  // Sliding highlight — matches the app's card curve language
                  // (32px on full-size cards, scaled down for this bar's height)
                  // rather than a tight, near-square corner.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    left: slot * currentIndex + insetX,
                    top: insetY,
                    bottom: insetY,
                    width: slot - insetX * 2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(destinations.length, (i) {
                      if (i == captureIndex) {
                        return Expanded(
                          child: _CaptureButton(
                            icon: captureIcon,
                            onTap: onCapture,
                          ),
                        );
                      }
                      return Expanded(
                        child: _NavItem(
                          destination: destinations[i],
                          active: currentIndex == i,
                          onTap: () => onSelect(i),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: active ? 1 : 0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, t, child) => Transform.translate(
              offset: Offset(0, -1.5 * t),
              child: Transform.scale(scale: 1 + 0.10 * t, child: child),
            ),
            child: Icon(
              destination.icon,
              size: 21,
              color: active ? AppColors.primary : AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: AppText.labelCaps(
              color: active ? AppColors.primary : AppColors.onSurfaceVariant,
              size: 9,
            ).copyWith(
              letterSpacing: 0,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
            child: Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Middle-slot capture action — filled and inline, matching the highlight's
/// soft-rectangle language.
class _CaptureButton extends StatefulWidget {
  const _CaptureButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 130),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow:
                  AppColors.glow(AppColors.primary, blur: 18, opacity: 0.4),
            ),
            child: Icon(widget.icon, color: AppColors.onPrimary, size: 24),
          ),
        ),
      ),
    );
  }
}
