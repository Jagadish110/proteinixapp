import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Compact floating mic button for the dashboard.
///
/// Idles with a slow breathing halo and a barely-there scale so it reads as
/// "alive" without competing with the content, and squashes on press.
class MicFab extends StatefulWidget {
  const MicFab({
    super.key,
    required this.onTap,
    this.size = 56,
    this.color = AppColors.primary,
    this.iconColor = AppColors.onPrimary,
  });

  final VoidCallback onTap;
  final double size;
  final Color color;
  final Color iconColor;

  @override
  State<MicFab> createState() => _MicFabState();
}

class _MicFabState extends State<MicFab> with SingleTickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  bool _down = false;

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final halo = widget.size * 1.7;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: RepaintBoundary(
        child: SizedBox(
          width: halo,
          height: halo,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _breathe,
                builder: (context, _) => CustomPaint(
                  size: Size.square(halo),
                  painter: _BreathPainter(
                    phase: _breathe.value,
                    color: widget.color,
                    coreRadius: widget.size / 2,
                  ),
                ),
              ),
              AnimatedScale(
                scale: _down ? 0.9 : 1,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    boxShadow:
                        AppColors.glow(widget.color, blur: 22, opacity: 0.4),
                  ),
                  child: Icon(Icons.mic_rounded,
                      color: widget.iconColor, size: widget.size * 0.42),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreathPainter extends CustomPainter {
  _BreathPainter({
    required this.phase,
    required this.color,
    required this.coreRadius,
  });

  final double phase;
  final Color color;
  final double coreRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;

    // Two rings, half a cycle apart, so one is always fading in.
    for (var i = 0; i < 2; i++) {
      final t = (phase + i / 2) % 1.0;
      final radius = coreRadius + (maxRadius - coreRadius) * t;
      final fade = (1 - t) * 0.30;
      if (fade <= 0.01) continue;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(_BreathPainter old) =>
      old.phase != phase || old.color != color;
}
