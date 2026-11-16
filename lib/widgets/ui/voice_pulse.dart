import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Mic button that breathes with the speaker's voice.
///
/// Three concentric halos expand outward on a continuous loop; their radius and
/// opacity are scaled by the live sound level so the ring visibly "pumps" when
/// the user talks and settles to a slow idle pulse when they stop.
class VoicePulse extends StatefulWidget {
  const VoicePulse({
    super.key,
    required this.listening,
    required this.onTap,
    this.level = 0,
    this.size = 96,
    this.color = AppColors.primary,
    this.activeColor = AppColors.secondary,
  });

  final bool listening;
  final VoidCallback onTap;

  /// Normalised 0.0 – 1.0 loudness.
  final double level;
  final double size;
  final Color color;
  final Color activeColor;

  @override
  State<VoicePulse> createState() => _VoicePulseState();
}

class _VoicePulseState extends State<VoicePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  /// Smoothed level so the halo eases between mic readings instead of jumping.
  double _smoothed = 0;

  @override
  void initState() {
    super.initState();
    if (widget.listening) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(VoicePulse old) {
    super.didUpdateWidget(old);
    if (widget.listening && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.listening && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
      _smoothed = 0;
    }
    _smoothed = _smoothed + (widget.level.clamp(0.0, 1.0) - _smoothed) * 0.35;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.listening ? widget.activeColor : widget.color;
    final outer = widget.size * 2.1;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: outer,
        height: outer,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.listening)
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) => CustomPaint(
                    size: Size.square(outer),
                    painter: _HaloPainter(
                      phase: _ctrl.value,
                      level: _smoothed,
                      color: tint,
                      coreRadius: widget.size / 2,
                    ),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: widget.size * (1 + _smoothed * 0.10),
              height: widget.size * (1 + _smoothed * 0.10),
              decoration: BoxDecoration(
                color: tint,
                shape: BoxShape.circle,
                boxShadow: AppColors.glow(tint,
                    blur: 26 + _smoothed * 20, opacity: 0.35),
              ),
              child: Icon(
                widget.listening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                color: widget.listening
                    ? AppColors.onSecondary
                    : AppColors.onPrimary,
                size: widget.size * 0.38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({
    required this.phase,
    required this.level,
    required this.color,
    required this.coreRadius,
  });

  final double phase;
  final double level;
  final Color color;
  final double coreRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;

    for (var i = 0; i < 3; i++) {
      // Stagger the three halos a third of a cycle apart.
      final t = (phase + i / 3) % 1.0;
      final radius =
          coreRadius + (maxRadius - coreRadius) * t * (0.55 + level * 0.45);
      final fade = (1 - t) * (0.25 + level * 0.45);
      if (fade <= 0.01) continue;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + level * 2
          ..color = color.withValues(alpha: fade.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.phase != phase || old.level != level || old.color != color;
}

/// Live bar-graph visualiser shown under the transcript while recording.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({
    super.key,
    required this.listening,
    this.level = 0,
    this.bars = 28,
    this.height = 48,
    this.color = AppColors.secondary,
  });

  final bool listening;
  final double level;
  final int bars;
  final double height;
  final Color color;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => CustomPaint(
            size: Size(double.infinity, widget.height),
            painter: _WaveformPainter(
              phase: _ctrl.value,
              level: widget.listening ? widget.level.clamp(0.0, 1.0) : 0,
              bars: widget.bars,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.phase,
    required this.level,
    required this.bars,
    required this.color,
  });

  final double phase;
  final double level;
  final int bars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / bars;
    final barWidth = slot * 0.45;
    final mid = size.height / 2;

    for (var i = 0; i < bars; i++) {
      // Two offset sine waves keep neighbouring bars from moving in lockstep.
      final t = (i / bars) * 2 * math.pi;
      final wave = math.sin(t * 2 + phase * 2 * math.pi) * 0.5 +
          math.sin(t * 3.7 - phase * 2 * math.pi) * 0.5;
      final amplitude = (0.12 + level * 0.88) * wave.abs();
      final h = (mid * amplitude).clamp(2.0, mid);
      final x = i * slot + (slot - barWidth) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h, barWidth, h * 2),
          Radius.circular(barWidth),
        ),
        Paint()..color = color.withValues(alpha: 0.35 + level * 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.phase != phase || old.level != level || old.color != color;
}
