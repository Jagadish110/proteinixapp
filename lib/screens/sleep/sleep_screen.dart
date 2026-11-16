import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/require_account.dart';
import '../../core/utils/technical_issue.dart';
import '../../models/daily_log.dart';
import '../../models/sleep_result.dart';
import '../../providers/auth_provider.dart';
import '../../providers/daily_log_provider.dart';
import '../../services/local_db_service.dart';
import '../../services/sleep_tracking_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/sleep_cycle_switch.dart';
import '../../widgets/ui/ui.dart';

/// The full sleep record: last night in detail, the week behind it, and the
/// schedule.
///
/// The dashboard card stays the control — set two times, switch it on — and
/// this is where the reading happens. Splitting them that way keeps the
/// dashboard from growing a chart nobody looks at daily, and gives the numbers
/// somewhere to live that isn't a 312px carousel slot.
class SleepScreen extends ConsumerStatefulWidget {
  const SleepScreen({super.key});

  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen>
    with WidgetsBindingObserver {
  SleepTrackingStatus _status = SleepTrackingStatus.defaults;
  SleepNight _night = SleepNight.none;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final status = await SleepTrackingService.status();
    final night = await SleepTrackingService.lastNight();
    if (!mounted) return;
    setState(() {
      _status = status;
      _night = night;
    });
  }

  Future<void> _pickTime({required bool bedtime}) async {
    final current = bedtime ? _status.bedtime : _status.wake;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? (bedtime ? 22 : 6),
        minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 30,
      ),
      // Without this, the picker inherits the phone's system clock format —
      // a device set to 24-hour time got a 24-hour dial with no AM/PM toggle
      // at all. Every time in this screen renders 12-hour with AM/PM
      // (formatTime below, the "10:30 PM" defaults), so the picker that sets
      // them needs to match regardless of the device's own clock setting.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null) return;

    final hhmm = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    final nextBed = bedtime ? hhmm : _status.bedtime;
    final nextWake = bedtime ? _status.wake : hhmm;

    if (nextBed == nextWake) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sleep and wake times must differ.')),
      );
      return;
    }

    final uid = SupabaseService.currentUserId;
    try {
      // Re-arm rather than just save when tracking is on: the alarms already
      // scheduled point at the old times, so saving alone would show the new
      // window here while the sampler still ran on the previous one.
      if (_status.armed) {
        await SleepTrackingService.start(
            bedtime: nextBed, wake: nextWake, userId: uid);
      } else {
        await SleepTrackingService.saveSchedule(
            bedtime: nextBed, wake: nextWake, userId: uid);
      }
    } catch (_) {
      // Non-Android host; the times are still saved locally.
    }
    await _load();
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    if (!await requireAccount(context, action: 'track your sleep')) return;
    setState(() => _busy = true);
    final uid = SupabaseService.currentUserId;
    try {
      if (on) {
        await SleepTrackingService.start(
            bedtime: _status.bedtime, wake: _status.wake, userId: uid);
      } else {
        await SleepTrackingService.stop(userId: uid);
      }
    } catch (e, s) {
      if (mounted) {
        showTechnicalIssueSnack(
          context,
          action: on ? 'start sleep tracking' : 'stop sleep tracking',
          reportContext: 'sleep_toggle',
          error: e,
          stack: s,
        );
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  /// Last night as a scored result, preferring the log over the live reading.
  ///
  /// The log is what was actually saved and may hold a Health Connect figure
  /// that beats the sampler's estimate; the live reading covers the window
  /// still in progress, before anything has been written.
  SleepResult? _lastNight(DailyLog? log) {
    if (log != null && log.sleepHrs > 0) {
      return SleepResult(
        sleepHours: log.sleepHrs,
        interruptions: log.sleepInterruptions,
        phonePickups: log.phonePickups,
        date: log.date,
        sleepStart: log.sleepStart,
        sleepEnd: log.sleepEnd,
      );
    }
    if (_night.isEmpty) return null;
    return SleepResult(
      sleepHours: _night.hours,
      interruptions: _night.interruptions,
      phonePickups: _night.phonePickups,
      date: _night.date!,
      sleepStart: _night.sleepStart,
      sleepEnd: _night.sleepEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = AppDateUtils.toDateOnly(DateTime.now());
    final log = ref.watch(dailyLogProvider(today));
    final profile = ref.watch(profileProvider).value;
    final result = _lastNight(log);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TerraAppBar(title: 'Sleep'),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        backgroundColor: AppColors.surfaceContainer,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs,
              AppSpacing.page, AppSpacing.navClearance),
          children: [
            _HeroCard(
              result: result,
              status: _status,
              night: _night,
              goalHrs: profile?.sleepGoalHrs ?? 8,
            ),
            const SizedBox(height: AppSpacing.gutter),
            if (result != null) ...[
              _StatsGrid(result: result),
              const SizedBox(height: AppSpacing.gutter),
            ],
            _ScheduleCard(
              status: _status,
              busy: _busy,
              onPickBedtime: () => _pickTime(bedtime: true),
              onPickWake: () => _pickTime(bedtime: false),
              onToggle: _toggle,
            ),
            const SizedBox(height: AppSpacing.gutter),
            _WeeklyChart(goalHrs: profile?.sleepGoalHrs ?? 8),
            const SizedBox(height: AppSpacing.sm),
            const _Disclaimer(),
          ],
        ),
      ),
    );
  }
}

