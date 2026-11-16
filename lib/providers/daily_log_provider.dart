import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/date_utils.dart';
import '../models/daily_log.dart';
import '../models/local/local_meal.dart';
import '../models/meal.dart';
import '../models/sleep_result.dart';
import '../models/user_profile.dart';
import '../services/local_db_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import 'auth_provider.dart';

final selectedDateProvider =
    StateProvider<DateTime>((_) => AppDateUtils.toDateOnly(DateTime.now()));

/// Bumped whenever a background sync writes new rows into Hive.
///
/// The data providers below read Hive synchronously, so nothing would tell them
/// a pull had landed — watching this is what turns a completed sync into a
/// repaint.
final dataRevisionProvider = StateProvider<int>((_) => 0);

/// The day's totals, read from the local database.
///
/// Local-first: this never touches the network, which is what lets Home,
/// Nutrition and Progress render with no connection at all. Fresh server data
/// arrives via [SyncService.pullFromSupabase] writing into the same boxes.
///
/// A synchronous [Provider], not a [FutureProvider], and the difference is
/// visible on screen. A Hive read returns immediately, but a FutureProvider
/// still resolves through a microtask: it begins in `AsyncLoading` and drops
/// back into it on every recompute. That painted a spinner for a frame on open
/// and flashed another one each time a sync bumped the revision — data the app
/// already had in hand. Reading synchronously means frame one has the data.
final dailyLogProvider = Provider.family<DailyLog?, DateTime>((ref, date) {
  ref.watch(dataRevisionProvider);
  final uid = SupabaseService.currentUserId;
  if (uid == null) return null;
  return _withMealTotals(LocalDBService.dailyLogOrEmpty(uid, date).toDomain());
});

/// Recomputes the food-derived fields from the day's own meal rows.
///
/// `daily_logs` keeps a *running* total that [MealService.addMeal] increments
/// as food is logged, while `meals` holds the individual rows. Two copies of
/// the same fact drift the moment one of them is written without the other —
/// and they did: signing out clears the local boxes but keeps the outbox, so
/// the aggregate could come back from the server as zeroes while every meal
/// row restored correctly, leaving the dashboard reporting 0/120g protein
/// underneath a full list of the day's food.
///
/// The meals are the source of truth here — each is an independent, idempotent
/// row keyed by its own id — so the totals are derived on read rather than
/// trusted from storage. Steps, water and sleep are untouched: nothing else
/// records them, so the stored figure is all there is.
DailyLog _withMealTotals(DailyLog log) {
  final meals = LocalDBService.getMealsForDate(log.userId, log.date);
  if (meals.isEmpty) return log;

  var kcal = 0;
  var protein = 0.0, carbs = 0.0, fat = 0.0, fiber = 0.0;
  for (final m in meals) {
    kcal += m.calories;
    protein += m.proteinG;
    carbs += m.carbsG;
    fat += m.fatG;
    fiber += m.fiberG;
  }

  return DailyLog(
    id: log.id,
    userId: log.userId,
    date: log.date,
    caloriesConsumed: kcal,
    proteinG: protein,
    carbsG: carbs,
    fatG: fat,
    fiberG: fiber,
    waterMl: log.waterMl,
    steps: log.steps,
    caloriesBurned: log.caloriesBurned,
    sleepHrs: log.sleepHrs,
    sleepQuality: log.sleepQuality,
    sleepInterruptions: log.sleepInterruptions,
    phonePickups: log.phonePickups,
    sleepScore: log.sleepScore,
    sleepStart: log.sleepStart,
    sleepEnd: log.sleepEnd,
    weightKg: log.weightKg,
  );
}

final mealsForDateProvider = Provider.family<List<Meal>, DateTime>((ref, date) {
  ref.watch(dataRevisionProvider);
  final uid = SupabaseService.currentUserId;
  if (uid == null) return const [];
  return LocalDBService.getMealsForDate(uid, date)
      .map((m) => m.toDomain())
      .toList();
});

/// Daily logs over a window, for the Progress charts. Local-only, so the charts
/// keep working offline.
final logsInRangeProvider = Provider.family<List<DailyLog>, int>((ref, days) {
  ref.watch(dataRevisionProvider);
  final uid = SupabaseService.currentUserId;
  if (uid == null) return const [];
  final start = DateTime.now().subtract(Duration(days: days - 1));
  return LocalDBService.getLogsForRange(uid, start, DateTime.now())
      .map((l) => l.toDomain())
      .toList();
});

