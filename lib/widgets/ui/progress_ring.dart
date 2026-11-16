import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Circular biometric gauge — the app's signature "living data" element.
///
/// Always paints a full track in [AppColors.track] so the remaining goal stays
/// visible, then animates the coloured arc in from zero.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 64,
    this.strokeWidth = 5,
    this.trackColor = AppColors.track,
    this.center,
    this.glow = false,
  });

  /// 0.0 – 1.0. Values above 1 are clamped.
  final double value;
  final Color color;
  final double size;
  final double strokeWidth;
  final Color trackColor;
  final Widget? center;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);

    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: target),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => CustomPaint(
            painter: _RingPainter(
              value: v,
              color: color,
              trackColor: trackColor,
              strokeWidth: strokeWidth,
              glow: glow,
            ),
            child: child,
          ),
          // Passed through the builder so the centre label isn't rebuilt on
          // every animation tick.
          child: center == null ? null : Center(child: center),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    required this.glow,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    if (value <= 0) return;

    if (glow) {
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * value, false, halo);
    }

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}

/// One macro's worth of data for [MacroGaugeRow].
class MacroSpec {
  const MacroSpec({
    required this.label,
    required this.current,
    required this.goal,
    required this.color,
    required this.icon,
    this.unit = 'g',
  });

  final String label;
  final double current;
  final double goal;
  final Color color;
  final IconData icon;
  final String unit;
}

/// Evenly spaced row of macro gauges.
///
/// The ring diameter is derived from the width actually available rather than
/// being hard-coded, so the gauges keep a real gutter between them on narrow
/// screens instead of colliding.
class MacroGaugeRow extends StatelessWidget {
  const MacroGaugeRow({
    super.key,
    required this.macros,
    this.gap = 12,
    this.maxRingSize = 68,
    this.minRingSize = 44,
  });

  final List<MacroSpec> macros;
  final double gap;
  final double maxRingSize;
  final double minRingSize;

  @override
  Widget build(BuildContext context) {
    if (macros.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth =
            (constraints.maxWidth - gap * (macros.length - 1)) / macros.length;
        final ringSize = columnWidth.clamp(minRingSize, maxRingSize).toDouble();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < macros.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(
                child: MacroGauge(
                  label: macros[i].label,
                  current: macros[i].current,
                  goal: macros[i].goal,
                  color: macros[i].color,
                  icon: macros[i].icon,
                  unit: macros[i].unit,
                  size: ringSize,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Ring + caption block used in the dashboard's 4-up macro grid.
class MacroGauge extends StatelessWidget {
  const MacroGauge({
    super.key,
    required this.label,
    required this.current,
    required this.goal,
    required this.color,
    required this.icon,
    this.size = 62,
    this.unit = 'g',
  });

  final String label;
  final double current;
  final double goal;
  final Color color;
  final IconData icon;
  final double size;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final ratio = goal <= 0 ? 0.0 : current / goal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProgressRing(
          value: ratio,
          color: color,
          size: size,
          strokeWidth: 5,
          center: Icon(icon, color: color, size: (size * 0.32).clamp(14, 22)),
        ),
        const SizedBox(height: 8),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.labelCaps(size: 9),
        ),
        const SizedBox(height: 2),
        // Value can be long ("180/260g") — shrink rather than overflow.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${current.round()}/${goal.round()}$unit',
            maxLines: 1,
            style: AppText.labelCaps(color: AppColors.onSurface, size: 10),
          ),
        ),
      ],
    );
  }
}

/// One metric's worth of data for [ProgressRings].
class RingSpec {
  const RingSpec({
    required this.label,
    required this.current,
    required this.goal,
    required this.color,
    this.unit = '',
    this.hasData = true,
  });

  final String label;
  final double current;
  final double goal;
  final Color color;
  final String unit;

  /// False when the metric wasn't measured at all, as opposed to measuring
  /// zero. Sleep is the case that forced the distinction: a night the guard
  /// was switched off records 0 hours, and drawing that as an empty ring reads
  /// as "you slept badly" rather than "we don't know".
  final bool hasData;

  /// 0.0 – 1.0+; the painter clamps.
  double get ratio => goal <= 0 ? 0 : current / goal;

  /// What is still owed on the goal, floored at zero.
  double get remaining => (goal - current).clamp(0, double.infinity).toDouble();
}

/// Concentric activity rings — one goal per ring, outermost first.
///
/// Each ring paints a full [AppColors.track] circle so the shortfall stays
/// legible next to the covered arc.
class ProgressRings extends StatelessWidget {
  const ProgressRings({
    super.key,
    required this.rings,
    this.size = 96,
    this.strokeWidth = 7,
    this.gap = 3.5,
    this.center,
  });

  final List<RingSpec> rings;
  final double size;
  final double strokeWidth;

  /// Clear space between one ring's stroke and the next.
  final double gap;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    if (rings.isEmpty) return SizedBox.square(dimension: size);

    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => CustomPaint(
            painter: _RingsPainter(
              values: [
                for (final r in rings)
                  r.hasData ? r.ratio.clamp(0.0, 1.0).toDouble() * t : 0.0,
              ],
              colors: [for (final r in rings) r.color],
              known: [for (final r in rings) r.hasData],
              strokeWidth: strokeWidth,
              gap: gap,
            ),
            child: child,
          ),
          child: center == null ? null : Center(child: center),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({
    required this.values,
    required this.colors,
    required this.known,
    required this.strokeWidth,
    required this.gap,
  });

  final List<double> values;
  final List<Color> colors;

  /// Per-ring: whether the metric was measured at all. An unmeasured ring
  /// draws a fainter track and no arc, so it reads as absent rather than as a
  /// goal missed entirely.
  final List<bool> known;
  final double strokeWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = (Offset.zero & size).center;
    final outer = (math.min(size.width, size.height) - strokeWidth) / 2;

    for (var i = 0; i < values.length; i++) {
      final radius = outer - i * (strokeWidth + gap);
      // Too many rings for the diameter — stop rather than paint inside out.
      if (radius <= strokeWidth / 2) break;

      final measured = i >= known.length || known[i];
      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = measured
            ? AppColors.track
            : AppColors.track.withValues(alpha: 0.35);
      canvas.drawCircle(centre, radius, track);

      if (!measured || values[i] <= 0) continue;
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = colors[i];
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        -math.pi / 2,
        2 * math.pi * values[i],
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      !listEquals(old.values, values) ||
      !listEquals(old.colors, colors) ||
      !listEquals(old.known, known) ||
      old.strokeWidth != strokeWidth ||
      old.gap != gap;
}
