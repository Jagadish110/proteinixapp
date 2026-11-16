import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/utils/nutrition_calculator.dart';

/// A 70 kg, 175 cm, 28-year-old male — TDEE ≈ 2571 at moderately active.
Map<String, num> targets({
  String goal = 'Maintain Weight',
  String gender = 'male',
  double weightKg = 70,
  double heightCm = 175,
  int age = 28,
  String activity = 'Moderately Active',
}) =>
    NutritionCalculator.dailyTargets(
      gender: gender,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      goal: goal,
      activityLevel: activity,
    );

double kcal(Map<String, num> t) =>
    t['protein_g']! * 4 + t['carbs_g']! * 4 + t['fat_g']! * 9;

void main() {
  group('macros are anchored to body weight, not calorie share', () {
    // The bug this replaced: a 30% split gave this profile 215 g of protein
    // when building muscle, over 3 g/kg, and starved the carbs that fuel it.
    test('building muscle stays inside the evidence range', () {
      final t = targets(goal: 'Build Muscle');
      final perKg = t['protein_g']! / 70;
      expect(perKg, greaterThanOrEqualTo(1.6));
      expect(perKg, lessThanOrEqualTo(2.2));
    });

    // Protein is highest in a deficit, where lean mass is actually at risk —
    // the opposite of what a percentage-of-calories split produces.
    test('cutting prescribes more protein than bulking', () {
      expect(targets(goal: 'Lose Weight')['protein_g']!,
          greaterThan(targets(goal: 'Build Muscle')['protein_g']!));
    });

    test('protein is unchanged by activity level', () {
      expect(targets(goal: 'Lose Weight', activity: 'Sedentary')['protein_g'],
          targets(goal: 'Lose Weight', activity: 'Very Active')['protein_g']);
    });
  });

  group('calorie targets', () {
    test('a deficit is a share of TDEE, not a flat cut', () {
      final small = targets(goal: 'Lose Weight', weightKg: 50, heightCm: 155);
      final large = targets(goal: 'Lose Weight', weightKg: 100, heightCm: 190);
      // A flat −500 would take 31% off the small profile and 14% off the large.
      expect(large['calories']! - small['calories']!, greaterThan(400));
    });

    test('never drops below BMR or the absolute minimum', () {
      // Small, sedentary and cutting — the profile a percentage deficit would
      // otherwise push into genuinely unsafe territory.
      final t = targets(
          goal: 'Lose Weight',
          gender: 'female',
          weightKg: 45,
          heightCm: 150,
          age: 55,
          activity: 'Sedentary');
      expect(t['calories'], greaterThanOrEqualTo(1200));
    });

    test('surplus goals exceed maintenance, deficit goals fall short', () {
      final maintain = targets()['calories']!;
      expect(targets(goal: 'Gain Weight')['calories'], greaterThan(maintain));
      expect(targets(goal: 'Build Muscle')['calories'], greaterThan(maintain));
      expect(targets(goal: 'Lose Weight')['calories'], lessThan(maintain));
    });

    test('gaining weight is a larger surplus than building muscle', () {
      expect(targets(goal: 'Gain Weight')['calories']!,
          greaterThan(targets(goal: 'Build Muscle')['calories']!));
    });
  });

  group('high BMI', () {
    // Scaling per kg of total mass would prescribe 240 g here. Requirements
    // track lean mass, so the basis is capped at BMI 25 for the height.
    test('protein is capped rather than scaling with total mass', () {
      final t = targets(goal: 'Lose Weight', weightKg: 120, heightCm: 170);
      expect(t['protein_g']!, lessThan(160));
      // 25 × 1.7² = 72.25 kg basis × 2.0 g/kg
      expect(t['protein_g']!, closeTo(144.5, 1));
    });

    test('a normal-BMI profile is not capped', () {
      final t = targets(goal: 'Lose Weight', weightKg: 70, heightCm: 175);
      expect(t['protein_g']!, closeTo(140, 1));
    });
  });

  group('every onboarding goal is handled', () {
    // 'Stay Active' used to fall through to the initialiser by accident, and
    // 'Gain Weight' had a branch nothing could select.
    for (final goal in [
      'Lose Weight',
      'Gain Weight',
      'Build Muscle',
      'Stay Active',
      'Maintain Weight',
    ]) {
      test('$goal produces usable targets', () {
        final t = targets(goal: goal);
        expect(t['calories']!, greaterThan(1200));
        expect(t['protein_g']!, greaterThan(0));
        expect(t['carbs_g']!, greaterThan(0));
        expect(t['fat_g']!, greaterThan(0));
      });
    }

    test('an unknown goal falls back to maintenance', () {
      expect(targets(goal: 'nonsense')['calories'],
          targets(goal: 'Maintain Weight')['calories']);
    });

    // Profiles written before the goal list changed still carry this label.
    test('the retired improve fitness label still works', () {
      expect(targets(goal: 'Improve Fitness')['calories'],
          targets(goal: 'Stay Active')['calories']);
    });
  });

  group('invariants', () {
    test('macros add up to the calorie target', () {
      for (final goal in ['Lose Weight', 'Build Muscle', 'Gain Weight']) {
        final t = targets(goal: goal);
        expect(kcal(t), closeTo(t['calories']!.toDouble(), 5),
            reason: '$goal macros must reconstruct its calorie target');
      }
    });

    test('fibre never falls below a workable minimum', () {
      final t = targets(
          goal: 'Lose Weight',
          gender: 'female',
          weightKg: 45,
          heightCm: 150,
          activity: 'Sedentary');
      expect(t['fiber_g']!, greaterThanOrEqualTo(25));
    });

    test('carbohydrate is never negative', () {
      final t = targets(
          goal: 'Lose Weight',
          gender: 'female',
          weightKg: 45,
          heightCm: 150,
          age: 60,
          activity: 'Sedentary');
      expect(t['carbs_g']!, greaterThanOrEqualTo(0));
    });
  });
}
