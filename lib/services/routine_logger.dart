import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/date_utils.dart';
import '../models/meal.dart';
import '../models/meal_slot.dart';
import '../providers/daily_log_provider.dart';
import 'routine_service.dart';

/// Which saved meal the user tends to log for which meal slot.
///
/// A plain tally — routine id → slot key → times logged — kept on the device.
/// It is a convenience, not a record: losing it costs nothing but the
/// suggestion, which rebuilds itself after a log or two, so it does not go
/// through the sync layer.
class RoutineUsage {
  const RoutineUsage(this._counts);

  final Map<String, Map<String, int>> _counts;

  static const empty = RoutineUsage({});

  static const _prefsKey = 'routine_usage_v1';

  int count(String routineId, String slotKey) =>
      _counts[routineId]?[slotKey] ?? 0;

  RoutineUsage recorded(String routineId, String slotKey) {
    final next = {
      for (final e in _counts.entries) e.key: Map<String, int>.of(e.value),
    };
    final slots = next.putIfAbsent(routineId, () => {});
    slots[slotKey] = (slots[slotKey] ?? 0) + 1;
    return RoutineUsage(next);
  }

  String encode() => jsonEncode(_counts);

  static RoutineUsage decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return RoutineUsage({
        for (final e in json.entries)
          e.key: {
            for (final s in (e.value as Map<String, dynamic>).entries)
              s.key: (s.value as num).toInt(),
          },
      });
    } catch (_) {
      return empty;
    }
  }

  static Future<RoutineUsage> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decode(prefs.getString(_prefsKey));
    } catch (_) {
      return empty;
    }
  }

  static Future<void> record(String routineId, String slotKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next =
          decode(prefs.getString(_prefsKey)).recorded(routineId, slotKey);
      await prefs.setString(_prefsKey, next.encode());
    } catch (_) {}
  }

  /// The saved meal to offer as "your usual" for [slot], or null.
  ///
  /// The one logged most often in that slot wins. With no history yet, a
  /// routine the user *named* after the slot ("My usual breakfast") is taken
  /// at its word. Nothing is suggested otherwise — a guess that is wrong is
  /// worse than no suggestion on a card this prominent.
  SavedRoutine? usualFor(List<SavedRoutine> routines, MealSlot slot) {
    SavedRoutine? best;
    var bestCount = 0;
    for (final r in routines) {
      if (r.items.isEmpty) continue;
      final n = count(r.id, slot.key);
      if (n > bestCount) {
        best = r;
        bestCount = n;
      }
    }
    if (best != null) return best;

    final label = slot.label.trim().toLowerCase();
    final key = slot.key.trim().toLowerCase();
    for (final r in routines) {
      if (r.items.isEmpty) continue;
      final name = r.name.toLowerCase();
      if ((label.isNotEmpty && name.contains(label)) ||
          (key.isNotEmpty && name.contains(key))) {
        return r;
      }
    }
    return null;
  }
}

/// Logs a saved meal — a "Quick Pick", a usual meal, or one of the user's own
/// dishes — into a meal slot.
class RoutineLogger {
  const RoutineLogger._();

  /// The portion multipliers offered when logging a saved meal by portion.
  static const portionChoices = <double>[0.5, 1, 1.5, 2, 3];

  static String portionLabel(double portions) {
    if (portions == 0.5) return '½';
    if (portions == 1.5) return '1½';
    return portions == portions.roundToDouble()
        ? portions.toInt().toString()
        : portions.toString();
  }

  /// [item] scaled to [portions] servings of the saved meal.
  static RoutineItem scaled(RoutineItem item, double portions) => RoutineItem(
        name: item.name,
        quantity: item.quantity * portions,
        unit: item.unit,
        calories: (item.calories * portions).round(),
        proteinG: item.proteinG * portions,
        carbsG: item.carbsG * portions,
        fatG: item.fatG * portions,
        fiberG: item.fiberG * portions,
      );

  /// Total calories for [portions] servings of [routine].
  static int caloriesFor(SavedRoutine routine, double portions) => routine.items
      .fold(0, (sum, i) => sum + scaled(i, portions).calories);

  /// Writes every item of [routine] to today's [mealType], scaled to
  /// [portions], and remembers that this meal was logged for that slot.
  ///
  /// Returns the calories logged. Throws if a write fails, so the caller can
  /// say so instead of reporting a meal that is only half there.
  static Future<int> log(
    WidgetRef ref, {
    required String uid,
    required SavedRoutine routine,
    required String mealType,
    double portions = 1,
  }) async {
    final date = AppDateUtils.toDateOnly(DateTime.now());
    var total = 0;
    for (final raw in routine.items) {
      final item = scaled(raw, portions);
      await MealService.addMeal(
        ref,
        Meal(
          userId: uid,
          date: date,
          mealType: mealType,
          foodName: item.name,
          quantity: item.quantity,
          unit: item.unit,
          calories: item.calories,
          proteinG: item.proteinG,
          carbsG: item.carbsG,
          fatG: item.fatG,
          fiberG: item.fiberG,
          logMethod: 'quick',
        ),
      );
      total += item.calories;
    }
    await RoutineUsage.record(routine.id, mealType);
    return total;
  }
}
