import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import 'pill_button.dart';
import 'terra_card.dart';

/// Hydration card: a horizontal tank whose fill is a live animated wave in
/// [AppColors.hydrationBlue], with the volume read-out floating on top.
class HydrationCard extends StatelessWidget {
  const HydrationCard({
    super.key,
    required this.currentMl,
    required this.goalMl,
    required this.onAdd,
    this.increments = const [250, 500],
  });

  final int currentMl;
  final int goalMl;

  /// Called with the millilitres to add.
  final ValueChanged<int> onAdd;
  final List<int> increments;

  @override
  Widget build(BuildContext context) {
    final ratio = goalMl <= 0 ? 0.0 : (currentMl / goalMl).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();

    return TerraCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.waves_rounded,
                        color: AppColors.hydrationBlue, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('HYDRATION',
                          overflow: TextOverflow.ellipsis,
                          style: AppText.labelCaps(
                              color: AppColors.onSurface, size: 12)),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final ml in increments) ...[
                    if (ml != increments.first) const SizedBox(width: 6),
                    MiniPill(
                      label: '+$ml',
                      onTap: () => onAdd(ml),
                      foreground: AppColors.hydrationBlue,
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: WaveTank(
              fill: ratio,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: _format(currentMl),
                          style: AppText.bodyBold(color: AppColors.onSurface)
                              .copyWith(fontSize: 16),
                        ),
                        TextSpan(
                          text: ' / ${_format(goalMl)} ml',
                          style:
                              AppText.bodySm(color: AppColors.onSurfaceVariant),
                        ),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.6),
                        borderRadius: AppRadius.smR,
                      ),
                      child: Text('$pct%',
                          style: AppText.labelCaps(
                              color: AppColors.onSurface, size: 10)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _format(int v) {
    final s = v.toString();
    if (s.length <= 3) return s;
    final head = s.substring(0, s.length - 3);
    return '$head,${s.substring(s.length - 3)}';
  }
}

/// Rounded tank with a continuously animating sine wave at the fill line.
class WaveTank extends StatefulWidget {
  const WaveTank({
    super.key,
    required this.fill,
    this.child,
    this.color = AppColors.hydrationBlue,
    this.radius = AppRadius.lg,
  });

  /// 0.0 – 1.0 horizontal fill fraction.
  final double fill;
  final Widget? child;
  final Color color;
  final double radius;

  @override
  State<WaveTank> createState() => _WaveTankState();
}

class _WaveTankState extends State<WaveTank>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.4),
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The wave repaints every frame — isolate it from the card around it.
            RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: widget.fill.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, f, _) => AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) => CustomPaint(
                    painter: _WavePainter(
                      fill: f,
                      phase: _ctrl.value,
                      color: widget.color,
                      radius: widget.radius,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.child != null)
              Align(alignment: Alignment.center, child: widget.child!),
          ],
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.fill,
    required this.phase,
    required this.color,
    required this.radius,
  });

  final double fill;
  final double phase;
  final Color color;

  /// Corner radius of the tank, so the fill can match it exactly at 100%.
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (fill <= 0) return;

    final edge = size.width * fill;

    // The fill is a rounded rectangle in its own right, not a bare rect left to
    // the tank's ClipRRect to tidy up. The clip only ever rounded the two outer
    // corners it happened to touch, so a part-full tank ended in a hard
    // vertical edge and a full one had its crest sliced flat against the corner.
    //
    // Radius is clamped to half the fill's own width and height: a nearly-empty
    // tank is a small blue nub, and an unclamped radius would make it render as
    // a lens or vanish altogether.
    final r = math.min(radius, math.min(edge / 2, size.height / 2));
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, edge, size.height),
      Radius.circular(r),
    );
    canvas.drawRRect(body, Paint()..color = color.withValues(alpha: 0.40));

    // The wave now lives *inside* the fill as a moving highlight rather than
    // defining its right-hand edge. It keeps the water feeling alive without
    // ever being the thing that decides the silhouette — which is what let it
    // overshoot the corner before.
    canvas.save();
    canvas.clipRRect(body);
    const amplitude = 7.0;
    const band = 12.0;
    final crest = Path()..moveTo(edge, 0);
    for (double y = 0; y <= size.height; y += 2) {
      final t = (y / size.height) * 2 * math.pi;
      crest.lineTo(
        edge - band + math.sin(t + phase * 2 * math.pi) * amplitude,
        y,
      );
    }
    crest.lineTo(edge, size.height);
    crest.close();
    canvas.drawPath(crest, Paint()..color = color.withValues(alpha: 0.30));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.fill != fill ||
      old.phase != phase ||
      old.color != color ||
      old.radius != radius;
}