// ── Card 1: last night ────────────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.result,
    required this.status,
    required this.night,
    required this.goalHrs,
  });

  final SleepResult? result;
  final SleepTrackingStatus status;
  final SleepNight night;
  final double goalHrs;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return TerraCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('LAST NIGHT', color: AppColors.sleep),
            const SizedBox(height: AppSpacing.sm),
            Text(
              // A night that was watched and came back under the floor is not
              // a night that went unwatched, and telling the user "nothing
              // recorded yet" when 37 minutes had in fact been measured read
              // as the tracker being broken. Name the figure and the bar.
              night.belowMinimum
                  ? 'Watched ${night.observedLabel} of sleep so far — a night '
                      'has to reach ${night.minimumLabel} before it counts, so '
                      'there is nothing to score yet.'
                  : status.armed
                      ? 'Nothing recorded yet. Your first night will appear here '
                          'after ${SleepTrackingService.formatTime(status.wake, 'your wake time')}.'
                      : 'Sleep tracking is off. Switch it on below and your first '
                          'night will appear here tomorrow morning.',
              style: AppText.body(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final vsGoal = r.sleepHours - goalHrs;
    final scoreColor = _scoreColor(r.sleepScore);

    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel('LAST NIGHT', color: AppColors.sleep),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.15),
                  borderRadius: AppRadius.pill,
                  border: Border.all(color: scoreColor.withValues(alpha: 0.5)),
                ),
                child: Text('${r.sleepScore}/100 · ${r.scoreLabel}',
                    style: AppText.labelCaps(color: scoreColor, size: 10)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(r.durationLabel, style: AppText.display()),
          ),
          const SizedBox(height: 2),
          Text(
            switch (vsGoal) {
              // Half an hour either way is not a shortfall worth naming; a goal
              // reported as missed by six minutes reads as nagging.
              > -0.5 && < 0.5 =>
                'On target (${goalHrs.toStringAsFixed(0)}h goal)',
              < 0 => '${_short(-vsGoal)} under your '
                  '${goalHrs.toStringAsFixed(0)}h goal',
              _ => '${_short(vsGoal)} over your '
                  '${goalHrs.toStringAsFixed(0)}h goal',
            },
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(color: AppColors.outline, height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _Moment(
                  icon: Icons.bedtime_rounded,
                  label: 'FELL ASLEEP',
                  // Falls back to the scheduled time on nights recorded before
                  // the observed timestamps existed.
                  value: _clock(r.sleepStart) ??
                      SleepTrackingService.formatTime(status.bedtime, '—'),
                  exact: r.sleepStart != null,
                  color: AppColors.sleep,
                ),
              ),
              Expanded(
                child: _Moment(
                  icon: Icons.wb_sunny_rounded,
                  label: 'WOKE UP',
                  value: _clock(r.sleepEnd) ??
                      SleepTrackingService.formatTime(status.wake, '—'),
                  exact: r.sleepEnd != null,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (night.status == SleepNightStatus.partial && !night.isEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.tertiary, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Checks stopped early last night, so this is a minimum. '
                    'Exempting Proteinix from battery optimisation helps.',
                    style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _short(double hours) {
    final mins = (hours * 60).round();
    return mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m';
  }

  static String? _clock(DateTime? at) {
    if (at == null) return null;
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    return '${h.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')} '
        '${at.hour < 12 ? 'AM' : 'PM'}';
  }
}

Color _scoreColor(int score) => switch (score) {
      >= 70 => AppColors.secondary,
      >= 55 => AppColors.primary,
      _ => AppColors.error,
    };

class _Moment extends StatelessWidget {
  const _Moment({
    required this.icon,
    required this.label,
    required this.value,
    required this.exact,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Observed, rather than the scheduled time standing in for it. Marked so a
  /// fallback is never mistaken for a measurement.
  final bool exact;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(exact ? label : '$label (SET)',
                  style: AppText.labelCaps(size: 9)),
              const SizedBox(height: 1),
              Text(value, style: AppText.bodyBold()),
            ],
          ),
        ],
      );
}

