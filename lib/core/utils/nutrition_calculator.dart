import 'dart:math' as math;

/// Calorie and macro anchors for one goal.
///
/// Protein and fat are grams per kg of body weight rather than a share of
/// calories, which is the whole point of this rewrite — see [dailyTargets].
class _GoalSpec {
  const _GoalSpec({
    required this.calorieFactor,
    required this.proteinPerKg,
    required this.fatPerKg,
  });

  /// Multiplier on TDEE. A share rather than a flat ±500 kcal: the same 500
  /// is a crash diet for someone maintaining on 1600 and barely a nudge for
  /// someone on 3500. 0.80 lands everyone at roughly 0.5–1% of bodyweight per
  /// week, which is the range people actually sustain.
  final double calorieFactor;

  final double proteinPerKg;
  final double fatPerKg;
}

/// Mifflin-St Jeor BMR, activity multipliers, and goal-anchored macro targets.
class NutritionCalculator {
  static double bmr({
    required String gender,
    required double weightKg,
    required double heightCm,
    required int age,
  }) {
    final base = (10 * weightKg) + (6.25 * heightCm) - (5 * age);
    return gender.toLowerCase() == 'male' ? base + 5 : base - 161;
  }

  static double activityMultiplier(String level) {
    switch (level.toLowerCase()) {
      case 'sedentary':
        return 1.2;
      case 'lightly active':
        return 1.375;
      case 'moderately active':
        return 1.55;
      case 'very active':
        return 1.725;
      default:
        return 1.375;
    }
  }

  /// Protein is highest while cutting, not while bulking. Muscle is lost in a
  /// deficit unless protein is kept up, whereas beyond ~2.2 g/kg the benefit
  /// plateaus — so a surplus buys nothing extra and only displaces the carbs
  /// that fuel the training doing the actual work.
  static const _goals = <String, _GoalSpec>{
    'lose weight':
        _GoalSpec(calorieFactor: 0.80, proteinPerKg: 2.0, fatPerKg: 0.9),
    'gain weight':
        _GoalSpec(calorieFactor: 1.15, proteinPerKg: 1.6, fatPerKg: 1.0),
    'build muscle':
        _GoalSpec(calorieFactor: 1.10, proteinPerKg: 1.8, fatPerKg: 1.0),
    'stay active':
        _GoalSpec(calorieFactor: 1.00, proteinPerKg: 1.6, fatPerKg: 1.0),
    'maintain weight':
        _GoalSpec(calorieFactor: 1.00, proteinPerKg: 1.4, fatPerKg: 1.0),
    // Retired label, still present on profiles created before the goal list
    // changed. Mapped rather than dropped so those users keep sane targets.
    'improve fitness':
        _GoalSpec(calorieFactor: 1.00, proteinPerKg: 1.6, fatPerKg: 1.0),
  };

  static const _maintain =
      _GoalSpec(calorieFactor: 1.00, proteinPerKg: 1.4, fatPerKg: 1.0);

  /// Never prescribe less than this, even in a deficit.
  static const _floorMale = 1500.0;
  static const _floorFemale = 1200.0;

  /// Hormone production and fat-soluble vitamin absorption both suffer below
  /// roughly this much fat, so it holds even if the carb remainder suffers.
  static const _fatFloorPerKg = 0.8;

  /// Daily targets for one profile.
  ///
  /// Protein and fat are set from body weight and carbohydrate takes whatever
  /// calories are left. The previous version split calories 30/45/25 for every
  /// goal, which inverted the thing that matters: protein scales with the lean
  /// mass you are trying to keep, not with how much you happen to be eating.
  /// A percentage split cuts protein exactly when a deficit makes it most
  /// necessary, and inflates it during a surplus — a 70 kg user building
  /// muscle was being told to eat 215 g, over 3 g/kg.
  static Map<String, num> dailyTargets({
    required String gender,
    required int age,
    required double heightCm,
    required double weightKg,
    required String goal,
    required String activityLevel,
    // Extra nudge on top of the goal's own calorieFactor, for the weekly
    // check-in to deepen a deficit/surplus that isn't moving the scale
    // despite the user actually following it. 1.0 (unchanged) for onboarding
    // and any other caller that just wants the plain goal-based target.
    double intensityMultiplier = 1.0,
  }) {
    final basal =
        bmr(gender: gender, weightKg: weightKg, heightCm: heightCm, age: age);
    final tdee = basal * activityMultiplier(activityLevel);
    final spec = _goals[goal.toLowerCase().trim()] ?? _maintain;

    // Two floors, whichever binds harder: eating under your own BMR is not a
    // target worth handing someone, and the absolute minimums catch the small,
    // sedentary profiles where even a percentage deficit goes too low.
    final isMale = gender.toLowerCase() == 'male';
    final floor = math.max(basal, isMale ? _floorMale : _floorFemale);
    final calories =
        math.max(tdee * spec.calorieFactor * intensityMultiplier, floor);

    // Per-kg scaling on total mass overshoots badly at high BMI — a 120 kg
    // user would be told to eat 240 g of protein. Requirements track lean
    // mass, so the basis is capped at the weight this height would carry at
    // BMI 25 and only counts the excess once.
    final heightM = heightCm / 100;
    final basisKg = math.min(weightKg, 25 * heightM * heightM);

    final proteinG = spec.proteinPerKg * basisKg;
    final fatG = math.max(spec.fatPerKg * basisKg, _fatFloorPerKg * basisKg);

    // Carbohydrate absorbs the remainder. Clamped at zero for the pathological
    // case where the calorie floor sits below protein + fat; the floors above
    // make that unreachable for a plausible profile, but a negative target
    // would render as nonsense rather than fail loudly.
    final carbsG = math.max(0.0, (calories - (proteinG * 4) - (fatG * 9)) / 4);

    // 14 g per 1000 kcal is the dietary guideline, but a deep cut drives that
    // below what keeps digestion comfortable, so it does not go under 25 g.
    final fiberG = math.max(25.0, (calories / 1000) * 14);

    return {
      'calories': calories.round(),
      'protein_g': double.parse(proteinG.toStringAsFixed(1)),
      'carbs_g': double.parse(carbsG.toStringAsFixed(1)),
      'fat_g': double.parse(fatG.toStringAsFixed(1)),
      'fiber_g': double.parse(fiberG.toStringAsFixed(1)),
      'water_ml': 4000,
      'steps': 10000,
      'sleep_hrs': 8.0,
    };
  }

  static double bmi(double weightKg, double heightCm) {
    final m = heightCm / 100;
    return weightKg / (m * m);
  }
}
