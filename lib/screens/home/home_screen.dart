import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/crash_log.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/require_account.dart';
import '../../core/utils/technical_issue.dart';
import '../../models/daily_log.dart';
import '../../models/meal.dart';
import '../../models/meal_slot.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/daily_log_provider.dart';
import '../../providers/meal_schedule_provider.dart';
import '../../services/health_connect_service.dart';
import '../../services/meal_schedule_service.dart';
import '../../services/pedometer_service.dart';
import '../../services/sleep_tracking_service.dart';
import '../../services/supabase_service.dart';
import '../../services/sync_service.dart';
import '../../services/weight_checkin_service.dart';
import '../../widgets/sleep_cycle_switch.dart';
import '../../widgets/home_banner_ad.dart';
import 'home_prompts.dart';
import '../../widgets/ui/ui.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _hc = HealthConnectService();
  final _pedo = PedometerService();
  final PageController _carousel = PageController();
  int _carouselIndex = 0;

  /// Guards against re-prompting on every resume — once shown (or skipped)
  /// this session, it waits for the next session rather than the next time
  /// the app comes back from the background.
  bool _checkinPrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSelectedDate();
      _startTracking();
      _maybeShowWeightCheckin();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _carousel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncSelectedDate();
      _startTracking();
      _maybeShowWeightCheckin();
    }
  }

  /// Snaps the shared date selector back to today, on Home's behalf only.
  ///
  /// [selectedDateProvider] is shared with Nutrition, which deliberately lets
  /// someone browse a past day and expects that choice to survive a brief
  /// background/resume — so the provider itself can't just always reset to
  /// today. But Home has no date picker of its own; every value it can ever
  /// show *should* be today. Without this, leaving the app open (or merely
  /// backgrounded) across midnight left it reading gone-stale "today" data —
  /// yesterday's steps still in the ring — because nothing else ever moved
  /// this provider forward once app start had set it once.
  void _syncSelectedDate() {
    final today = AppDateUtils.toDateOnly(DateTime.now());
    if (ref.read(selectedDateProvider) != today) {
      ref.read(selectedDateProvider.notifier).state = today;
    }
  }

  /// Prompts for a weigh-in once a week, and — if the trend doesn't match
  /// the user's goal — either recalibrates targets or asks for more
  /// consistency, depending on whether the past week was actually followed.
  /// See [WeightCheckinService] for the full decision.
  Future<void> _maybeShowWeightCheckin() async {
    if (_checkinPrompted) return;
    final uid = SupabaseService.currentUserId;
    final profile = ref.read(profileProvider).value;
    if (uid == null || profile == null || !profile.onboardingComplete) return;
    if (!await WeightCheckinService.isDue(uid)) return;
    _checkinPrompted = true;
    // Recorded before the sheet opens, not after it is answered: dismissing
    // by tapping outside returns nothing and runs no callback, and without
    // this that path left the interval un-restarted and the prompt due again
    // on the next rebuild.
    await WeightCheckinService.markAsked();
    if (!mounted) return;
    await _showWeightCheckinSheet(uid, profile);
  }

  Future<void> _showWeightCheckinSheet(String uid, UserProfile profile) async {
    final controller = TextEditingController(
        text: (profile.weightKg ?? 70).toStringAsFixed(1));
    final newWeight = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.page,
          right: AppSpacing.page,
          bottom: MediaQuery.of(ctx).padding.bottom + AppSpacing.md,
        ),
        child: TerraCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.monitor_weight_rounded,
                      color: AppColors.secondary),
                  const SizedBox(width: 8),
                  Text('Weekly check-in', style: AppText.headlineMd()),
                ],
              ),
              const SizedBox(height: 6),
              Text("It's been a week — what's your weight today?",
                  style: AppText.body(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.md),
              TerraField(
                controller: controller,
                label: 'Weight',
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,4}\.?\d{0,2}')),
                ],
                trailingText: 'kg',
              ),
              const SizedBox(height: AppSpacing.md),
              PillButton(
                label: 'Save',
                onPressed: () {
                  final v = double.tryParse(controller.text);
                  if (v != null && v > 0) Navigator.pop(ctx, v);
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Skip for now'),
              ),
            ],
          ),
        ),
      ),
    );
    if (newWeight == null || !mounted) return;

    final result = await WeightCheckinService.submit(
      userId: uid,
      profile: profile,
      newWeightKg: newWeight,
    );
    // The weigh-in itself always updates the stored weight, independent of
    // whether targets end up changing — every BMR/TDEE calculation downstream
    // should read the number the user just gave, not the onboarding one.
    await ref.read(profileProvider.notifier).update(
          profile.copyWith(weightKg: newWeight),
        );
    if (!mounted) return;
    await _showCheckinResultSheet(
        result, profile.copyWith(weightKg: newWeight));
  }

  Future<void> _showCheckinResultSheet(
      CheckinResult result, UserProfile profile) async {
    switch (result.outcome) {
      case CheckinOutcome.onTrack:
        await _infoSheet(
          icon: Icons.trending_up_rounded,
          color: AppColors.secondary,
          title: "You're on track",
          message:
              "Nice work — your weight is trending the right way. Keep doing exactly what you're doing.",
        );
        break;
      case CheckinOutcome.stayConsistent:
        final areas = result.weakAreas.isEmpty
            ? 'your daily goals'
            : result.weakAreas.join(', ');
        await _infoSheet(
          icon: Icons.flag_rounded,
          color: AppColors.tertiary,
          title: 'Your targets are staying the same',
          message:
              "Your weight hasn't moved as expected, but this week's numbers show $areas fell short on several days. Stay consistent with your existing goals and check back in a week.",
        );
        break;
      case CheckinOutcome.recalibrated:
        final t = result.newTargets!;
        final apply = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (ctx) => Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.page,
              right: AppSpacing.page,
              bottom: MediaQuery.of(ctx).padding.bottom + AppSpacing.md,
            ),
            child: TerraCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('Your targets need an update',
                              style: AppText.headlineMd())),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "You've been following your plan, but your weight isn't moving as expected — the targets themselves need adjusting.",
                    style: AppText.body(color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _beforeAfter('Calories', profile.calorieGoal,
                          (t['calories'] ?? 0).toInt()),
                      _beforeAfter('Protein', profile.proteinGoalG.round(),
                          (t['protein_g'] ?? 0).round()),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PillButton(
                    label: 'Update my targets',
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Keep current targets'),
                  ),
                ],
              ),
            ),
          ),
        );
        if (apply == true && mounted) {
          await ref.read(profileProvider.notifier).update(profile.copyWith(
                calorieGoal: (t['calories'] ?? profile.calorieGoal).toInt(),
                proteinGoalG:
                    (t['protein_g'] ?? profile.proteinGoalG).toDouble(),
                carbsGoalG: (t['carbs_g'] ?? profile.carbsGoalG).toDouble(),
                fatGoalG: (t['fat_g'] ?? profile.fatGoalG).toDouble(),
                fiberGoalG: (t['fiber_g'] ?? profile.fiberGoalG).toDouble(),
              ));
        }
    }
  }

  Future<void> _infoSheet({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.page,
          right: AppSpacing.page,
          bottom: MediaQuery.of(ctx).padding.bottom + AppSpacing.md,
        ),
        child: TerraCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: AppText.headlineMd())),
                ],
              ),
              const SizedBox(height: 8),
              Text(message,
                  style: AppText.body(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.md),
              PillButton(label: 'Got it', onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _beforeAfter(String label, int before, int after) => Column(
        children: [
          Text(label.toUpperCase(), style: AppText.labelCaps(size: 10)),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$before',
                style: AppText.body(color: AppColors.onSurfaceVariant)
                    .copyWith(decoration: TextDecoration.lineThrough),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded,
                  size: 14, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('$after', style: AppText.bodyBold(color: AppColors.primary)),
            ],
          ),
        ],
      );

  /// Guards against overlapping refreshes. Anything that pauses the app —
  /// a permission dialog, the app switcher — fires `resumed` on return, and
  /// without this the next refresh starts before the previous one finished.
  bool _tracking = false;
  DateTime? _lastTrackedAt;

  Future<void> _startTracking({bool force = false}) async {
    if (_tracking) return;
    // A resume immediately after a refresh has nothing new to read; throttling
    // also stops a resume storm from turning into a request storm. An explicit
    // pull-to-refresh bypasses it.
    final last = _lastTrackedAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _tracking = true;
    try {
      // First, and before the sign-in check: the app being in the foreground is
      // a fact about the night regardless of who is logged in, and it has to be
      // recorded before `_recordSleep` reads the night below. The native side
      // ignores it outside the sleep window and debounces repeat resumes.
      await SleepTrackingService.noteAppOpen();

      final uid = SupabaseService.currentUserId;
      if (uid == null) return;
      final today = AppDateUtils.toDateOnly(DateTime.now());

      // Sleep first, and in its own guard.
      //
      // This used to be the last statement of one long try that swallowed every
      // exception, so anything upstream failing took the night down with it and
      // said nothing: `_pedo.start()` on a phone that refused ACTIVITY_
      // RECOGNITION, a Health Connect call, a `setSteps` write. The night was
      // measured correctly by the native sampler and then simply never written,
      // which is indistinguishable from the tracker not working.
      //
      // These two are independent readings of unrelated sensors. Neither should
      // ever be able to cancel the other, and a failure in either has to leave
      // a trace in Diagnostics rather than vanishing.
      try {
        await _recordSleep(uid);
      } catch (e, s) {
        await CrashLog.record('Sleep record failed: $e', s);
      }

      try {
        final profile = ref.read(profileProvider).value;
        await _pedo.start(
          weightKg: profile?.weightKg ?? 70.0,
          heightCm: profile?.heightCm ?? 170.0,
          gender: profile?.gender ?? 'male',
        );

        int hcSteps = 0;
        double hcCalories = 0;
        try {
          if (await _hc.available()) {
            final results =
                await Future.wait([_hc.stepsToday(), _hc.caloriesToday()]);
            hcSteps = results[0] as int;
            hcCalories = results[1] as double;
          }
        } catch (_) {}

        final pedoSteps = _pedo.todaySteps;
        final bestSteps = hcSteps > pedoSteps ? hcSteps : pedoSteps;
        final bestCalories =
            hcCalories > 0 ? hcCalories.round() : _pedo.caloriesBurned;

        // Unconditional — [PedometerService.todaySteps] is now always an
        // honest read of *today's* count (see its doc comment), so a
        // genuine 0 here means nothing measured yet today, not a sensor
        // that lost its count. Writing it through unconditionally is what
        // lets this self-correct a stale figure left over from a previous
        // day instead of silently declining to touch it. The old branch's
        // `forceSync()` fallback read the same field without that fix, which
        // was the other way a stale count reached the server.
        await MealService.setSteps(ref, uid, today, bestSteps,
            caloriesBurned: bestCalories);
      } catch (e, s) {
        await CrashLog.record('Step tracking failed: $e', s);
      }

      if (mounted) ref.invalidate(dailyLogProvider(today));
    } catch (e, s) {
      await CrashLog.record('Dashboard refresh failed: $e', s);
    } finally {
      _tracking = false;
      _lastTrackedAt = DateTime.now();
    }
  }

  /// Persists the night the tracker observed.
  ///
  /// Health Connect wins when it has something, because a watch measures sleep
  /// where this only infers it from screen state — but it stays silent for
  /// anyone without a wearable, which is why it can't be the only source. The
  /// screen-state estimate is what makes the Sleep ring work on a bare phone.
  Future<void> _recordSleep(String uid) async {
    // Nights the sampler banked while the app was closed. Without this pass a
    // night was only ever written if the dashboard happened to be opened
    // between waking and the next bedtime — miss that and it was gone.
    for (final past in await SleepTrackingService.history()) {
      if (!past.usable) continue;
      await MealService.setSleep(
        ref,
        uid,
        AppDateUtils.toDateOnly(past.date!),
        past.hours,
        interruptions: past.wakeUps,
        phonePickups: past.phonePickups,
        sleepStart: past.sleepStart,
        sleepEnd: past.sleepEnd,
      );
    }

    final night = await SleepTrackingService.lastNight();
    if (!night.usable) return;

    final day = AppDateUtils.toDateOnly(night.date!);
    final today = AppDateUtils.toDateOnly(DateTime.now());
    var hours = night.hours;
    // Only when the night is today's. `sleepHoursToday` reads from 18:00
    // yesterday, so it always describes the night that ended this morning —
    // during the evening the guard is already accruing *tomorrow's* night, and
    // applying this to that row would file last night's sleep under tomorrow.
    if (day == today) {
      try {
        if (await _hc.available()) {
          final measured = await _hc.sleepHoursToday();
          if (measured > 0) hours = measured;
        }
      } catch (_) {}
    }

    await MealService.setSleep(
      ref,
      uid,
      day,
      hours,
      interruptions: night.wakeUps,
      phonePickups: night.phonePickups,
      sleepStart: night.sleepStart,
      sleepEnd: night.sleepEnd,
    );
  }

  Future<void> _refresh(DateTime date) async {
    await _startTracking(force: true);
    // Pull-to-refresh is the user asking for server data, so try the network —
    // but the local reads below repaint either way, so this works offline too.
    final uid = SupabaseService.currentUserId;
    if (uid != null) await SyncService.onAppStart(uid);
    ref.read(dataRevisionProvider.notifier).state++;
    ref.invalidate(dailyLogProvider(date));
    ref.invalidate(mealsForDateProvider(date));
  }

  Future<void> _addWater(int ml, int currentMl) async {
    if (!await requireAccount(context, action: 'track your water')) return;
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    final today = AppDateUtils.toDateOnly(DateTime.now());
    try {
      await MealService.addWater(ref, uid, today, ml, currentMl: currentMl);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save that water — try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final date = ref.watch(selectedDateProvider);
    final log = ref.watch(dailyLogProvider(date));
    final meals = ref.watch(mealsForDateProvider(date));

    final waterMl = log?.waterMl ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: Padding(
        // Lift clear of the floating nav bar.
        padding: const EdgeInsets.only(bottom: 78, right: 4),
        child: MicFab(onTap: () async {
          if (!await requireAccount(context, action: 'log a meal')) return;
          if (context.mounted) context.push('/log-food/voice');
        }),
      ),
      body: SafeArea(
        bottom: false,
        // No offline banner. Working offline is a supported mode here, not a
        // fault — everything is written to Hive and synced when the connection
        // returns — so a red strip across the dashboard reported a problem the
        // user does not have. The one place offline genuinely blocks something
        // is the AI features, and OfflineAIWidget says so on those screens.
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _refresh(date),
                color: AppColors.primary,
                backgroundColor: AppColors.surfaceContainer,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                      AppSpacing.xs, AppSpacing.page, AppSpacing.navClearance),
                  children: [
                    _Header(
                        profile: profile,
                        streak: ref.watch(proteinStreakProvider)),
                    const SizedBox(height: AppSpacing.md),
                    // Both render nothing unless they have something to say.
                    WelcomeBackCard(name: profile?.name),
                    const UsualMealCard(),
                    _carouselSection(profile, log),
                    const SizedBox(height: AppSpacing.md),
                    _StepsCard(profile: profile, log: log, pedo: _pedo),
                    const SizedBox(height: AppSpacing.gutter),
                    HydrationCard(
                      currentMl: waterMl,
                      goalMl: profile?.waterGoalMl ?? 2500,
                      onAdd: (ml) => _addWater(ml, waterMl),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SectionHeading(
                      AppStrings.todaysMeals,
                      actionLabel: AppStrings.logFood,
                      onAction: () async {
                        if (!await requireAccount(context,
                            action: 'log a meal')) {
                          return;
                        }
                        if (context.mounted) context.push('/log-food');
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // No loading/error branch: the list comes straight out of Hive,
                    // so it is either present or genuinely empty — never pending.
                    _MealsList(meals: meals),
                    // The app's only ad: one banner, here, for users not on
                    // Pro. Takes no space when there is nothing to show.
                    const HomeBannerAd(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carouselSection(UserProfile? profile, DailyLog? log) {
    return Column(
      children: [
        SizedBox(
          // Sized to the energy card's tallest arrangement: header + progress
          // rings + macro gauges measure ~293px at 320dp, and the gauges grow
          // with width until their ring size caps. today_progress_test.dart
          // fails if that budget is exceeded.
          //
          // Grown with the text scale rather than fixed. Both cards are almost
          // entirely text, so a user who has turned system text up gets a
          // clipped card from a hard 312 — and clamping the scale *inside* the
          // card would fix the layout by ignoring an accessibility setting.
          // Capped at 1.4 so an extreme setting cannot swallow the screen.
          height:
              312 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4),
          child: PageView(
            controller: _carousel,
            onPageChanged: (i) => setState(() => _carouselIndex = i),
            children: [
              _EnergyCard(profile: profile, log: log),
              const _SleepCard(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            2,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _carouselIndex == i ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color:
                    _carouselIndex == i ? AppColors.primary : AppColors.outline,
                borderRadius: AppRadius.pill,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.streak});

  final UserProfile? profile;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              ProfileBadge(
                name: profile?.name,
                avatarUrl: profile?.avatarUrl,
                onTap: () => context.push('/profile'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile?.name?.trim().isNotEmpty == true
                          ? profile!.name!
                          : AppStrings.appFullName,
                      style: AppText.headlineMd(),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    _StreakBadge(streak: streak),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SyncStatusWidget(),
        const SizedBox(width: 6),
        CircleIconButton(
          icon: Icons.notifications_none_rounded,
          color: AppColors.primary,
          badge: true,
          onTap: () => context.push('/notifications'),
        ),
      ],
    );
  }
}

/// Flame + day count under the header name.
///
/// A soft glow breathes behind the flame whenever there's a streak to
/// protect, and the flame bumps once when [streak] ticks up — the only
/// moment the badge has something to celebrate, so that's the only moment it
/// moves beyond the idle glow.
class _StreakBadge extends StatefulWidget {
  const _StreakBadge({required this.streak});

  final int streak;

  @override
  State<_StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<_StreakBadge>
    with TickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat();
  late final AnimationController _bump = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void didUpdateWidget(covariant _StreakBadge old) {
    super.didUpdateWidget(old);
    if (widget.streak > old.streak) _bump.forward(from: 0);
  }

  @override
  void dispose() {
    _breathe.dispose();
    _bump.dispose();
    super.dispose();
  }

  /// Triangular pulse peaking at 35% through the bump, back to baseline by
  /// the end — a scale for the flame, an inverted one (dip then recover) for
  /// the text.
  double _peak(double t) => t <= 0.35 ? t / 0.35 : 1 - (t - 0.35) / 0.65;

  void _showDetail() {
    // The element can be torn down between a tap starting and this callback
    // running — a rebuild racing the gesture, or (as seen in Diagnostics) the
    // app itself getting force-stopped mid-tap. Looking up the ScaffoldMessenger
    // on a deactivated element throws, so this is not optional.
    if (!mounted) return;
    final n = widget.streak;
    final message = n > 0
        ? "$n day${n == 1 ? '' : 's'} streak — you've hit your protein goal "
            '$n day${n == 1 ? '' : 's'} running.'
        : 'No streak yet — hit your protein goal today to start one.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasStreak = widget.streak > 0;

    return GestureDetector(
      onTap: _showDetail,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (hasStreak)
                  AnimatedBuilder(
                    animation: _breathe,
                    builder: (context, _) {
                      final t = _breathe.value;
                      return Container(
                        width: 15 + 9 * t,
                        height: 15 + 9 * t,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryContainer
                              .withValues(alpha: (1 - t) * 0.35),
                        ),
                      );
                    },
                  ),
                AnimatedBuilder(
                  animation: _bump,
                  builder: (context, child) => Transform.scale(
                    scale: 1 + 0.5 * _peak(_bump.value),
                    child: child,
                  ),
                  child: const Icon(Icons.local_fire_department_rounded,
                      color: AppColors.primaryContainer, size: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _bump,
            builder: (context, child) => Opacity(
              opacity: 1 - 0.5 * _peak(_bump.value),
              child: child,
            ),
            child: Text(
                hasStreak
                    ? '${widget.streak} day${widget.streak == 1 ? '' : 's'} streak'
                    : 'Daily streak',
                style: AppText.labelCaps(
                    color: AppColors.primaryContainer, size: 11)),
          ),
        ],
      ),
    );
  }
}

// ── Carousel card 1: energy & macros ──────────────────────────────────────
class _EnergyCard extends StatelessWidget {
  const _EnergyCard({required this.profile, required this.log});

  final UserProfile? profile;
  final DailyLog? log;

  @override
  Widget build(BuildContext context) {
    final goal = profile?.calorieGoal ?? 2000;
    final eaten = log?.caloriesConsumed ?? 0;
    final left = (goal - eaten).clamp(0, 99999);

    return TerraCard(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: SectionLabel(AppStrings.dailyEnergy)),
              _figure('Left', '$left', AppColors.primary),
              Container(
                height: 32,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: AppColors.outline,
              ),
              _figure('Eaten', '$eaten', AppColors.onSurface),
            ],
          ),
          const Spacer(),
          _TodayProgress(profile: profile, log: log),
          const Spacer(),
          MacroGaugeRow(
            macros: [
              MacroSpec(
                label: 'Protein',
                current: log?.proteinG ?? 0,
                goal: profile?.proteinGoalG ?? 150,
                color: AppColors.protein,
                icon: Icons.kebab_dining_rounded,
              ),
              MacroSpec(
                label: 'Carbs',
                current: log?.carbsG ?? 0,
                goal: profile?.carbsGoalG ?? 260,
                color: AppColors.carbs,
                icon: Icons.bakery_dining_rounded,
              ),
              MacroSpec(
                label: 'Fats',
                current: log?.fatG ?? 0,
                goal: profile?.fatGoalG ?? 70,
                color: AppColors.fat,
                icon: Icons.water_drop_rounded,
              ),
              MacroSpec(
                label: 'Fiber',
                current: log?.fiberG ?? 0,
                goal: profile?.fiberGoalG ?? 25,
                color: AppColors.fiber,
                icon: Icons.eco_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label.toUpperCase(), style: AppText.labelCaps(size: 10)),
          const SizedBox(height: 2),
          Text(value, style: AppText.headlineMd(color: color)),
        ],
      );
}

/// Four goals as concentric rings, with a legend of what is still owed.
///
/// Macros collapse to a single ring — the mean of the four macro ratios — so
/// the stack stays readable; the gauges below this block carry the breakdown.
/// Each ring reuses the colour that metric already has elsewhere in the app:
/// lime for steps, peach for intake, blue for water, violet for sleep.
class _TodayProgress extends StatelessWidget {
  const _TodayProgress({required this.profile, required this.log});

  final UserProfile? profile;
  final DailyLog? log;

  double _macroMean() {
    final ratios = <double>[
      _ratio(log?.proteinG ?? 0, profile?.proteinGoalG ?? 150),
      _ratio(log?.carbsG ?? 0, profile?.carbsGoalG ?? 260),
      _ratio(log?.fatG ?? 0, profile?.fatGoalG ?? 70),
      _ratio(log?.fiberG ?? 0, profile?.fiberGoalG ?? 25),
    ];
    return ratios.reduce((a, b) => a + b) / ratios.length;
  }

  static double _ratio(double current, double goal) =>
      goal <= 0 ? 0 : (current / goal).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    // The macro ring is already a 0–1 mean, so it is fed as a fraction of 1.
    final rings = <RingSpec>[
      RingSpec(
        label: 'Steps',
        current: (log?.steps ?? 0).toDouble(),
        goal: (profile?.stepsGoal ?? 10000).toDouble(),
        color: AppColors.secondary,
      ),
      RingSpec(
        label: 'Macros',
        current: _macroMean(),
        goal: 1,
        color: AppColors.primary,
      ),
      RingSpec(
        label: 'Water',
        current: (log?.waterMl ?? 0).toDouble(),
        goal: (profile?.waterGoalMl ?? 2500).toDouble(),
        color: AppColors.water,
        unit: 'ml',
      ),
      RingSpec(
        label: 'Sleep',
        current: log?.sleepHrs ?? 0,
        goal: profile?.sleepGoalHrs ?? 8,
        color: AppColors.sleep,
        unit: 'h',
        // Sleep is the one metric nothing records unless Sleep Guard ran, so
        // zero means "not tracked" rather than "none" — the ring dims out
        // instead of claiming a night of no sleep.
        hasData: (log?.sleepHrs ?? 0) > 0,
      ),
    ];

    return TodayProgressPanel(
      title: AppStrings.todaysProgress,
      rings: rings,
    );
  }
}

// ── Carousel card 2: sleep cycle ──────────────────────────────────────────
/// Sets the sleep window and switches tracking on, with no separate setup
/// screen behind it.
///
/// Everything the feature needs is two times and one button, so a whole screen
/// to hold them was three taps of ceremony around a decision most people make
/// once. Tapping either time opens a picker in place; the button arms the
/// native alarms that start and stop tracking at those times.
class _SleepCard extends StatefulWidget {
  const _SleepCard();

  @override
  State<_SleepCard> createState() => _SleepCardState();
}

class _SleepCardState extends State<_SleepCard> with WidgetsBindingObserver {
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

  /// The card loaded once and then never again, so the night it drew at 11pm
  /// was still on screen at 8am — the figures only ever changed by leaving the
  /// screen and coming back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final status = await SleepTrackingService.status();
    final night = await SleepTrackingService.lastNight();
    if (mounted) {
      setState(() {
        _status = status;
        _night = night;
      });
    }
  }

  /// Edits one end of the window.
  ///
  /// A change while tracking is armed re-arms it, because the alarms already
  /// scheduled point at the old times — saving without that would show the new
  /// window on the card while the service still ran on the previous one.
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
      // a device set to 24-hour time got a 24-hour dial with no AM/PM toggle.
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
      if (_status.armed) {
        await SleepTrackingService.start(
            bedtime: nextBed, wake: nextWake, userId: uid);
      } else {
        await SleepTrackingService.saveSchedule(
            bedtime: nextBed, wake: nextWake, userId: uid);
      }
    } catch (_) {
      // Non-Android host; the times are still saved locally by saveSchedule.
    }
    await _load();
  }

  Future<void> _toggle(bool turningOn) async {
    if (_busy || turningOn == _status.armed) return;

    setState(() => _busy = true);
    try {
      final uid = SupabaseService.currentUserId;
      if (turningOn) {
        await SleepTrackingService.start(
            bedtime: _status.bedtime, wake: _status.wake, userId: uid);
      } else {
        await SleepTrackingService.stop(userId: uid);
      }
      if (!mounted) return;
      setState(() => _busy = false);
      // Re-read rather than assuming: the service can refuse to start.
      await _load();
      if (!mounted) return;

      // Switching on outside the window schedules tracking without starting
      // it, so say which of the two happened rather than claiming it is
      // running when it is only armed. Either way the wake time is named:
      // "it stops on its own" is the half of the deal the old Stop button
      // implied was the user's job.
      final at = SleepTrackingService.formatTime(_status.bedtime, 'bedtime');
      final until = SleepTrackingService.formatTime(_status.wake, 'your wake time');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!turningOn
              ? 'Sleep cycle off. Nothing will be tracked.'
              : _status.running
                  ? 'Tracking your sleep now — stops at $until.'
                  : 'Sleep cycle on. Tracking runs $at to $until.'),
        ),
      );
    } catch (e, s) {
      if (!mounted) return;
      setState(() => _busy = false);
      showTechnicalIssueSnack(
        context,
        action: 'change your sleep tracking',
        reportContext: 'home_sleep_toggle',
        error: e,
        stack: s,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TerraCard(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel(AppStrings.sleepCycle),
              Row(
                children: [
                  _PhaseChip(phase: _status.phase, busy: _busy),
                  const SizedBox(width: 4),
                  // The card is the control; the screen is the detail. Both
                  // exist because setting a bedtime and reading last week's
                  // nights are different errands, and the dashboard should
                  // only ever be the first one.
                  GestureDetector(
                    onTap: () => context.push('/sleep'),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.chevron_right_rounded,
                          color: AppColors.onSurfaceVariant, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _time(
                  Icons.bedtime_rounded,
                  'Sleep',
                  SleepTrackingService.formatTime(_status.bedtime, '10:30 PM'),
                  AppColors.tertiary,
                  () => _pickTime(bedtime: true),
                ),
              ),
              Expanded(
                child: _time(
                  Icons.wb_sunny_rounded,
                  'Wake',
                  SleepTrackingService.formatTime(_status.wake, '06:30 AM'),
                  AppColors.primary,
                  () => _pickTime(bedtime: false),
                ),
              ),
            ],
          ),
          const Spacer(),
          _summaryLine(),
          const SizedBox(height: 6),
          // A switch, not a Start/Stop button. The feature has never been a
          // stopwatch — it schedules alarms for the window above and does
          // nothing outside it — and a button labelled "Track My Sleep" said
          // the opposite of that every hour of the day it stayed on.
          SleepCycleSwitch(
            status: _status,
            busy: _busy,
            onChanged: _busy ? (_) {} : _toggle,
          ),
        ],
      ),
    );
  }

  /// One line of context under the schedule, in priority order: whatever the
  /// tracker measured, then — only when there is nothing to report — what the
  /// window will be.
  ///
  /// A truncated night still shows its hours, with the warning icon rather than
  /// instead of the figure. Replacing the number with "wasn't fully tracked"
  /// read as a failure on nights that had measured six hours and written them
  /// to the log, which is the opposite of what happened.
  Widget _summaryLine() {
    final cut = _night.status == SleepNightStatus.partial && !_night.isEmpty;
    final summary = _night.summary;

    // Nothing measured yet: the window is all there is to say — unless
    // something *was* watched and fell under the floor, in which case saying
    // only the window claims nothing happened on a night that was measured.
    if (summary == null) {
      final short = _night.belowMinimum;
      return Row(
        children: [
          Icon(short ? Icons.timelapse_rounded : Icons.schedule_rounded,
              color: AppColors.onSurfaceVariant, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              short
                  ? '${_night.observedLabel} so far · under the '
                      '${_night.minimumLabel} minimum'
                  : '${_hours(SleepTrackingService.window(_status.bedtime, _status.wake))}'
                      ' in bed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodySm(color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    final inProgress = _night.status == SleepNightStatus.inProgress;
    final awake = _night.awakeInBed;

    // The hours line, then the three counts spelled out underneath.
    //
    // They used to be crammed into one sentence with the hours — "6h 12m · 2
    // wake-ups · 3 pickups" — which ellipsized on a narrow phone and lost
    // exactly the detail it was there to show. Three labelled figures read at
    // a glance and always fit, because each one is short.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(cut ? Icons.warning_amber_rounded : Icons.bedtime_rounded,
                color: AppColors.sleep, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                inProgress ? '$summary so far' : summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyBold(),
              ),
            ),
            if (cut)
              Text('PARTIAL',
                  style: AppText.labelCaps(size: 9, color: AppColors.tertiary)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _miniStat('WAKE-UPS', '${_night.wakeUps}'),
            _miniStat('AWAKE', awake == null ? '—' : '${awake.inMinutes}m'),
            _miniStat('PICKUPS', '${_night.phonePickups}'),
          ],
        ),
      ],
    );
  }

  /// One of the three counts under the hours. Equal thirds so they stay
  /// aligned whatever the values are.
  Widget _miniStat(String label, String value) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyBold().copyWith(fontSize: 15)),
            const SizedBox(height: 1),
            Text(label, style: AppText.labelCaps(size: 8)),
          ],
        ),
      );

  static String _hours(Duration d) => d.inMinutes % 60 == 0
      ? '${d.inHours}h'
      : '${d.inHours}h ${d.inMinutes % 60}m';

  /// Stacked, not side by side. The carousel height is set by the energy
  /// card's ring stack, so this card has vertical room to spare and very
  /// little horizontal — each slot is only half the card. Side by side, a
  /// 52px bubble left ~50px for "10:57 PM" on a 320dp screen and the text
  /// shrank below where it started; stacking gives it the full column.
  Widget _time(IconData icon, String label, String value, Color color,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBubble(
                icon: icon, color: color, size: 64, tinted: true, glow: true),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label.toUpperCase(), style: AppText.labelCaps(size: 10)),
                const SizedBox(width: 3),
                const Icon(Icons.edit_outlined,
                    color: AppColors.onSurfaceVariant, size: 11),
              ],
            ),
            const SizedBox(height: 2),
            // Still guarded: large text scales can outgrow even the full column.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  maxLines: 1,
                  style: AppText.bodyBold().copyWith(fontSize: 20)),
            ),
          ],
        ),
      );
}