/// Consecutive days, ending today, on which protein intake met the user's
/// goal — walked backward from today over the local log history.
///
/// Today is skipped rather than treated as a break when it hasn't hit goal
/// yet: the day isn't over, so an unmet goal at (say) 9am shouldn't zero out
/// a streak the user still has all day to keep. The first fully-elapsed day
/// (yesterday and earlier) that missed goal ends the count.
final proteinStreakProvider = Provider<int>((ref) {
  ref.watch(dataRevisionProvider);
  final uid = SupabaseService.currentUserId;
  final goal = ref.watch(profileProvider).value?.proteinGoalG ?? 0;
  if (uid == null || goal <= 0) return 0;

  final today = AppDateUtils.toDateOnly(DateTime.now());
  // A year is far more history than any real streak will reach, so this
  // still returns in one bounded Hive scan.
  final logs = LocalDBService.getLogsForRange(
    uid,
    today.subtract(const Duration(days: 365)),
    today,
  );
  final metByIso = <String, bool>{
    for (final l in logs) AppDateUtils.iso(l.date): l.proteinG >= goal,
  };

  int streak = 0;
  if (metByIso[AppDateUtils.iso(today)] == true) streak++;

  var cursor = today.subtract(const Duration(days: 1));
  while (metByIso[AppDateUtils.iso(cursor)] == true) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
});

class MealService {
  /// Goal alerts only make sense for the day in progress — logging a past day
  /// retroactively shouldn't fire a congratulation.
  static bool _isToday(DateTime date) =>
      AppDateUtils.iso(date) == AppDateUtils.iso(DateTime.now());

  /// Nudges every provider that reads Hive, then lets the sync layer catch up
  /// in the background. Callers never await the upload.
  static void _refresh(WidgetRef ref) {
    ref.read(dataRevisionProvider.notifier).state++;
    SyncService.syncPendingData();
  }

  /// Logs a meal and folds its macros into the day's totals.
  ///
  /// Both writes are local and synchronous-ish, so this succeeds with no
  /// network; the outbox carries them to Supabase later. The aggregate is
  /// recomputed from the local row rather than read back from the server,
  /// which is what makes it correct offline.
  static Future<void> addMeal(WidgetRef ref, Meal m) async {
    final local = LocalMeal.fromDomain(m, id: LocalDBService.newId());
    await LocalDBService.saveMeal(local);

    // Recomputed from the day's meals, not `+=` on whatever was stored.
    // Incrementing assumes the running total was right to begin with, so a
    // single bad starting point (an aggregate wiped on sign-out while the
    // meals survived) stayed wrong for the rest of the day and pushed that
    // wrong figure to the server on every subsequent meal. Summing the rows
    // that already exist makes each write self-correcting — and it matches
    // what the dashboard now displays, so stored and shown can't disagree.
    final log = LocalDBService.dailyLogOrEmpty(m.userId, m.date);
    final meals = LocalDBService.getMealsForDate(m.userId, m.date);
    log.caloriesConsumed = meals.fold(0, (s, x) => s + x.calories);
    log.proteinG = meals.fold(0.0, (s, x) => s + x.proteinG);
    log.carbsG = meals.fold(0.0, (s, x) => s + x.carbsG);
    log.fatG = meals.fold(0.0, (s, x) => s + x.fatG);
    log.fiberG = meals.fold(0.0, (s, x) => s + x.fiberG);
    await LocalDBService.saveDailyLog(log, scope: 'macros');

    _refresh(ref);

    if (_isToday(m.date)) {
      final p = _profile(ref);
      await GoalAlerts.protein(log.proteinG, p?.proteinGoalG ?? 150);
      await GoalAlerts.calories(log.caloriesConsumed, p?.calorieGoal ?? 2000);
    }
  }

  /// Adds [ml] of water to [date]'s total.
  ///
  /// [currentMl] is no longer used to paint an optimistic value — the Hive
  /// write has already landed by the time this returns — but the parameter is
  /// kept so existing call sites compile unchanged.
  static Future<void> addWater(
    WidgetRef ref,
    String uid,
    DateTime date,
    int ml, {
    int currentMl = 0,
  }) async {
    final newTotal = await LocalDBService.addWater(uid, ml, date: date);
    _refresh(ref);

    if (_isToday(date)) {
      await GoalAlerts.water(newTotal, _profile(ref)?.waterGoalMl ?? 2500);
      // Today's reminders quote how much is still owed, and that text is baked
      // in when the alarm is registered — the plugin fires it with no Dart
      // running. Re-registering here is what keeps the figure honest.
      // Unawaited: rewriting the day's slots is one platform call each, and the
      // glass the user just logged should not wait on them.
      unawaited(NotificationService.refreshWaterReminders());
    }
  }