// ── Card 2: the numbers ───────────────────────────────────────────────────
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.result});

  final SleepResult result;

  @override
  Widget build(BuildContext context) {
    final awake = result.timeAwake;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.gutter,
      crossAxisSpacing: AppSpacing.gutter,
      // Matched to what StatTile actually needs: icon, label and a 22pt value
      // plus card padding come to ~116dp, and at this width 1.7 gave it 89 —
      // so every tile clipped its own value off the bottom. Kept in step with
      // the profile screen's grid, which uses the same tile.
      childAspectRatio: 1.3,
      children: [
        StatTile(
          label: 'Wake-ups',
          value: '${result.interruptions}',
          icon: Icons.nights_stay_rounded,
          accent: AppColors.sleep,
        ),
        StatTile(
          label: 'Awake in bed',
          value: awake == null ? '—' : '${awake.inMinutes}',
          unit: awake == null ? null : 'min',
          icon: Icons.hourglass_bottom_rounded,
          accent: AppColors.primary,
        ),
        StatTile(
          label: 'Phone pickups',
          value: '${result.phonePickups}',
          icon: Icons.phone_android_rounded,
          accent: AppColors.secondary,
        ),
        StatTile(
          label: 'Sleep score',
          value: '${result.sleepScore}',
          unit: '/100',
          icon: Icons.auto_awesome_rounded,
          accent: _scoreColor(result.sleepScore),
        ),
      ],
    );
  }
}

// ── Card 3: the schedule ──────────────────────────────────────────────────
class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.status,
    required this.busy,
    required this.onPickBedtime,
    required this.onPickWake,
    required this.onToggle,
  });

  final SleepTrackingStatus status;
  final bool busy;
  final VoidCallback onPickBedtime;
  final VoidCallback onPickWake;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('SCHEDULE',
              color: AppColors.primary,
              trailing:
                  Text(status.phase.label, style: AppText.labelCaps(size: 9))),
          const SizedBox(height: AppSpacing.sm),
          _row(
            icon: Icons.bedtime_rounded,
            label: 'Bedtime',
            value: SleepTrackingService.formatTime(status.bedtime, '10:30 PM'),
            onTap: onPickBedtime,
          ),
          const Divider(color: AppColors.outline, height: 20),
          _row(
            icon: Icons.wb_sunny_rounded,
            label: 'Wake time',
            value: SleepTrackingService.formatTime(status.wake, '06:30 AM'),
            onTap: onPickWake,
          ),
          const Divider(color: AppColors.outline, height: 20),
          // The same control the dashboard card carries, so the two can never
          // read as different switches for different things.
          SleepCycleSwitch(
            status: status,
            busy: busy,
            onChanged: busy ? (_) {} : onToggle,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Nothing runs outside these hours — the night opens at your '
            'bedtime and closes itself at your wake time.',
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            Icon(icon, color: AppColors.tertiary, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppText.body())),
            Text(value, style: AppText.bodyBold()),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined,
                color: AppColors.onSurfaceVariant, size: 14),
          ],
        ),
      );
}