/// Off / Armed / Tracking, beside the card's heading.
///
/// Reports whether tracking is *armed*, not whether the service is running.
/// Those differ for most of the day: arming at 3pm with a 22:30 bedtime
/// schedules the alarms and starts nothing, and reading the service state made
/// the control look like the tap had failed.
class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.phase, required this.busy});

  final SleepTrackingPhase phase;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 14,
        height: 14,
        child:
            CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
      );
    }

    final color = switch (phase) {
      SleepTrackingPhase.active => AppColors.secondary,
      SleepTrackingPhase.armed => AppColors.tertiary,
      SleepTrackingPhase.off => AppColors.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bedtime_rounded, color: color, size: 11),
          const SizedBox(width: 4),
          Text(phase.label, style: AppText.labelCaps(color: color, size: 10)),
        ],
      ),
    );
  }
}

// ── Steps ─────────────────────────────────────────────────────────────────
class _StepsCard extends StatelessWidget {
  const _StepsCard(
      {required this.profile, required this.log, required this.pedo});

  final UserProfile? profile;
  final DailyLog? log;
  final PedometerService pedo;

  @override
  Widget build(BuildContext context) {
    final dbSteps = log?.steps ?? 0;
    final burned = log?.caloriesBurned ?? 0;
    final goal = profile?.stepsGoal ?? 10000;

    return StreamBuilder<int>(
      stream: PedometerService.stepsController.stream,
      initialData: pedo.todaySteps > 0 ? pedo.todaySteps : dbSteps,
      builder: (context, snap) {
        // Monotonic, same rule as MealService.setSteps: a lower reading is a
        // source that lost its count, not a correction. The live pedometer
        // stream can legitimately emit a fresh 0 right after install — no
        // local baseline yet — and that must not blank out a total the
        // server already confirmed for today.
        final steps = math.max(snap.data ?? 0, dbSteps);
        final km = (steps * 0.00075).toStringAsFixed(1);

        return TerraCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              ProgressRing(
                value: goal <= 0 ? 0 : steps / goal,
                color: AppColors.secondary,
                size: 92,
                strokeWidth: 10,
                glow: true,
                center: const Icon(Icons.directions_run_rounded,
                    color: AppColors.secondary, size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.dailySteps,
                        style: AppText.labelCaps(
                            color: AppColors.onSurface, size: 12)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(_thousands(steps),
                            style: AppText.display(color: AppColors.secondary)
                                .copyWith(fontSize: 28)),
                        const SizedBox(width: 4),
                        Text('/ ${(goal / 1000).round()}k',
                            style: AppText.bodySm(
                                color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('~ $km KM COVERED',
                        style: AppText.labelCaps(size: 10)),
                    const SizedBox(height: 2),
                    Text('~ $burned KCAL BURNED',
                        style: AppText.labelCaps(
                            color: AppColors.secondary, size: 10)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _thousands(int v) {
    final s = v.toString();
    if (s.length <= 3) return s;
    return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
  }
}

// ── Meals ─────────────────────────────────────────────────────────────────
class _MealsList extends ConsumerWidget {
  const _MealsList({required this.meals});

  final List<Meal> meals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(mealScheduleProvider);
    // Meals logged against a slot the user has since deleted still exist in
    // the database. Appending their keys keeps that food visible instead of
    // silently dropping it off the dashboard.
    final keys = [
      for (final s in slots) s.key,
      ...{for (final m in meals) m.mealType}
          .where((k) => !slots.any((s) => s.key == k)),
    ];

    return Column(
      children: keys.map((type) {
        final items = meals.where((m) => m.mealType == type).toList();
        final kcal = items.fold<int>(0, (s, m) => s + m.calories);
        final logged = items.isNotEmpty;
        final label = MealScheduleService.labelFor(slots, type);
        final accent = MealSlotStyle.accent(type, label: label);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TerraListRow(
            title: label,
            subtitle: logged ? null : 'Not logged yet',
            subtitleWidget: logged
                ? FoodIconStrip(foodNames: [for (final m in items) m.foodName])
                : null,
            icon: MealSlotStyle.icon(type, label: label),
            iconColor: accent,
            dimmed: !logged,
            onTap: () async {
              if (!await requireAccount(context, action: 'log a meal')) return;
              if (context.mounted) context.push('/log-food', extra: type);
            },
            trailing: logged
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$kcal kcal',
                          style: AppText.bodyBold(color: accent)),
                      if (items.first.loggedAt != null)
                        Text(
                          TimeOfDay.fromDateTime(
                                  items.first.loggedAt!.toLocal())
                              .format(context),
                          style: AppText.labelCaps(size: 10),
                        ),
                    ],
                  )
                : MiniPill(
                    label: 'Add',
                    background: AppColors.tertiaryContainer,
                    foreground: AppColors.onTertiaryContainer,
                    border: AppColors.tertiaryContainer,
                    onTap: () async {
                      if (!await requireAccount(context,
                          action: 'log a meal')) {
                        return;
                      }
                      if (context.mounted) {
                        context.push('/log-food', extra: type);
                      }
                    },
                  ),
          ),
        );
      }).toList(),
    );
  }
}
