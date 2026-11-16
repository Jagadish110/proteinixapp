import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// One entry in the user's meal schedule.
///
/// [key] and [label] are deliberately separate. The key is what gets written
/// to `Meal.mealType` in Supabase and Hive, so it can never change once a slot
/// exists — renaming "Snack" to "Pre-workout" must not orphan every snack the
/// user has already logged. The label is the only part the user edits.
@immutable
class MealSlot {
  const MealSlot({
    required this.key,
    required this.label,
    required this.time,
  });

  /// Stable identity, persisted on every meal row. Never edited.
  final String key;

  /// What the user sees, and what the reminder says. Freely renameable.
  final String label;

  /// "HH:mm" — when the reminder for this slot fires.
  final String time;

  MealSlot copyWith({String? label, String? time}) => MealSlot(
        key: key,
        label: label ?? this.label,
        time: time ?? this.time,
      );

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'time': time};

  factory MealSlot.fromJson(Map<String, dynamic> j) => MealSlot(
        key: j['key'] as String,
        label: j['label'] as String,
        time: j['time'] as String,
      );

  /// Minutes past midnight, for ordering the day. Unparseable times sort last
  /// rather than throwing.
  int get minuteOfDay {
    final parts = time.split(':');
    if (parts.length != 2) return 24 * 60;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return 24 * 60;
    return h * 60 + m;
  }

  @override
  bool operator ==(Object other) =>
      other is MealSlot &&
      other.key == key &&
      other.label == label &&
      other.time == time;

  @override
  int get hashCode => Object.hash(key, label, time);
}

/// Icon and accent for a slot, keyed off the canonical keys so the four
/// built-in meals keep the look they have always had. Custom slots fall back
/// to a neutral pairing.
class MealSlotStyle {
  const MealSlotStyle._();

  /// Chosen for a protein-and-macros app rather than a generic food one: an
  /// egg reads as a protein breakfast where a coffee cup reads as a drink, and
  /// a grain bowl reads as a tracked lunch where a burger reads as a cheat
  /// meal. The icon a user sees six times a day should look like the app's
  /// point of view.
  static const _icons = <String, IconData>{
    'breakfast': Icons.egg_alt_rounded,
    'lunch': Icons.rice_bowl_rounded,
    'dinner': Icons.dinner_dining_rounded,
    'snack': Icons.cookie_rounded,
  };

  static const _accents = <String, Color>{
    'breakfast': AppColors.primary,
    'lunch': AppColors.secondary,
    'dinner': AppColors.tertiary,
    'snack': AppColors.fiberTeal,
  };

  /// Icons for slots the user renamed, matched on the label.
  ///
  /// Only four slots are built in, so a "Pre-workout" is a *renamed* one and
  /// carries whatever key it started with — a lunch key on a pre-workout meal.
  /// Keying off the label is what stops the most personalised slots being the
  /// ones with a wrong icon.
  static const _byLabel = <String, (IconData, Color)>{
    'pre-workout': (Icons.bolt_rounded, AppColors.secondary),
    'preworkout': (Icons.bolt_rounded, AppColors.secondary),
    'post-workout': (Icons.fitness_center_rounded, AppColors.primary),
    'postworkout': (Icons.fitness_center_rounded, AppColors.primary),
    'brunch': (Icons.brunch_dining_rounded, AppColors.primary),
    'supper': (Icons.dinner_dining_rounded, AppColors.tertiary),
    'shake': (Icons.local_drink_rounded, AppColors.hydrationBlue),
    'protein': (Icons.fitness_center_rounded, AppColors.secondary),
    'smoothie': (Icons.local_drink_rounded, AppColors.fiberTeal),
    'tea': (Icons.emoji_food_beverage_rounded, AppColors.primary),
    'coffee': (Icons.coffee_rounded, AppColors.primary),
    'breakfast': (Icons.egg_alt_rounded, AppColors.primary),
    'lunch': (Icons.rice_bowl_rounded, AppColors.secondary),
    'dinner': (Icons.dinner_dining_rounded, AppColors.tertiary),
    'snack': (Icons.cookie_rounded, AppColors.fiberTeal),
  };

  /// Matches a label loosely — "Pre workout meal" should still find the bolt.
  static (IconData, Color)? _fromLabel(String? label) {
    if (label == null || label.trim().isEmpty) return null;
    final needle = label.toLowerCase().replaceAll(RegExp(r'[\s_]+'), '');
    for (final entry in _byLabel.entries) {
      if (needle.contains(entry.key.replaceAll('-', ''))) return entry.value;
    }
    return null;
  }

  /// [label] takes precedence over [key]: a slot the user has renamed should
  /// look like what they called it, not like the slot it was cloned from.
  static IconData icon(String key, {String? label}) =>
      _fromLabel(label)?.$1 ?? _icons[key] ?? Icons.restaurant_rounded;

  static Color accent(String key, {String? label}) =>
      _fromLabel(label)?.$2 ?? _accents[key] ?? AppColors.primary;
}
