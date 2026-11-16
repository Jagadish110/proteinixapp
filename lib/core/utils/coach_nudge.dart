import '../../models/daily_log.dart';
import '../../models/user_profile.dart';

enum CoachNudgeKind { start, protein, calories, water, onTrack }

/// The one thing worth telling the user right now, worked out from today's
/// numbers — "26g protein short, eat this".
///
/// Arithmetic, not an AI call: it is instant, works offline, costs nothing and
/// is therefore free on every plan. The chat underneath is where the AI comes
/// in, for the follow-up question.
class CoachNudge {
  const CoachNudge({
    required this.kind,
    required this.headline,
    required this.body,
    required this.followUp,
  });

  final CoachNudgeKind kind;

  /// Short enough to read at a glance: "26g protein short".
  final String headline;

  /// What to do about it: "Eat this: 100g paneer, or …".
  final String body;

  /// The question sent to the AI coach when the user taps through.
  final String followUp;

  /// How much of the day's target should be in by [now].
  ///
  /// Linear from 06:00 to 22:00, with a small floor so the morning is not
  /// treated as "nothing expected yet". Without this, a nudge at 9am would
  /// report the whole day's protein as a shortfall, which is noise.
  static double expectedFraction(DateTime now) {
    final hours = now.hour + now.minute / 60.0;
    return ((hours - 6) / 16).clamp(0.15, 1.0);
  }

  /// Foods that close a protein gap of [gapG] grams. Portions are the app's
  /// own everyday reference servings, rounded — a suggestion, not a log entry.
  ///
  /// [lean] is for when the calorie budget is nearly spent, so the suggestion
  /// has to add protein without adding much else.
  static String proteinFoods(double gapG, {bool lean = false}) {
    if (lean) {
      return 'egg whites, grilled chicken or low-fat curd — protein without '
          'many extra calories';
    }
    if (gapG <= 8) return 'a glass of milk or a boiled egg';
    if (gapG <= 15) return '2 boiled eggs, or a katori of dal with curd';
    if (gapG <= 25) {
      return '100g paneer, or 3 boiled eggs with a glass of milk';
    }
    if (gapG <= 40) {
      return '100g grilled chicken, or 150g paneer with a katori of dal';
    }
    return '100g grilled chicken or 150g paneer now, and eggs or dal at '
        'your next meal';
  }

  static CoachNudge forToday(UserProfile p, DailyLog? log, DateTime now) {
    final protein = log?.proteinG ?? 0;
    final calories = log?.caloriesConsumed ?? 0;
    final water = log?.waterMl ?? 0;

    if (calories <= 0 && protein <= 0) {
      return CoachNudge(
        kind: CoachNudgeKind.start,
        headline: 'Nothing logged yet today',
        body: p.proteinGoalG > 0
            ? 'Log your first meal and you will see exactly what to eat '
                'next. Today\'s protein target is ${p.proteinGoalG.round()}g.'
            : 'Log your first meal and you will see exactly what to eat next.',
        followUp: 'I have not eaten yet today. What should my first meal be '
            'to stay on target?',
      );
    }

    final expected = expectedFraction(now);
    final proteinLeft = p.proteinGoalG - protein;
    final caloriesLeft = p.calorieGoal - calories;

    // Protein first — it is the number this app is named after, and the one
    // that is hardest to make up late in the day.
    if (p.proteinGoalG > 0 && proteinLeft > 0.5) {
      final behind = (p.proteinGoalG * expected) - protein;
      if (behind > 5) {
        final lean = p.calorieGoal > 0 && caloriesLeft < 200;
        final gap = proteinLeft.round();
        return CoachNudge(
          kind: CoachNudgeKind.protein,
          headline: '${gap}g protein short',
          body: 'Eat this: ${proteinFoods(proteinLeft, lean: lean)}.',
          followUp: 'I am ${gap}g short of my protein goal today. What '
              'should I eat next to close the gap?',
        );
      }
    }

    if (p.calorieGoal > 0 && caloriesLeft < 0) {
      final over = -caloriesLeft;
      return CoachNudge(
        kind: CoachNudgeKind.calories,
        headline: '$over kcal over today',
        body: 'Keep the rest of the day light: salad, dal or curd, and skip '
            'the fried sides. One day over does not undo your week.',
        followUp: 'I am $over kcal over my calorie goal today. What should '
            'I do for the rest of the day?',
      );
    }

    if (p.waterGoalMl > 0) {
      final behindMl = (p.waterGoalMl * expected) - water;
      if (behindMl > 500) {
        final glasses = (behindMl / 250).round();
        return CoachNudge(
          kind: CoachNudgeKind.water,
          headline: '$glasses glasses of water behind',
          body: 'Drink a glass now and keep a bottle within reach — small '
              'sips through the day beat catching up at night.',
          followUp: 'I am behind on water today. How should I catch up?',
        );
      }
    }

    if (p.proteinGoalG > 0 && proteinLeft > 0.5) {
      final gap = proteinLeft.round();
      return CoachNudge(
        kind: CoachNudgeKind.onTrack,
        headline: 'On pace — ${gap}g protein to go',
        body: 'Still to come today: ${proteinFoods(proteinLeft)}.',
        followUp: 'I have ${gap}g of protein left for today. Plan the rest '
            'of my day.',
      );
    }

    return const CoachNudge(
      kind: CoachNudgeKind.onTrack,
      headline: 'Protein goal met',
      body: 'Nicely done. Keep the rest of the day balanced and get your '
          'water in.',
      followUp: 'I have hit my protein goal today. Anything else I should '
          'focus on?',
    );
  }
}
