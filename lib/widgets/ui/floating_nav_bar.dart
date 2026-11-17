import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';

class NavDestination {
  const NavDestination({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Detached floating navigation bar: a dark ink pill over the light ground.
///
/// Icons only, with each destination's label kept as its tooltip and
/// accessibility label. A mint pill slides behind the active tab, and the
/// capture action is the amber button in the middle slot — the brightest
/// thing on the bar, because scanning a plate is the app's main action.
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

  static const double _barHeight = 68;

  /// The bar's own palette. It is the one dark surface in a light app, so it
  /// carries its own foreground colours rather than the theme's.
  static const Color _barColor = AppColors.inverseSurface;
  static const Color _idle = Color(0xFFC9D6CF);
  static const Color _activeFill = AppColors.primaryFixedDim;

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
            color: _barColor,
            borderRadius: AppRadius.pill,
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
              const insetX = 4.0;
              const insetY = 8.0;

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
                    // Hidden behind the capture slot, which has its own fill.
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: currentIndex == captureIndex ? 0 : 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _activeFill,
                          borderRadius: AppRadius.pill,
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
    return Semantics(
      button: true,
      selected: active,
      label: destination.label,
      excludeSemantics: true,
      child: Tooltip(
        message: destination.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.pill,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: active ? 1 : 0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              builder: (context, t, child) => Transform.scale(
                scale: 1 + 0.08 * t,
                child: child,
              ),
              child: Icon(
                destination.icon,
                size: 23,
                color: active ? AppColors.inverseSurface : FloatingNavBar._idle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Middle-slot capture action — the amber pill in the centre of the bar.
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
    return Semantics(
      button: true,
      label: 'Scan a meal',
      excludeSemantics: true,
      child: Center(
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
              width: 60,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer,
                borderRadius: AppRadius.pill,
              ),
              child:
                  Icon(widget.icon, color: AppColors.inverseSurface, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
