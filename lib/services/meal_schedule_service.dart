import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/meal_slot.dart';

/// The one place the app's meal slots are defined.
///
/// Every screen that offers "which meal is this?" — the dashboard breakdown,
/// the nutrition tab, log food, the scanner, the AI results — reads from here,
/// so renaming a slot or adding one shows up everywhere at once.
///
/// Storage stays alongside the reminder preferences that already existed
/// (`notif_meal_times` / `notif_meal_labels`) so the scheduling code keeps
/// working untouched; this adds `notif_meal_keys` for the stable identity
/// those two arrays never had.
class MealScheduleService {
  const MealScheduleService._();

  static const _keyKeys = 'notif_meal_keys';
  static const _keyLabels = 'notif_meal_labels';
  static const _keyTimes = 'notif_meal_times';

  /// Matches the reminder scheduler's slot ceiling.
  static const maxSlots = 5;

  /// The four built-ins, in the order they have always been stored. Existing
  /// `Meal.mealType` values in Supabase are exactly these strings.
  static const defaults = <MealSlot>[
    MealSlot(key: 'breakfast', label: 'Breakfast', time: '08:00'),
    MealSlot(key: 'lunch', label: 'Lunch', time: '13:00'),
    MealSlot(key: 'dinner', label: 'Dinner', time: '19:00'),
    MealSlot(key: 'snack', label: 'Snack', time: '16:00'),
  ];

  static List<String> get defaultKeys => [for (final s in defaults) s.key];

  static Future<List<MealSlot>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs);
  }

  static List<MealSlot> _read(SharedPreferences prefs) {
    final labels = _decode(prefs.getString(_keyLabels));
    final times = _decode(prefs.getString(_keyTimes));
    if (labels.isEmpty || times.isEmpty) return defaults;

    // Installs that predate the key array stored slots positionally, and the
    // first four were always breakfast/lunch/dinner/snack in that order.
    final keys = _decode(prefs.getString(_keyKeys));

    final count = labels.length < times.length ? labels.length : times.length;
    final slots = <MealSlot>[];
    for (var i = 0; i < count && i < maxSlots; i++) {
      slots.add(MealSlot(
        key: i < keys.length && keys[i].isNotEmpty
            ? keys[i]
            : (i < defaults.length ? defaults[i].key : 'meal_$i'),
        label: labels[i],
        time: times[i],
      ));
    }
    return slots.isEmpty ? defaults : slots;
  }

  static List<String> _decode(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return List<String>.from(jsonDecode(json) as List);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<MealSlot> slots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyKeys, jsonEncode([for (final s in slots) s.key]));
    await prefs.setString(
        _keyLabels, jsonEncode([for (final s in slots) s.label]));
    await prefs.setString(
        _keyTimes, jsonEncode([for (final s in slots) s.time]));
  }

  /// A key that cannot collide with the built-ins or with an existing slot.
  static String newKey(List<MealSlot> existing) {
    final taken = {for (final s in existing) s.key};
    var i = existing.length;
    while (taken.contains('meal_$i')) {
      i++;
    }
    return 'meal_$i';
  }

  /// Resolves a stored `Meal.mealType` to its display label.
  ///
  /// Falls back to a title-cased key so meals logged against a slot the user
  /// has since deleted still render with a sensible name instead of vanishing.
  static String labelFor(List<MealSlot> slots, String key) {
    for (final s in slots) {
      if (s.key == key) return s.label;
    }
    if (key.isEmpty) return 'Meal';
    return key[0].toUpperCase() + key.substring(1).replaceAll('_', ' ');
  }

  /// The slot a meal logged right now most likely belongs to: the latest slot
  /// whose time has already passed, or the earliest slot if the day has not
  /// reached one yet.
  static String currentKey(List<MealSlot> slots, DateTime now) {
    if (slots.isEmpty) return defaults.first.key;
    final ordered = [...slots]
      ..sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));
    final minutes = now.hour * 60 + now.minute;
    var chosen = ordered.first;
    for (final slot in ordered) {
      if (slot.minuteOfDay <= minutes) chosen = slot;
    }
    return chosen.key;
  }
}
