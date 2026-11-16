import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/nutrition_calculator.dart';
import '../models/local/local_weight_log.dart';
import '../models/user_profile.dart';
import 'local_db_service.dart';
import 'sync_service.dart';

/// What a check-in concluded, for the result sheet to render.
enum CheckinOutcome { onTrack, recalibrated, stayConsistent }

class CheckinResult {
  const CheckinResult({
    required this.outcome,
    required this.deltaKg,
    this.newTargets,
    this.weakAreas = const [],
  });

  final CheckinOutcome outcome;
  final double deltaKg;

  /// Set only when [outcome] is [CheckinOutcome.recalibrated].
  final Map<String, num>? newTargets;

  /// Set only when [outcome] is [CheckinOutcome.stayConsistent] — which
  /// daily goals were missed most often over the past week.
  final List<String> weakAreas;
}

/// Periodic weigh-in that checks whether the user is actually trending
/// toward their goal and, if not, whether that's a targets problem or an
/// adherence problem before touching anything.
///
/// The distinction is the whole point: recalculating a deficit that was
/// never really followed just moves a number without fixing anything, and
/// telling someone who *did* follow the plan to "try harder" when the
/// targets themselves were wrong is the wrong message.
class WeightCheckinService {
  /// Long enough to separate a real trend from ordinary day-to-day
  /// water/food-weight noise, short enough that a wrong target doesn't run
  /// unnoticed for long.
  static const checkinInterval = Duration(days: 7);

  /// Below this, a week-over-week change reads as noise rather than trend.
  static const _noiseThresholdKg = 0.2;

  /// How much drift "maintain" tolerates before it counts as off track.
  static const _maintainToleranceKg = 1.0;

  /// A day counts as "on plan" for a metric once it clears this fraction of
  /// goal — 100% every single day isn't realistic or required.
  static const _dayMetThreshold = 0.85;

  /// Share of the week's four daily metrics that need to be on-plan for a
  /// miss to be blamed on the targets rather than on adherence.
  static const _adherenceGoodThreshold = 0.7;

  /// When the user was last asked, whether or not they answered.
  ///
  /// Separate from the weight history because *skipping* has to count too. A
  /// prompt anchored only to the last recorded weigh-in re-fires on every
  /// dashboard build until the user gives it a number, which is a modal the
  /// user cannot get rid of by declining it.
  static const _prefsAnchor = 'weight_checkin_anchor';

  /// Whether it's time to prompt for a new weigh-in.
  ///
  /// Due-ness is measured from the later of the last real weigh-in and the
  /// last time we asked. Both matter: recording a weight obviously restarts
  /// the week, but so does declining, otherwise "Skip for now" means "ask me
  /// again in a few seconds".
  ///
  /// An account with neither — every profile that predates this feature, plus
  /// anyone who reached the dashboard without onboarding writing a baseline —
  /// is *seeded* rather than prompted. It used to fall back to the account's
  /// creation date, which for an existing user is months in the past, so the
  /// check-in read as permanently overdue and reappeared every single time
  /// Home was rebuilt: after editing the profile, after switching tabs, on
  /// every resume. Seeding starts their first full week from now instead.
  static Future<bool> isDue(String userId) async {
    final history = LocalDBService.getWeightHistory(userId);
    final prefs = await SharedPreferences.getInstance();
    final anchorText = prefs.getString(_prefsAnchor);
    final anchor = anchorText == null ? null : DateTime.tryParse(anchorText);
    final lastWeighIn = history.isEmpty ? null : history.first.date;

    final last = switch ((lastWeighIn, anchor)) {
      (null, null) => null,
      (final w?, null) => w,
      (null, final a?) => a,
      (final w?, final a?) => w.isAfter(a) ? w : a,
    };

    if (last == null) {
      await markAsked();
      return false;
    }
    return DateTime.now().difference(last) >= checkinInterval;
  }

