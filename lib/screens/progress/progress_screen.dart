import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../models/local/local_daily_log.dart';
import '../../services/local_db_service.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/daily_log_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';

enum ProgressRange {
  week('This Week', 7),
  month('30 Days', 30),
  quarter('90 Days', 90);

  const ProgressRange(this.label, this.days);
  final String label;
  final int days;
}

/// A tracked metric the Progress tab can chart. One entry per selector button.
enum ProgressMetric {
  calories('Calories', 'calories_consumed', 'kcal',
      Icons.local_fire_department_rounded),
  protein('Protein', 'protein_g', 'g', Icons.egg_alt_outlined),
  water('Water', 'water_ml', 'ml', Icons.water_drop_rounded),
  steps('Steps', 'steps', '', Icons.directions_walk_rounded),
  sleep('Sleep', 'sleep_hrs', 'h', Icons.bedtime_rounded);

  const ProgressMetric(this.label, this.column, this.unit, this.icon);

  final String label;
  final String column;
  final String unit;
  final IconData icon;

  Color get color => switch (this) {
        ProgressMetric.calories => AppColors.primaryContainer,
        ProgressMetric.protein => AppColors.protein,
        ProgressMetric.water => AppColors.water,
        ProgressMetric.steps => AppColors.secondary,
        ProgressMetric.sleep => AppColors.tertiary,
      };

  double goalFor(UserProfile? p) => switch (this) {
        ProgressMetric.calories => (p?.calorieGoal ?? 2000).toDouble(),
        ProgressMetric.protein => p?.proteinGoalG ?? 150,
        ProgressMetric.water => (p?.waterGoalMl ?? 2500).toDouble(),
        ProgressMetric.steps => (p?.stepsGoal ?? 10000).toDouble(),
        ProgressMetric.sleep => p?.sleepGoalHrs ?? 8,
      };

  /// Sleep is the only fractional metric; everything else reads as a whole number.
  String format(double v) => this == ProgressMetric.sleep
      ? v.toStringAsFixed(1)
      : v.round().toString();
}

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});
  @override
  ConsumerState<ProgressScreen> createState() => _ProgressState();
}

class _ProgressState extends ConsumerState<ProgressScreen> {
  ProgressRange _range = ProgressRange.week;
  ProgressMetric _metric = ProgressMetric.calories;

  /// Drives the swipeable metric cards. The chips above them and the swipe are
  /// two ways at the same thing, so each has to move the other: tapping a chip
  /// animates the page, and swiping updates the selection.
  final PageController _metricPages = PageController();
  late Future<List<Map<String, dynamic>>> _logsFuture = _fetchLogs();

  @override
  void dispose() {
    _metricPages.dispose();
    super.dispose();
  }

