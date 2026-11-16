import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/theme/app_typography.dart';
import '../services/sleep_tracking_service.dart';

/// The one control for sleep tracking: on means "run every night between the
/// two times", off means nothing runs at all.
///
/// It replaced a Start/Stop button, which read as a stopwatch. "Track My Sleep"
/// was taken to mean sampling had begun there and then — so a card left on
/// through the afternoon looked like a tracker that never stopped, and the
/// hours it later reported looked like a day of idle phone time rather than a
/// night. Nothing in the control itself mentioned the schedule, and "Stop
/// Tracking" implied stopping was the user's job.
///
/// A switch plus the window underneath it says the true thing: the alarms open
/// the night at [SleepTrackingStatus.bedtime] and close it at
/// [SleepTrackingStatus.wake], and outside those the app is not running in any
/// sense. Shared by the dashboard card and the sleep screen so the two can
/// never describe the same switch differently.
class SleepCycleSwitch extends StatefulWidget {
  const SleepCycleSwitch({
    super.key,
    required this.status,
    required this.busy,
    required this.onChanged,
  });

  final SleepTrackingStatus status;

  /// A toggle in flight. Swaps the track for a spinner of the same footprint
  /// rather than disabling the row, so the control cannot be double-fired
  /// mid-write and the layout does not jump while it settles.
  final bool busy;

  final ValueChanged<bool> onChanged;

  @override
  State<SleepCycleSwitch> createState() => _SleepCycleSwitchState();
}

class _SleepCycleSwitchState extends State<SleepCycleSwitch> {
  bool _down = false;

  SleepTrackingStatus get _status => widget.status;

  /// Lime once the cycle is on, whichever phase it is in.
  ///
  /// Deliberately one colour rather than a per-phase palette: "armed" and
  /// "tracking" are both *on*, and giving them separate accents made the
  /// switch look like it was answering a different question from the one the
  /// user asked it. The phase difference belongs in [_caption], which can say
  /// it in words.
  Color get _accent =>
      _status.armed ? AppColors.secondary : AppColors.onSurfaceVariant;

  /// What the switch position means tonight, in the user's own times.
  ///
  /// Naming both ends in every state is the point: "armed" is the state people
  /// misread, and it is the one where the times are the whole explanation.
  String get _caption {
    final bed = SleepTrackingService.formatTime(_status.bedtime, 'bedtime');
    final wake = SleepTrackingService.formatTime(_status.wake, 'wake time');
    return switch (_status.phase) {
      SleepTrackingPhase.active => 'Tracking now · stops $wake',
      SleepTrackingPhase.armed => 'Starts $bed · stops $wake',
      SleepTrackingPhase.off => 'Off · nothing is tracked, day or night',
    };
  }

  @override
  Widget build(BuildContext context) {
    final on = _status.armed;

    return GestureDetector(
      // The whole row, not just the track. A settings row that toggles on tap
      // is the expected behaviour, and it gives the control a target far
      // larger than the 24dp track could offer on its own.
      onTapDown: widget.busy ? null : (_) => setState(() => _down = true),
      onTapCancel: widget.busy ? null : () => setState(() => _down = false),
      onTapUp: widget.busy ? null : (_) => setState(() => _down = false),
      onTap: widget.busy ? null : () => widget.onChanged(!on),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          decoration: BoxDecoration(
            // A lime wash when on, so the row reads as live at a glance rather
            // than only through a 24dp track at its right edge.
            color: on
                ? AppColors.secondary.withValues(alpha: 0.10)
                : AppColors.surfaceContainerHigh,
            borderRadius: AppRadius.pill,
            border: Border.all(
              color: on
                  ? AppColors.secondary.withValues(alpha: 0.45)
                  : AppColors.outline,
            ),
            // Only while a night is actually being measured. A glow through
            // every armed daytime hour would be the same overclaim the old
            // button made.
            boxShadow: _status.running
                ? AppColors.glow(AppColors.secondary, blur: 18, opacity: 0.18)
                : null,
          ),
          child: Row(
            children: [
              _Bubble(accent: _accent, on: on, glow: _status.running),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pinned to one line. Two would be the difference
                    // between fitting the carousel slot and overflowing it,
                    // and the height must not depend on how wide the font
                    // happens to render — widget tests substitute a far wider
                    // face than Hanken Grotesk, so an unpinned title measures
                    // as two lines there and one on the device.
                    Text('Sleep Cycle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyBold()),
                    const SizedBox(height: 2),
                    Text(
                      _caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelCaps(color: _accent, size: 9),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (widget.busy)
                const SizedBox(
                  width: _CycleTrack.width,
                  height: _CycleTrack.height,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  ),
                )
              else
                _CycleTrack(on: on),
            ],
          ),
        ),
      ),
    );
  }
}

/// The moon anchor, filling in as the cycle comes on.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.accent, required this.on, required this.glow});

  final Color accent;
  final bool on;
  final bool glow;

  /// Smaller than the 48dp [IconBubble] used elsewhere. The dashboard card
  /// lives in a fixed 312dp carousel slot sized by the *energy* card, and this
  /// row has to fit whatever the schedule and last night's figures leave.
  static const _size = 28.0;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: on ? 0.18 : 0.10),
          shape: BoxShape.circle,
          boxShadow:
              glow ? AppColors.glow(accent, blur: 14, opacity: 0.3) : null,
        ),
        child: Icon(
          on ? Icons.bedtime_rounded : Icons.bedtime_off_rounded,
          color: accent,
          size: 15,
        ),
      );
}

/// The track itself, drawn rather than themed.
///
/// A stock Material [Switch] is 48dp tall with its tap padding and 40 without,
/// which overflowed the carousel slot outright; scaling one down with a
/// FittedBox fitted, but rendered a control that was visibly a squashed
/// Material widget inside a card built from pills and glows. Drawing it costs
/// less height, matches the surrounding shape language, and can carry the same
/// lime the rest of the row uses.
class _CycleTrack extends StatelessWidget {
  const _CycleTrack({required this.on});

  final bool on;

  static const width = 42.0;
  static const height = 24.0;
  static const _thumb = 18.0;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: width,
        height: height,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: on ? AppColors.secondary : AppColors.track,
          borderRadius: AppRadius.pill,
          border: Border.all(
            color: on ? AppColors.secondary : AppColors.outline,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: _thumb,
            height: _thumb,
            decoration: BoxDecoration(
              color: on ? AppColors.onSecondary : AppColors.onSurfaceVariant,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
}