  /// Restarts the interval. Called whether the user answers or skips.
  static Future<void> markAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAnchor, DateTime.now().toIso8601String());
  }

  static Future<CheckinResult> submit({
    required String userId,
    required UserProfile profile,
    required double newWeightKg,
  }) async {
    final history = LocalDBService.getWeightHistory(userId);
    final previousKg = history.isNotEmpty
        ? history.first.weightKg
        : (profile.weightKg ?? newWeightKg);

    await LocalDBService.saveWeightLog(LocalWeightLog(
      id: LocalDBService.newId(),
      userId: userId,
      weightKg: newWeightKg,
      date: DateTime.now(),
    ));
    // Fire-and-forget, same as every other write path in this app (see
    // MealService._refresh) — the outbox carries it if this fails.
    SyncService.syncPendingData();

    final delta = newWeightKg - previousKg;
    if (_isOnTrack(profile.goal, delta)) {
      return CheckinResult(outcome: CheckinOutcome.onTrack, deltaKg: delta);
    }

    final adherence = _weekAdherence(userId, profile);
    if (adherence.overall >= _adherenceGoodThreshold) {
      final targets = NutritionCalculator.dailyTargets(
        gender: profile.gender ?? 'male',
        age: profile.age ?? 28,
        heightCm: profile.heightCm ?? 170,
        weightKg: newWeightKg,
        goal: profile.goal ?? 'Maintain Weight',
        activityLevel: profile.activityLevel ?? 'Moderately Active',
        intensityMultiplier: _intensityMultiplier(profile.goal, delta),
      );
      return CheckinResult(
        outcome: CheckinOutcome.recalibrated,
        deltaKg: delta,
        newTargets: targets,
      );
    }

    return CheckinResult(
      outcome: CheckinOutcome.stayConsistent,
      deltaKg: delta,
      weakAreas: adherence.weakAreas,
    );
  }

  static bool _isOnTrack(String? goal, double delta) {
    switch (goal) {
      case 'Lose Weight':
        return delta <= -_noiseThresholdKg;
      case 'Gain Weight':
      case 'Build Muscle':
        return delta >= _noiseThresholdKg;
      default:
        return delta.abs() <= _maintainToleranceKg;
    }
  }

  /// How much harder to push the calorie target once the scale shows the
  /// current one isn't working for someone who's actually following it.
  static double _intensityMultiplier(String? goal, double delta) {
    switch (goal) {
      case 'Lose Weight':
        return 0.93;
      case 'Gain Weight':
      case 'Build Muscle':
        return 1.07;
      default:
        // Maintain/Stay Active drifted — pull back toward true maintenance
        // rather than assuming a direction the user never asked for.
        return delta > 0 ? 0.95 : 1.05;
    }
  }

  /// Fraction of the last 7 days that hit protein, steps, sleep and calories
  /// — days with no log at all count as missed on every metric, so a week
  /// the app was barely opened doesn't read as "close enough."
  static ({double overall, List<String> weakAreas}) _weekAdherence(
      String userId, UserProfile profile) {
    const days = 7;
    final today = DateTime.now();
    final logs = LocalDBService.getLogsForRange(
      userId,
      today.subtract(const Duration(days: days)),
      today.subtract(const Duration(days: 1)),
    );

    if (logs.isEmpty) {
      return (
        overall: 0.0,
        weakAreas: const ['protein', 'steps', 'sleep', 'calories']
      );
    }

    int proteinMet = 0, stepsMet = 0, sleepMet = 0, caloriesMet = 0;
    for (final l in logs) {
      if (l.proteinG >= profile.proteinGoalG * _dayMetThreshold) proteinMet++;
      if (l.steps >= profile.stepsGoal * _dayMetThreshold) stepsMet++;
      if (l.sleepHrs >= profile.sleepGoalHrs * _dayMetThreshold) sleepMet++;
      if (_caloriesOnPlan(l.caloriesConsumed, profile)) caloriesMet++;
    }

    final weak = <String>[];
    if (proteinMet / days < 0.5) weak.add('protein');
    if (stepsMet / days < 0.5) weak.add('steps');
    if (sleepMet / days < 0.5) weak.add('sleep');
    if (caloriesMet / days < 0.5) weak.add('calories');

    return (
      overall: (proteinMet + stepsMet + sleepMet + caloriesMet) / (4 * days),
      weakAreas: weak,
    );
  }

  static bool _caloriesOnPlan(int consumed, UserProfile profile) {
    if (consumed <= 0) return false;
    final goalCal = profile.calorieGoal;
    switch (profile.goal) {
      case 'Lose Weight':
        return consumed <= goalCal * 1.1;
      case 'Gain Weight':
      case 'Build Muscle':
        return consumed >= goalCal * 0.9;
      default:
        return consumed >= goalCal * 0.85 && consumed <= goalCal * 1.15;
    }
  }
}
