import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'progress_ring.dart';

/// The launch animation: the Proteinix mark unpacking itself into the day.
///
/// The logo's four arcs and the dashboard's four goal rings are the same four
/// shapes — the mark simply draws them as a tight half-turn stack beside the P
/// stem. This plays that as one continuous move: the stem fades, the arcs swing
/// open from a half turn to a full one, drift out to the ring stack's radii,
/// take on each metric's colour, and finally wind back to where that metric
/// actually stands today.
///
/// It is drawn rather than cross-faded from the icon PNG on purpose. The arcs
/// have to be *interpolated* — radius, sweep and colour all move together — and
/// an image can only be scaled.
class LogoBloom extends StatefulWidget {
  const LogoBloom({
    super.key,
    required this.rings,
    this.size = 168,
    this.duration = const Duration(milliseconds: 1750),
    this.onComplete,
    this.autoplay = true,
  });

  /// The day's goals, outermost first — the same list the dashboard draws.
  /// Empty (or all unmeasured) settles on bare tracks rather than inventing
  /// progress nobody has made.
  final List<RingSpec> rings;

  final double size;
  final Duration duration;
  final VoidCallback? onComplete;

  /// False holds the painter at `t = 0` — the bare P mark, no bloom.
  ///
  /// Splash uses this: navigation there fires as soon as [_SplashState._route]
  /// resolves, which for an already-signed-in user with a cached profile can
  /// land well before the bloom finishes opening. Cutting the animation off
  /// mid-morph froze on whatever half-open arc shape the timing happened to
  /// land on — which reads as a broken or wrong icon, not a loading state.
  /// The mark has no mid-state that isn't the bloom itself, so the fix is not
  /// playing it where nothing is watching it reach the end.
  final bool autoplay;

  @override
  State<LogoBloom> createState() => _LogoBloomState();
}

class _LogoBloomState extends State<LogoBloom>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.autoplay) return;
    _ctrl.forward().whenComplete(() {
      if (mounted) widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => CustomPaint(
            painter: _BloomPainter(
              t: _ctrl.value,
              values: [
                for (final r in widget.rings)
                  r.hasData ? r.ratio.clamp(0.0, 1.0).toDouble() : 0.0,
              ],
              known: [for (final r in widget.rings) r.hasData],
              ringColors: [for (final r in widget.rings) r.color],
            ),
          ),
        ),
      ),
    );
  }
}

class _BloomPainter extends CustomPainter {
  _BloomPainter({
    required this.t,
    required this.values,
    required this.known,
    required this.ringColors,
  });

  /// 0–1 across the whole animation.
  final double t;
  final List<double> values;
  final List<bool> known;
  final List<Color> ringColors;

  /// The mark's arcs, outermost first, as they appear in the icon.
  static const _iconColors = [
    Color(0xFFB4E938), // lime
    Color(0xFFFF6B2C), // orange
    Color(0xFFFF4F7B), // pink
    Color(0xFF19D3D8), // cyan
  ];

  /// Ring order on the dashboard is steps, macros, water, sleep — which is not
  /// the mark's colour order, so the inner two change hue on the way out. That
  /// is the point of the move rather than a mismatch to hide: the arcs are
  /// taking on a meaning they did not have as a logo.
  static const _fallbackRingColors = [
    AppColors.secondary,
    AppColors.primary,
    AppColors.water,
    AppColors.tertiary,
  ];

  // The stem clears out early and fast. Held any longer it is still painting
  // at low opacity while the arcs are halfway to full rings, and the hook
  // reads as a white smear across them rather than as part of a letter.
  static const _stemFade = Interval(0.14, 0.34, curve: Curves.easeIn);
  static const _open = Interval(0.20, 0.60, curve: Curves.easeInOutCubic);
  static const _fill = Interval(0.58, 1.0, curve: Curves.easeOutCubic);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = (Offset.zero & size).center;
    final dim = math.min(size.width, size.height);

    // Ring-stack geometry, matched to ProgressRings so the bloom lands exactly
    // where the dashboard would draw it.
    const stroke = 9.0;
    const gap = 4.0;
    final outer = (dim - stroke) / 2;

    final opened = _open.transform(t);
    final filled = _fill.transform(t);
    final stem = 1 - _stemFade.transform(t);

    // The P's bowl sits right of the stem and rises as it opens.
    final markCentre = Offset(
      centre.dx + dim * 0.06 * (1 - opened),
      centre.dy - dim * 0.02 * (1 - opened),
    );
    final origin = Offset.lerp(markCentre, centre, opened)!;

    for (var i = 0; i < 4; i++) {
      final ringR = outer - i * (stroke + gap);
      if (ringR <= stroke / 2) break;

      // Arcs start tight and nested, then drift out to the ring radii.
      //
      // The radius step has to exceed the stroke or the four arcs overlap into
      // one thick band and the mark stops reading as four separate things —
      // which is the whole premise of the animation.
      final markR = dim * 0.255 - i * dim * 0.052;
      final markStroke = dim * 0.038;
      final radius = ui(markR, ringR, opened);
      final width = ui(markStroke, stroke, opened);

      final colour = Color.lerp(
        _iconColors[i],
        i < ringColors.length ? ringColors[i] : _fallbackRingColors[i],
        opened,
      )!;

      final measured = i < known.length ? known[i] : false;
      final value = i < values.length ? values[i] : 0.0;

      // The track belongs to the ring, not to the mark, so it arrives late.
      // Fading it in with the opening drew a dark disc behind arcs that were
      // still logo-sized, and the middle of the animation turned to mud.
      final trackIn = ((opened - 0.62) / 0.38).clamp(0.0, 1.0);
      if (trackIn > 0.01) {
        canvas.drawCircle(
          origin,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..color = AppColors.track
                .withValues(alpha: trackIn * (measured ? 1 : 0.35)),
        );
      }

      // Sweep: a half turn in the mark, a full turn once open, then wound back
      // to the day's actual figure. Anything unmeasured stops at the full ring
      // and dims with the track — an empty arc would read as a goal missed
      // rather than a goal unmeasured.
      final full = math.pi * (1 + opened);
      final target = measured ? 2 * math.pi * value : full;
      final sweep = ui(full, target, filled);
      if (sweep.abs() < 0.001) continue;

      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radius),
        // The mark's bowl opens to the right; a ring starts at twelve o'clock.
        ui(-math.pi / 2, -math.pi / 2, opened),
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color =
              colour.withValues(alpha: measured || filled < 1 ? 1.0 : 0.45),
      );
    }

    if (stem > 0.004) _paintStem(canvas, size, centre, dim, stem, opened);
  }

  /// The P's upright, which fades as the arcs leave.
  void _paintStem(Canvas canvas, Size size, Offset centre, double dim,
      double opacity, double opened) {
    final w = dim * 0.052;
    final x = centre.dx - dim * 0.20 - dim * 0.10 * opened;
    final top = centre.dy - dim * 0.26;
    final bottom = centre.dy + dim * 0.30;

    canvas.drawLine(
      Offset(x, top),
      Offset(x, bottom),
      Paint()
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: opacity),
    );

    // The hook over the bowl, which is what makes it read as a P rather than a
    // bar beside some rings.
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(x + dim * 0.085, top), radius: dim * 0.085),
      math.pi,
      math.pi * 0.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: opacity),
    );
  }

  /// Shorthand for the lerps above, which are otherwise unreadable inline.
  static double ui(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(_BloomPainter old) => old.t != t;
}
