import '../models/user_profile.dart';
import '../models/daily_log.dart';
import '../models/meal.dart';
import 'gemini_proxy_client.dart';

/// Text-only Gemini service for the AI Coach.
///
/// Calls go through the `gemini-proxy` edge function rather than the Gemini
/// SDK directly — see [GeminiProxyClient] for why.
class GeminiService {
  // ─── Helpers ────────────────────────────────────────────────────────────────

  String _pct(double consumed, double goal) {
    if (goal <= 0) return '0%';
    return '${(consumed / goal * 100).round()}%';
  }

  String _rem(double consumed, double goal) {
    final r = goal - consumed;
    return r > 0 ? '${r.toStringAsFixed(0)}g remaining' : 'GOAL MET ✓';
  }

  String _remKcal(int consumed, int goal) {
    final r = goal - consumed;
    return r > 0 ? '$r kcal remaining' : 'GOAL MET ✓';
  }

  String _remMl(int consumed, int goal) {
    final r = goal - consumed;
    return r > 0 ? '${r}ml remaining' : 'GOAL MET ✓';
  }

  String _mealBreakdown(List<Meal> meals) {
    if (meals.isEmpty) return '  (no meals logged yet today)';
    final sb = StringBuffer();
    for (final m in meals) {
      final time =
          '${m.date.hour.toString().padLeft(2, '0')}:${m.date.minute.toString().padLeft(2, '0')}';
      sb.writeln(
        '  • [${m.mealType}] ${m.foodName} — '
        '${m.calories} kcal | P:${m.proteinG.toStringAsFixed(1)}g '
        'C:${m.carbsG.toStringAsFixed(1)}g F:${m.fatG.toStringAsFixed(1)}g  @ $time',
      );
    }
    return sb.toString().trimRight();
  }

  // ─── System Prompt ──────────────────────────────────────────────────────────

  String buildSystemPrompt(
    UserProfile p,
    DailyLog? log, {
    String language = 'en',
    List<Meal> meals = const [],
  }) {
    final lang = {
          'en': 'English',
          'hi': 'Hindi',
          'ta': 'Tamil',
          'te': 'Telugu',
        }[language] ??
        'English';

    final dl = log ?? DailyLog(userId: p.id, date: DateTime.now());

    // Computed remaining values
    final calRem = _remKcal(dl.caloriesConsumed, p.calorieGoal);
    final protRem = _rem(dl.proteinG, p.proteinGoalG);
    final carbRem = _rem(dl.carbsG, p.carbsGoalG);
    final fatRem = _rem(dl.fatG, p.fatGoalG);
    final fiberRem = _rem(dl.fiberG, p.fiberGoalG);
    final waterRem = _remMl(dl.waterMl, p.waterGoalMl);

    final calPct =
        _pct(dl.caloriesConsumed.toDouble(), p.calorieGoal.toDouble());
    final protPct = _pct(dl.proteinG, p.proteinGoalG);
    final carbPct = _pct(dl.carbsG, p.carbsGoalG);
    final fatPct = _pct(dl.fatG, p.fatGoalG);

    // Net calories (consumed - burned)
    final netCal = dl.caloriesConsumed - dl.caloriesBurned;

    return '''
You are Proteinix Coach, a personal fitness and nutrition assistant specialized for Indian users.

════════════════════════════════════════
USER PROFILE
════════════════════════════════════════
Name           : ${p.name ?? 'User'}
Age / Gender   : ${p.age ?? '-'} / ${p.gender ?? '-'}
Height / Weight: ${p.heightCm ?? '-'} cm / ${p.weightKg ?? '-'} kg
Goal           : ${p.goal ?? 'Maintain weight'}
Activity Level : ${p.activityLevel ?? 'Moderate'}

════════════════════════════════════════
TODAY'S NUTRITION PROGRESS  (${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year})
════════════════════════════════════════
CALORIES
  Consumed : ${dl.caloriesConsumed} kcal  ($calPct of ${p.calorieGoal} kcal goal)
  Burned   : ${dl.caloriesBurned} kcal (activity)
  Net      : $netCal kcal
  ▶ $calRem

PROTEIN
  Consumed : ${dl.proteinG.toStringAsFixed(1)}g  ($protPct of ${p.proteinGoalG.toStringAsFixed(0)}g goal)
  ▶ $protRem

CARBOHYDRATES
  Consumed : ${dl.carbsG.toStringAsFixed(1)}g  ($carbPct of ${p.carbsGoalG.toStringAsFixed(0)}g goal)
  ▶ $carbRem

FAT
  Consumed : ${dl.fatG.toStringAsFixed(1)}g  ($fatPct of ${p.fatGoalG.toStringAsFixed(0)}g goal)
  ▶ $fatRem

FIBER
  Consumed : ${dl.fiberG.toStringAsFixed(1)}g  (goal: ${p.fiberGoalG.toStringAsFixed(0)}g)
  ▶ $fiberRem

WATER
  Consumed : ${dl.waterMl}ml  (goal: ${p.waterGoalMl}ml)
  ▶ $waterRem

STEPS  : ${dl.steps} / ${p.stepsGoal}
SLEEP  : ${dl.sleepHrs.toStringAsFixed(1)} hrs / ${p.sleepGoalHrs.toStringAsFixed(1)} hrs

════════════════════════════════════════
MEALS LOGGED TODAY
════════════════════════════════════════
${_mealBreakdown(meals)}

════════════════════════════════════════
INSTRUCTIONS FOR YOU (AI Coach)
════════════════════════════════════════
1. ALWAYS use the exact numbers above when answering macro/calorie questions.
   - When user asks "how much protein do I need?", reply with the EXACT remaining grams shown above.
   - Never make up numbers — use ONLY the data provided.
2. Suggest SPECIFIC Indian foods to fill remaining macros.
   - Protein gaps → paneer, dal, chana, eggs, chicken, curd, sprouts, tofu
   - Carb gaps → roti, rice, oats, banana, sweet potato
   - Fat gaps → ghee, nuts, avocado, coconut
3. If a goal is already met, say so clearly and congratulate the user.
4. Keep responses concise and friendly (3-5 short paragraphs max).
5. Respond in $lang using simple words.
6. Personalize advice based on the user's goal (${p.goal ?? 'maintain'}).
   - Weight loss → prioritise protein, suggest deficit-friendly foods
   - Muscle gain → high protein + calorie surplus suggestions
   - Maintenance → balanced macro guidance
7. Mention meal timing if relevant (e.g., pre/post workout, dinner suggestions).
''';
  }

  // ─── Chat ───────────────────────────────────────────────────────────────────

  Future<String> sendMessage({
    required UserProfile profile,
    required DailyLog? log,
    required List<({String role, String text})> history,
    required String userMessage,
    String language = 'en',
    List<Meal> meals = const [],
  }) async {
    final systemPrompt =
        buildSystemPrompt(profile, log, language: language, meals: meals);

    final contents = <Map<String, dynamic>>[
      {
        'role': 'user',
        'parts': [
          {'text': systemPrompt}
        ],
      },
    ];
    for (final m in history) {
      contents.add({
        'role': m.role == 'user' ? 'user' : 'model',
        'parts': [
          {'text': m.text}
        ],
      });
    }
    contents.add({
      'role': 'user',
      'parts': [
        {'text': userMessage}
      ],
    });

    final text = await GeminiProxyClient.generate(
      kind: 'text',
      contents: contents,
      generationConfig: const {
        'temperature': 0.7,
        'maxOutputTokens': 1024,
      },
    );
    return text.isEmpty ? 'Sorry, I could not respond right now.' : text;
  }
}
