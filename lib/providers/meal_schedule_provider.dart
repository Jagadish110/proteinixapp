import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/meal_slot.dart';
import '../services/meal_schedule_service.dart';

/// The meal schedule, shared by every screen that names a meal.
///
/// Seeded synchronously with the built-in slots so no screen has to render a
/// loading state for something this small; the stored schedule replaces it on
/// the first frame after the read completes.
class MealScheduleNotifier extends StateNotifier<List<MealSlot>> {
  MealScheduleNotifier() : super(MealScheduleService.defaults) {
    _load();
  }

  Future<void> _load() async {
    state = await MealScheduleService.load();
  }

  /// Re-reads from disk. Used when returning from the reminders screen, which
  /// writes the schedule through [MealScheduleService] directly.
  Future<void> refresh() => _load();

  Future<void> replace(List<MealSlot> slots) async {
    state = slots;
    await MealScheduleService.save(slots);
  }
}

final mealScheduleProvider =
    StateNotifierProvider<MealScheduleNotifier, List<MealSlot>>(
        (ref) => MealScheduleNotifier());
