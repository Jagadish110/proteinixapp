import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Four corner brackets marking the capture area over the camera preview.
class ScanFrame extends StatelessWidget {
  const ScanFrame({
    super.key,
    this.color = Colors.white,
    this.cornerLength = 56,
    this.strokeWidth = 3,
    this.radius = 28,
    this.inset = 28,
  });

  final Color color;
  final double cornerLength;
  final double strokeWidth;
  final double radius;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _CornerPainter(
          color: color.withValues(alpha: 0.7),
          cornerLength: cornerLength,
          strokeWidth: strokeWidth,
          radius: radius,
          inset: inset,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({
    required this.color,
    required this.cornerLength,
    required this.strokeWidth,
    required this.radius,
    required this.inset,
  });

  final Color color;
  final double cornerLength;
  final double strokeWidth;
  final double radius;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;

    final l = inset, t = inset;
    final r = size.width - inset, b = size.height - inset;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(l, t + cornerLength)
        ..lineTo(l, t + radius)
        ..arcToPoint(Offset(l + radius, t), radius: Radius.circular(radius))
        ..lineTo(l + cornerLength, t),
      p,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(r - cornerLength, t)
        ..lineTo(r - radius, t)
        ..arcToPoint(Offset(r, t + radius), radius: Radius.circular(radius))
        ..lineTo(r, t + cornerLength),
      p,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(r, b - cornerLength)
        ..lineTo(r, b - radius)
        ..arcToPoint(Offset(r - radius, b), radius: Radius.circular(radius))
        ..lineTo(r - cornerLength, b),
      p,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(l + cornerLength, b)
        ..lineTo(l + radius, b)
        ..arcToPoint(Offset(l, b - radius), radius: Radius.circular(radius))
        ..lineTo(l, b - cornerLength),
      p,
    );
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}

/// Large concentric shutter button for the camera screen.
class ShutterButton extends StatefulWidget {
  const ShutterButton({super.key, required this.onTap, this.busy = false});

  final VoidCallback onTap;
  final bool busy;

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.busy ? null : widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: AppColors.onPrimaryFixedVariant, width: 4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow:
                    AppColors.glow(AppColors.primary, blur: 24, opacity: 0.4),
              ),
              child: widget.busy
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation(AppColors.onPrimary),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