  /// Height of the metric card's page slot.
  ///
  /// A PageView needs a bounded height, and the cards differ slightly — sleep
  /// carries a fifth stat row the others don't. A fixed height sized to the
  /// tallest is the right answer rather than a defect: a slot that resized
  /// mid-swipe would make the whole page jump as the user dragged.
  ///
  /// Scaled with the text scale for the same reason the dashboard carousel is:
  /// the card is mostly text, and clamping the scale inside it would override
  /// an accessibility setting rather than respect it.
  /// 372 is measured, not guessed: the tallest card (sleep) comes to 358px at
  /// 320dp, and progress_metric_card_test.dart fails if any metric outgrows
  /// this. An earlier estimate of 404 left 46px of dead card under every page.
  static double _metricCardHeight(BuildContext context) =>
      372 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4);

  /// Selects [m] and brings its card into view.
  ///
  /// `jumpToPage` when the controller has no clients yet — the very first
  /// build can select before the PageView is laid out, and animating then
  /// throws.
  void _selectMetric(ProgressMetric m) {
    setState(() => _metric = m);
    final page = ProgressMetric.values.indexOf(m);
    if (!_metricPages.hasClients) return;
    _metricPages.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// Last data revision this screen read at. The future above is captured once,
  /// so without re-running it when a sync lands the charts stay empty for the
  /// whole session on a cold start — the pull finishes *after* this widget is
  /// built.
  int _seenRevision = -1;

  /// Reads the window from the local database, so the charts render with no
  /// connection. The cache is topped up by [SyncService.pullFromSupabase] at
  /// launch and on pull-to-refresh; nothing here touches the network.
  Future<List<Map<String, dynamic>>> _fetchLogs() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    // Pull double the window so we can compare against the previous period.
    final from = DateTime.now().subtract(Duration(days: _range.days * 2 - 1));
    final logs = LocalDBService.getLogsForRange(uid, from, DateTime.now());
    return logs
        .map((l) => <String, dynamic>{
              'date': LocalDailyLog.isoDate(l.date),
              'calories_consumed': l.caloriesConsumed,
              'protein_g': l.proteinG,
              'carbs_g': l.carbsG,
              'fat_g': l.fatG,
              'fiber_g': l.fiberG,
              'water_ml': l.waterMl,
              'steps': l.steps,
              'calories_burned': l.caloriesBurned,
              'sleep_hrs': l.sleepHrs,
              'sleep_interruptions': l.sleepInterruptions,
              'weight_kg': l.weightKg,
            })
        .toList();
  }

  void _setRange(ProgressRange r) {
    setState(() {
      _range = r;
      _logsFuture = _fetchLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;

    // Re-read Hive whenever a sync writes new rows.
    final revision = ref.watch(dataRevisionProvider);
    if (revision != _seenRevision) {
      _seenRevision = revision;
      _logsFuture = _fetchLogs();
    }

    final now = DateTime.now();
    final start = now.subtract(Duration(days: _range.days - 1));
    final fmt = DateFormat('MMM d');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _logsFuture,
          builder: (context, snap) {
            final all = snap.data ?? const [];
            final cutoff = AppDateUtils.iso(start);
            final current = all
                .where((e) => (e['date'] as String).compareTo(cutoff) >= 0)
                .toList();
            final previous = all
                .where((e) => (e['date'] as String).compareTo(cutoff) < 0)
                .toList();
            final stats = _Stats.from(current, previous, profile);

            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs,
                  AppSpacing.page, AppSpacing.navClearance),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Proteinix',
                        style: AppText.headlineMd(color: AppColors.primary)),
                    CircleIconButton(
                      icon: Icons.notifications_none_rounded,
                      onTap: () => context.push('/notifications'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Weekly\nOverview',
                              style: AppText.display()
                                  .copyWith(fontSize: 32, height: 1.15)),
                          const SizedBox(height: 6),
                          Text('${fmt.format(start)} — ${fmt.format(now)}',
                              style: AppText.body(
                                  color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    _RangeMenu(range: _range, onChanged: _setRange),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _ConsistencyCard(stats: stats),
                const SizedBox(height: AppSpacing.gutter),
                if (stats.peakDay != null) ...[
                  _PeakDayCard(stats: stats),
                  const SizedBox(height: AppSpacing.gutter),
                ],
                _MetricSelector(
                  selected: _metric,
                  onChanged: _selectMetric,
                ),
                const SizedBox(height: AppSpacing.sm),
                // Swipeable, with the chips as the other half of the same
                // control. Five metrics behind a row of chips means the ones
                // that scroll off the right are easy to miss entirely; a swipe
                // is how people expect to move between cards, and the dots
                // below say how many there are.
                SizedBox(
                  height: _metricCardHeight(context),
                  child: PageView(
                    controller: _metricPages,
                    onPageChanged: (i) =>
                        setState(() => _metric = ProgressMetric.values[i]),
                    children: [
                      for (final m in ProgressMetric.values)
                        Padding(
                          // Breathing room between pages so the neighbouring
                          // card's edge doesn't touch this one mid-swipe.
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ProgressMetricCard(
                            metric: m,
                            logs: current,
                            profile: profile,
                            loading:
                                snap.connectionState == ConnectionState.waiting,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _MetricDots(
                  count: ProgressMetric.values.length,
                  index: ProgressMetric.values.indexOf(_metric),
                  color: _metric.color,
                ),
                const SizedBox(height: AppSpacing.gutter),
                _ComplianceCard(stats: stats),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Derived stats ─────────────────────────────────────────────────────────
class _Stats {
  const _Stats({
    required this.score,
    required this.previousScore,
    required this.hydrationDays,
    required this.totalDays,
    required this.peakDay,
    required this.peakSteps,
    required this.compliance,
  });

  final int score;
  final int previousScore;
  final int hydrationDays;
  final int totalDays;
  final DateTime? peakDay;
  final int peakSteps;

  /// Average intake as a fraction of goal, per macro.
  final Map<String, double> compliance;

  int get delta => score - previousScore;

  factory _Stats.from(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> previous,
    UserProfile? profile,
  ) {
    double num_(Map<String, dynamic> row, String key) =>
        (row[key] as num?)?.toDouble() ?? 0;

    int scoreOf(List<Map<String, dynamic>> rows) {
      if (rows.isEmpty) return 0;
      final calGoal = (profile?.calorieGoal ?? 2000).toDouble();
      final waterGoal = (profile?.waterGoalMl ?? 2500).toDouble();
      final stepGoal = (profile?.stepsGoal ?? 10000).toDouble();
      double total = 0;
      for (final r in rows) {
        final cal = (num_(r, 'calories_consumed') / calGoal).clamp(0.0, 1.0);
        final water = (num_(r, 'water_ml') / waterGoal).clamp(0.0, 1.0);
        final steps = (num_(r, 'steps') / stepGoal).clamp(0.0, 1.0);
        total += (cal * 0.5) + (water * 0.25) + (steps * 0.25);
      }
      return ((total / rows.length) * 100).round();
    }

    final waterGoal = (profile?.waterGoalMl ?? 2500).toDouble();
    final hydrationDays =
        current.where((r) => num_(r, 'water_ml') >= waterGoal).length;

    Map<String, dynamic>? peak;
    for (final r in current) {
      if (peak == null || num_(r, 'steps') > num_(peak, 'steps')) peak = r;
    }
    final peakSteps = peak == null ? 0 : num_(peak, 'steps').round();

    double avg(String key) => current.isEmpty
        ? 0
        : current.fold<double>(0, (s, r) => s + num_(r, key)) / current.length;

    double ratio(double value, double goal) =>
        goal <= 0 ? 0 : (value / goal).clamp(0.0, 1.5);

    return _Stats(
      score: scoreOf(current),
      previousScore: scoreOf(previous),
      hydrationDays: hydrationDays,
      totalDays: math.max(current.length, 1),
      peakDay: (peak == null || peakSteps == 0)
          ? null
          : DateTime.tryParse(peak['date'] as String),
      peakSteps: peakSteps,
      compliance: {
        'Protein': ratio(avg('protein_g'), profile?.proteinGoalG ?? 150),
        'Carbohydrates': ratio(avg('carbs_g'), profile?.carbsGoalG ?? 260),
        'Healthy Fats': ratio(avg('fat_g'), profile?.fatGoalG ?? 70),
        'Dietary Fiber': ratio(avg('fiber_g'), profile?.fiberGoalG ?? 25),
      },
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────
class _RangeMenu extends StatelessWidget {
  const _RangeMenu({required this.range, required this.onChanged});

  final ProgressRange range;
  final ValueChanged<ProgressRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ProgressRange>(
      onSelected: onChanged,
      color: AppColors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.xlR),
      itemBuilder: (_) => ProgressRange.values
          .map((r) => PopupMenuItem(
                value: r,
                child: Text(r.label, style: AppText.bodyBold()),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.onPrimaryFixedVariant.withValues(alpha: 0.4),
          borderRadius: AppRadius.xlR,
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(range.label,
                style: AppText.bodyBold(color: AppColors.primary)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.primary, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ConsistencyCard extends StatelessWidget {
  const _ConsistencyCard({required this.stats});

  final _Stats stats;

  @override
  Widget build(BuildContext context) {
    final delta = stats.delta;
    return TerraCard(
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -30,
            child: Icon(Icons.eco_rounded,
                size: 140, color: AppColors.primary.withValues(alpha: 0.05)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Consistency Score', color: AppColors.primary),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${stats.score}',
                      style: AppText.display().copyWith(fontSize: 56)),
                  Text(' / 100',
                      style: AppText.headlineMd(
                          color: AppColors.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                stats.totalDays == 0
                    ? 'Log a few days to start building your score.'
                    : "You've hit your hydration goal ${stats.hydrationDays} out of "
                        '${stats.totalDays} days. Keep the momentum going!',
                style: AppText.body(color: AppColors.onSurfaceVariant)
                    .copyWith(height: 1.5),
              ),
              const SizedBox(height: AppSpacing.sm),
              TerraBadge(
                label: '${delta >= 0 ? '+' : ''}$delta% vs last period',
                icon: delta >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                color: delta >= 0 ? AppColors.primary : AppColors.error,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PeakDayCard extends StatelessWidget {
  const _PeakDayCard({required this.stats});

  final _Stats stats;

  @override
  Widget build(BuildContext context) {
    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: AppRadius.lgR,
            ),
            child: const Icon(Icons.star_outline_rounded,
                color: AppColors.onSecondary, size: 26),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Peak Day', style: AppText.headlineLg()),
          const SizedBox(height: 4),
          Text(DateFormat('EEEE, MMMM d').format(stats.peakDay!),
              style: AppText.body(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.sm),
          const Divider(color: AppColors.outline),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.directions_walk_rounded,
                  color: AppColors.secondary, size: 18),
              const SizedBox(width: 8),
              Text('${stats.peakSteps} steps',
                  style: AppText.bodyBold(color: AppColors.secondary)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontal row of buttons choosing which metric the card below charts.
class _MetricSelector extends StatelessWidget {
  const _MetricSelector({required this.selected, required this.onChanged});

  final ProgressMetric selected;
  final ValueChanged<ProgressMetric> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: ProgressMetric.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final m = ProgressMetric.values[i];
          final active = m == selected;
          return GestureDetector(
            onTap: () => onChanged(m),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? m.color : AppColors.surfaceContainer,
                borderRadius: AppRadius.pill,
                border: Border.all(color: active ? m.color : AppColors.outline),
                boxShadow: active
                    ? AppColors.glow(m.color, blur: 16, opacity: 0.3)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(m.icon,
                      size: 16,
                      color: active
                          ? AppColors.onPrimary
                          : AppColors.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    m.label.toUpperCase(),
                    style: AppText.labelCaps(
                      color: active
                          ? AppColors.onPrimary
                          : AppColors.onSurfaceVariant,
                      size: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Today's ring, period averages and the trend line for the selected metric.
/// Public so progress_metric_card_test.dart can measure it against the fixed
/// page-slot height the PageView gives it.
class ProgressMetricCard extends StatelessWidget {
  const ProgressMetricCard({
    super.key,
    required this.metric,
    required this.logs,
    required this.profile,
    required this.loading,
  });

  final ProgressMetric metric;
  final List<Map<String, dynamic>> logs;
  final UserProfile? profile;
  final bool loading;

  double _value(Map<String, dynamic> row) =>
      (row[metric.column] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final goal = metric.goalFor(profile);
    final values = logs.map(_value).toList();
    final latest = values.isEmpty ? 0.0 : values.last;
    final average =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;
    final best = values.isEmpty ? 0.0 : values.reduce(math.max);
    final daysHit = values.where((v) => v >= goal).length;
    // Zero calories is a real day; zero sleep is a night nothing tracked.
    final tracked = metric != ProgressMetric.sleep || latest > 0;

    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            '${metric.label} progress',
            color: metric.color,
            trailing: Text(
              'GOAL: ${metric.format(goal)}${metric.unit.toUpperCase()}',
              style: AppText.labelCaps(
                  color: AppColors.onSurfaceVariant, size: 10),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              ProgressRing(
                value: (goal <= 0 || !tracked) ? 0 : latest / goal,
                color: metric.color,
                size: 96,
                strokeWidth: 10,
                glow: true,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (goal <= 0 || !tracked)
                          ? '—'
                          : '${((latest / goal) * 100).clamp(0, 999).round()}%',
                      style: AppText.bodyBold(color: AppColors.onSurface),
                    ),
                    Text(tracked ? 'TODAY' : 'NO DATA',
                        style: AppText.labelCaps(size: 8)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            metric.format(latest),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.display(color: metric.color)
                                .copyWith(fontSize: 30),
                          ),
                        ),
                        if (metric.unit.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(metric.unit,
                              style: AppText.bodySm(
                                  color: AppColors.onSurfaceVariant)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    _stat('Average', '${metric.format(average)}${metric.unit}'),
                    _stat('Best day', '${metric.format(best)}${metric.unit}'),
                    _stat('Goal hit', '$daysHit of ${values.length} days'),
                    // Sleep is the only metric with a quality signal beside its
                    // quantity — hours alone can't tell eight unbroken hours
                    // from eight broken by three wake-ups.
                    if (metric == ProgressMetric.sleep)
                      _stat('Wake-ups', _wakeUps()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 150,
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : values.isEmpty
                    ? Center(
                        child: Text('No ${metric.label.toLowerCase()} data yet',
                            style: AppText.bodySm(
                                color: AppColors.onSurfaceVariant)),
                      )
                    : BarChart(_chart(values, goal)),
          ),
        ],
      ),
    );
  }

  /// Wake-ups across the nights Sleep Guard actually observed.
  ///
  /// Nights with no sleep recorded are dropped rather than counted as zero
  /// disturbances — the guard being off is missing data, not a flawless night,
  /// and folding those in would flatter every total. Phrased as a count over
  /// nights, matching the "Goal hit" row above it.
  String _wakeUps() {
    final counts = [
      for (final r in logs)
        if (((r['sleep_hrs'] as num?)?.toDouble() ?? 0) > 0)
          (r['sleep_interruptions'] as num?)?.toInt() ?? 0,
    ];
    if (counts.isEmpty) return 'No data';

    final total = counts.reduce((a, b) => a + b);
    final nights = counts.length == 1 ? 'night' : 'nights';
    return '$total in ${counts.length} $nights';
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label.toUpperCase(), style: AppText.labelCaps(size: 9)),
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppText.labelCaps(color: AppColors.onSurface, size: 10)),
            ),
          ],
        ),
      );

  /// Rounded bars, one per day, coloured with the metric's own accent — the
  /// same colour the chip, ring and figure above already use for it.
  ///
  /// The cap radius is always half the bar's width, top and bottom both, so
  /// a bar reads as a fully smooth-ended capsule rather than a rectangle at
  /// any width. Width itself shrinks as the range grows: 90 days of 9px bars
  /// would overlap in the card's ~300px of chart width, so bars thin out past
  /// a week's worth of points instead of the card scrolling horizontally.
  BarChartData _chart(List<double> values, double goal) {
    final barWidth =
        values.length <= 10 ? 9.0 : (values.length <= 35 ? 4.0 : 2.0);
    // ~4 date labels across the axis regardless of range, so 90 days doesn't
    // crowd every tick into an unreadable smear.
    final step = (values.length / 4).ceil().clamp(1, values.length);

    return BarChartData(
      alignment: BarChartAlignment.spaceBetween,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.outline, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        show: true,
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 20,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= logs.length || i % step != 0) {
                return const SizedBox.shrink();
              }
              final date = DateTime.tryParse(logs[i]['date'] as String);
              if (date == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(DateFormat('MMM d').format(date),
                    style: AppText.labelCaps(size: 8)),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(
          y: goal,
          color: metric.color.withValues(alpha: 0.5),
          strokeWidth: 1,
          dashArray: [6, 4],
        ),
      ]),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => AppColors.surfaceContainerHigh,
          getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
            '${metric.format(rod.toY)}${metric.unit}',
            AppText.bodyBold(color: metric.color),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < values.length; i++)
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i],
                color: metric.color,
                width: barWidth,
                borderRadius: BorderRadius.circular(barWidth / 2),
              ),
            ],
          ),
      ],
    );
  }
}

class _ComplianceCard extends StatelessWidget {
  const _ComplianceCard({required this.stats});

  final _Stats stats;

  static const _colors = {
    'Protein': AppColors.protein,
    'Carbohydrates': AppColors.carbs,
    'Healthy Fats': AppColors.fat,
    'Dietary Fiber': AppColors.fiber,
  };

  @override
  Widget build(BuildContext context) {
    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Macro compliance'),
          const SizedBox(height: AppSpacing.sm),
          ...stats.compliance.entries.map((e) {
            final pct = (e.value * 100).round();
            final color = _colors[e.key] ?? AppColors.primary;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key, style: AppText.bodyBold()),
                      Text('$pct%', style: AppText.bodyBold(color: color)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearMeter(value: e.value.clamp(0.0, 1.0), color: color),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Page indicator under the swipeable metric cards.
///
/// Five metrics is more than a row of chips advertises on a narrow phone — the
/// last of them scroll off the right edge — so the dots are what say there is
/// more here than the one card on screen.
class _MetricDots extends StatelessWidget {
  const _MetricDots({
    required this.count,
    required this.index,
    required this.color,
  });

  final int count;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 6,
              // The active dot stretches rather than just brightening, so the
              // position is readable at a glance and without relying on colour.
              width: i == index ? 18 : 6,
              decoration: BoxDecoration(
                color: i == index ? color : AppColors.outline,
                borderRadius: AppRadius.pill,
              ),
            ),
        ],
      );
}