// ── Card 4: the week ──────────────────────────────────────────────────────
/// Seven days of sleep, colour-coded against what the hours mean.
///
/// Drawn from Hive directly rather than through a provider: this is seven
/// point reads of local data, and a provider per day would be seven rebuild
/// subscriptions for a chart that only changes once a night.
class _WeeklyChart extends ConsumerWidget {
  const _WeeklyChart({required this.goalHrs});

  final double goalHrs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-read whenever anything writes, so a night recorded while this screen
    // is open lands on the chart.
    ref.watch(dataRevisionProvider);

    final uid = SupabaseService.currentUserId;
    final today = AppDateUtils.toDateOnly(DateTime.now());
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));

    final hours = days.map((d) {
      if (uid == null) return 0.0;
      return LocalDBService.getDailyLog(uid, d)?.sleepHrs ?? 0.0;
    }).toList();

    final measured = hours.where((h) => h > 0).toList();
    final average = measured.isEmpty
        ? 0.0
        : measured.reduce((a, b) => a + b) / measured.length;

    // Always at least the goal, so the goal line never sits on the ceiling and
    // a run of short nights doesn't rescale into looking like good ones.
    final peak = [
      goalHrs,
      ...hours,
    ].reduce((a, b) => a > b ? a : b);

    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('LAST 7 NIGHTS',
              color: AppColors.secondary,
              trailing: Text(
                measured.isEmpty
                    ? 'NO DATA'
                    : 'AVG ${average.toStringAsFixed(1)}H',
                style: AppText.labelCaps(size: 9),
              )),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: _Bar(
                      hours: hours[i],
                      peak: peak,
                      day: days[i],
                      isToday: i == days.length - 1,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _Key(color: AppColors.secondary, label: '7–9h'),
              _Key(color: AppColors.primary, label: '6–7h'),
              _Key(color: AppColors.error, label: 'Under 6h'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.hours,
    required this.peak,
    required this.day,
    required this.isToday,
  });

  final double hours;
  final double peak;
  final DateTime day;
  final bool isToday;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    // A night with no data is a gap in the record, not zero hours of sleep —
    // so it draws as an empty track rather than a bar of zero height, which
    // would read identically to "you did not sleep".
    final measured = hours > 0;
    final colour = switch (hours) {
      >= 7 => AppColors.secondary,
      >= 6 => AppColors.primary,
      > 0 => AppColors.error,
      _ => AppColors.outline,
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(measured ? hours.toStringAsFixed(1) : '–',
            style: AppText.labelCaps(
                size: 9,
                color: measured ? colour : AppColors.onSurfaceVariant)),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final fraction = peak <= 0 ? 0.0 : (hours / peak).clamp(0.0, 1.0);
              return Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 14,
                  // Floored so a very short night is still a visible mark.
                  height: measured
                      ? (box.maxHeight * fraction).clamp(6.0, box.maxHeight)
                      : box.maxHeight,
                  decoration: BoxDecoration(
                    color: measured
                        ? colour
                        : AppColors.outline.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _labels[day.weekday - 1],
          style: AppText.labelCaps(
            size: 9,
            color: isToday ? AppColors.primary : AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 5),
          Text(label, style: AppText.labelCaps(size: 9)),
        ],
      );
}

/// What the numbers can and cannot see.
///
/// Not fine print. The sampler reads the screen every 15 minutes, so a phone
/// picked up and put down in between leaves no trace — and a wake-up count of
/// zero on a night the user remembers waking would otherwise look like a bug
/// rather than the documented limit of the method.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.onSurfaceVariant, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sleep is estimated from phone screen activity every 15 minutes. '
              'Quick checks under 15 minutes may not be detected.',
              style: AppText.bodySm(color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      );
}
