import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../models/daily_log.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/daily_log_provider.dart';
import '../../services/daily_mission_gate.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';

/// First screen of the day: today's targets plus a one-line nudge derived
/// from yesterday's actual numbers. Shown once per calendar day — see
/// [DailyMissionGate] — right after splash/login/onboarding routing, before
/// the normal dashboard.
class DailyMissionScreen extends ConsumerStatefulWidget {
  const DailyMissionScreen({super.key});

  @override
  ConsumerState<DailyMissionScreen> createState() => _DailyMissionScreenState();
}

class _DailyMissionScreenState extends ConsumerState<DailyMissionScreen>
    with SingleTickerProviderStateMixin {
  String _bedtime = '10:30 PM';
  bool _loadingBedtime = true;

  /// Plays once on "Start My Day": the mission card settles back and the
  /// button hands off to a rocket-liftoff before the route actually changes,
  /// so the screen switch reads as a launch rather than an abrupt cut.
  late final AnimationController _launch = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  bool _launching = false;

  @override
  void initState() {
    super.initState();
    _loadBedtime();
  }

  @override
  void dispose() {
    _launch.dispose();
    super.dispose();
  }

  Future<void> _loadBedtime() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      if (mounted) setState(() => _loadingBedtime = false);
      return;
    }
    try {
      final row = await SupabaseService.client
          .from('sleep_schedule')
          .select('sleep_time')
          .eq('user_id', uid)
          .maybeSingle();
      final raw = row?['sleep_time'] as String?;
      if (!mounted) return;
      setState(() {
        if (raw != null) _bedtime = _formatTime12h(raw);
        _loadingBedtime = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBedtime = false);
    }
  }

  static String _formatTime12h(String hhmmss) {
    final parts = hhmmss.split(':');
    final h = int.tryParse(parts[0]) ?? 22;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 30;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  }

  static ({String emoji, String label}) _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return (emoji: '☀️', label: 'Good Morning');
    if (h < 17) return (emoji: '🌤️', label: 'Good Afternoon');
    return (emoji: '🌙', label: 'Good Evening');
  }

  /// Picks the goal with the biggest relative miss yesterday and phrases a
  /// concrete, actionable nudge for it — not an LLM call, just arithmetic
  /// against yesterday's logged totals, so it's instant and free.
  String _insight(UserProfile p, DailyLog? y) {
    if (y == null) {
      return "No data logged yesterday yet — today's a clean slate!";
    }

    final candidates = <(double pct, String text)>[];

    if (p.proteinGoalG > 0) {
      final gap = p.proteinGoalG - y.proteinG;
      if (gap > 0.5) {
        candidates.add((
          gap / p.proteinGoalG,
          'Yesterday you were ${gap.round()}g short of your protein goal. '
              'Try adding eggs or Greek yogurt to breakfast.',
        ));
      }
    }
    if (p.calorieGoal > 0 && y.caloriesConsumed > p.calorieGoal) {
      final over = y.caloriesConsumed - p.calorieGoal;
      candidates.add((
        over / p.calorieGoal,
        'Yesterday you went $over kcal over budget. A lighter dinner '
            'tonight can help bring you back on track.',
      ));
    }
    if (p.waterGoalMl > 0) {
      final gap = p.waterGoalMl - y.waterMl;
      if (gap > 100) {
        candidates.add((
          gap / p.waterGoalMl,
          'You were ${(gap / 1000).toStringAsFixed(1)}L short on water '
              'yesterday. Keep a bottle nearby as a reminder today.',
        ));
      }
    }
    if (p.stepsGoal > 0) {
      final gap = p.stepsGoal - y.steps;
      if (gap > 200) {
        candidates.add((
          gap / p.stepsGoal,
          'You were $gap steps short of your goal yesterday. A short '
              'walk after meals can help close that gap today.',
        ));
      }
    }

    if (candidates.isEmpty) {
      return 'Great job yesterday — every goal was on track. Keep the '
          'streak alive today!';
    }
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    return candidates.first.$2;
  }

  Future<void> _startDay() async {
    if (_launching) return;
    setState(() => _launching = true);
    await _launch.forward();
    await DailyMissionGate.markShownToday();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final yesterday = AppDateUtils.toDateOnly(
        DateTime.now().subtract(const Duration(days: 1)));
    final yesterdayLog = ref.watch(dailyLogProvider(yesterday));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          // A failed profile fetch used to be a dead end — bare text, no way
          // forward, on the first screen after launch. The rest of the app
          // reads from the local database and works regardless, so always
          // offer a way through.
          error: (_, __) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Could not load your profile',
                    style: AppText.bodyBold(color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text('Your logged data is safe on this device.',
                    style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PillButton(
                        label: 'Retry',
                        tone: PillTone.neutral,
                        icon: Icons.refresh_rounded,
                        height: 46,
                        glow: false,
                        onPressed: () =>
                            ref.read(profileProvider.notifier).load(),
                      ),
                      const SizedBox(width: 12),
                      PillButton(
                        label: 'Continue',
                        icon: Icons.arrow_forward_rounded,
                        height: 46,
                        onPressed: _startDay,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          data: (p) {
            if (p == null) return const SizedBox.shrink();
            final g = _greeting();
            final insight = _insight(p, yesterdayLog);

            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg,
                  AppSpacing.page, AppSpacing.lg),
              children: [
                Text(
                  '${g.emoji} ${g.label}, '
                  '${p.name?.trim().isNotEmpty == true ? p.name! : 'there'}',
                  style: AppText.headlineLg(),
                ),
                if (p.goal != null) ...[
                  const SizedBox(height: 6),
                  Text("Today's Goal: ${p.goal}",
                      style: AppText.body(color: AppColors.onSurfaceVariant)),
                ],
                const SizedBox(height: AppSpacing.lg),
                AnimatedBuilder(
                  animation: _launch,
                  builder: (context, child) => Opacity(
                    opacity: 1 - _launch.value * 0.6,
                    child: Transform.translate(
                      offset: Offset(0, _launch.value * 6),
                      child: child,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.flag_rounded,
                              color: AppColors.primary, size: 14),
                          const SizedBox(width: 6),
                          Text("Today's Mission",
                              style:
                                  AppText.headlineMd(color: AppColors.primary)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TerraCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _missionRow(
                                Icons.water_drop_rounded,
                                AppColors.water,
                                'Drink ${(p.waterGoalMl / 1000).toStringAsFixed(1)}L water'),
                            _missionRow(
                                Icons.kebab_dining_rounded,
                                AppColors.protein,
                                'Eat ${p.proteinGoalG.round()}g protein'),
                            _missionRow(
                                Icons.local_fire_department_rounded,
                                AppColors.primaryContainer,
                                'Stay under ${p.calorieGoal} kcal'),
                            _missionRow(
                                Icons.directions_run_rounded,
                                AppColors.fiberTeal,
                                'Walk ${p.stepsGoal} steps'),
                            _missionRow(Icons.bedtime_rounded, AppColors.sleep,
                                'Sleep before ${_loadingBedtime ? '…' : _bedtime}',
                                last: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TerraCard(
                  color: AppColors.secondary.withValues(alpha: 0.08),
                  borderColor: AppColors.secondary.withValues(alpha: 0.3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              color: AppColors.secondary, size: 18),
                          const SizedBox(width: 8),
                          Text('AI INSIGHT',
                              style: AppText.labelCaps(
                                  color: AppColors.secondary, size: 11)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(insight,
                          style: AppText.body().copyWith(height: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AnimatedBuilder(
                  animation: _launch,
                  builder: (context, _) {
                    // Rocket lifts and fades early in the timeline; the button
                    // itself only starts fading once the rocket is clear, so
                    // the two never visually overlap mid-flight.
                    final rocketT =
                        ((_launch.value - 0.1) / 0.6).clamp(0.0, 1.0);
                    final buttonT =
                        ((_launch.value - 0.6) / 0.4).clamp(0.0, 1.0);
                    return Column(
                      children: [
                        Opacity(
                          opacity: 1 - buttonT,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.pill,
                              boxShadow: _launching
                                  ? AppColors.glow(AppColors.primary,
                                      blur: 26, opacity: 0.45 * (1 - buttonT))
                                  : null,
                            ),
                            child: PillButton(
                              label: _launching ? 'Launching…' : 'Start My Day',
                              leading: Transform.translate(
                                offset: Offset(0, -26 * rocketT),
                                child: Opacity(
                                  opacity: 1 - rocketT,
                                  child: const Icon(Icons.rocket_launch_rounded,
                                      color: AppColors.onPrimary, size: 20),
                                ),
                              ),
                              onPressed: _launching ? null : _startDay,
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: buttonT,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text('Redirecting to your dashboard…',
                                style: AppText.bodySm(
                                    color: AppColors.onSurfaceVariant)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _missionRow(IconData icon, Color color, String text,
      {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: AppRadius.mdR,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppText.body())),
        ],
      ),
    );
  }
}