  /// Reads the cached profile without throwing when it hasn't loaded yet.
  static UserProfile? _profile(WidgetRef ref) {
    try {
      return ref.read(profileProvider).value;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setSteps(
    WidgetRef ref,
    String uid,
    DateTime date,
    int steps, {
    int caloriesBurned = 0,
  }) async {
    final log = LocalDBService.dailyLogOrEmpty(uid, date);
    // A direct overwrite, not a monotonic max — this was guarded with
    // "only rises within a day" on the theory that a lower reading always
    // means a source lost its count. [PedometerService.resolveBaseline]
    // already handles the one real case of that (a reboot mid-day) on its
    // own, correctly, before this is ever called. What the guard actually
    // did was permanent: once a bad figure landed here — [PedometerService
    // .todaySteps] used to keep reporting yesterday's count into the small
    // hours because nothing reset it until the day's first step — no
    // legitimate lower correction could ever land afterward either, so the
    // wrong number just sat there, re-synced to the server on every pull.
    // The one caller of this method always computes the best currently-known
    // total, so trusting it outright is what makes a fixed source able to
    // self-correct instead of staying wrong forever.
    log.steps = steps;
    // Only write calories_burned when we have a meaningful value, so a
    // pedometer fallback doesn't overwrite a prior Health Connect read.
    if (caloriesBurned > 0) log.caloriesBurned = caloriesBurned;
    await LocalDBService.saveDailyLog(log, scope: 'steps');

    _refresh(ref);

    if (_isToday(date)) {
      await GoalAlerts.steps(steps, _profile(ref)?.stepsGoal ?? 10000);
    }
  }

  /// Records a night against [date].
  ///
  /// The sampler re-reports the same night on every dashboard refresh, and the
  /// estimate only grows as the night goes on — so a shorter figure than the
  /// one already stored is a re-read of a partial night, not a correction, and
  /// is ignored. That also stops a manual or Health Connect entry from being
  /// overwritten by a worse guess.
  static Future<void> setSleep(
    WidgetRef ref,
    String uid,
    DateTime date,
    double hours, {
    int interruptions = 0,
    int phonePickups = 0,
    DateTime? sleepStart,
    DateTime? sleepEnd,
  }) async {
    if (hours <= 0) return;

    final log = LocalDBService.dailyLogOrEmpty(uid, date);
    if (hours < log.sleepHrs) return;

    log.sleepHrs = hours;
    log.sleepInterruptions = interruptions;
    // Monotonic like the hours, and for the same reason: a night re-read at
    // 3am and again at 7am should not lose the pickups the first read saw.
    if (phonePickups > log.phonePickups) log.phonePickups = phonePickups;
    if (sleepStart != null) log.sleepStart = sleepStart;
    if (sleepEnd != null) log.sleepEnd = sleepEnd;
    // Derived, never passed in — so the stored score always matches the stored
    // figures, and a change to the scoring rules reaches history on next write.
    log.sleepScore = SleepResult(
      sleepHours: hours,
      interruptions: interruptions,
      phonePickups: log.phonePickups,
      date: date,
    ).sleepScore;
    await LocalDBService.saveDailyLog(log, scope: 'sleep');

    _refresh(ref);
  }

  static Future<void> deleteMeal(
      WidgetRef ref, String uid, String? mealId, DateTime date) async {
    if (mealId == null) return;

    await LocalDBService.deleteMeal(mealId);

    // Recomputed from what's left, for the same reason as addMeal: the
    // subtraction this replaces could only ever be as correct as the total it
    // started from, and no clamp recovers a figure that was already wrong.
    // Unconditional now — summing the remaining rows is right even when the
    // deleted meal wasn't found locally, which the old guard treated as a
    // reason to leave a possibly-stale aggregate untouched.
    final log = LocalDBService.dailyLogOrEmpty(uid, date);
    final meals = LocalDBService.getMealsForDate(uid, date);
    log.caloriesConsumed = meals.fold(0, (s, x) => s + x.calories);
    log.proteinG = meals.fold(0.0, (s, x) => s + x.proteinG);
    log.carbsG = meals.fold(0.0, (s, x) => s + x.carbsG);
    log.fatG = meals.fold(0.0, (s, x) => s + x.fatG);
    log.fiberG = meals.fold(0.0, (s, x) => s + x.fiberG);
    await LocalDBService.saveDailyLog(log, scope: 'macros');

    _refresh(ref);
  }

  static Future<void> addQuickMeal(WidgetRef ref, String uid, DateTime date,
      String type, String name, int cal) async {
    final meal = Meal(
      userId: uid,
      date: date,
      mealType: type,
      foodName: name,
      calories: cal,
      logMethod: 'quick',
    );
    await addMeal(ref, meal);
  }
}
