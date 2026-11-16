import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_scan_result.dart';
import '../models/local/local_meal_routine.dart';
import 'local_db_service.dart';

/// A single food item saved inside a routine
class RoutineItem {
  final String name;
  final double quantity;
  final String unit;
  final int calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;

  const RoutineItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
  });

  factory RoutineItem.fromFoodItem(FoodItem item) => RoutineItem(
        name: item.name,
        quantity: item.quantity,
        unit: item.unit,
        calories: item.calories,
        proteinG: item.proteinG,
        carbsG: item.carbsG,
        fatG: item.fatG,
        fiberG: item.fiberG,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'fiber_g': fiberG,
      };

  factory RoutineItem.fromJson(Map<String, dynamic> j) => RoutineItem(
        name: j['name'] as String,
        quantity: (j['quantity'] as num).toDouble(),
        unit: j['unit'] as String,
        calories: (j['calories'] as num).toInt(),
        proteinG: (j['protein_g'] as num).toDouble(),
        carbsG: (j['carbs_g'] as num).toDouble(),
        fatG: (j['fat_g'] as num).toDouble(),
        fiberG: (j['fiber_g'] as num).toDouble(),
      );

  int get totalCal => calories;
}

/// A saved meal routine (named list of food items)
class SavedRoutine {
  final String id;
  final String name;
  final List<RoutineItem> items;
  final DateTime createdAt;

  const SavedRoutine({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
  });

  int get totalCalories => items.fold(0, (s, i) => s + i.calories);
  double get totalProtein => items.fold(0.0, (s, i) => s + i.proteinG);
  double get totalCarbs => items.fold(0.0, (s, i) => s + i.carbsG);
  double get totalFat => items.fold(0.0, (s, i) => s + i.fatG);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((i) => i.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
      };

  factory SavedRoutine.fromJson(Map<String, dynamic> j) => SavedRoutine(
        id: j['id'] as String,
        name: j['name'] as String,
        items: (j['items'] as List)
            .map((i) => RoutineItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// Saved meal routines ("Quick Picks"), persisted through the same
/// local-first + Supabase sync layer as every other user record.
///
/// This replaced pure `SharedPreferences` storage. That earlier version kept
/// routines only on the one device they were saved on — nothing survived
/// signing out and back in, a reinstall, or a second device, because there
/// was never a server copy to restore from. [loadAll] and [create] now go
/// through [LocalDBService], which enqueues an outbox entry the same way a
/// logged meal does.
class RoutineService {
  const RoutineService._();

  /// The abandoned SharedPreferences key. Kept only so [_migrateLegacy] has
  /// something to read once; nothing new is ever written here.
  static const _legacyKey = 'nutiai_meal_routines_v1';

  static bool _migrated = false;

  /// Every routine saved for [uid], newest first.
  ///
  /// Runs the one-time legacy migration first so a routine saved under the
  /// old SharedPreferences store is not orphaned by this rewrite — it is
  /// carried into the new store (and from there, uploaded) instead of simply
  /// vanishing the first time this build runs.
  static Future<List<SavedRoutine>> loadAll(String uid) async {
    await _migrateLegacy(uid);
    return LocalDBService.getRoutines(uid).map(_toDomain).toList();
  }

  /// Saves a new routine and returns it, with a proper v4 id.
  ///
  /// The id has to be a real UUID and not, say, a timestamp string — it is the
  /// primary key of a `uuid` column on the server, and the previous version's
  /// `DateTime.now().millisecondsSinceEpoch.toString()` would have failed the
  /// very first insert once routines started reaching Supabase at all.
  static Future<SavedRoutine> create({
    required String uid,
    required String name,
    required List<RoutineItem> items,
  }) async {
    final routine = SavedRoutine(
      id: LocalDBService.newId(),
      name: name,
      items: items,
      createdAt: DateTime.now(),
    );
    await LocalDBService.saveRoutine(LocalMealRoutine(
      id: routine.id,
      userId: uid,
      name: routine.name,
      itemsJson: jsonEncode(routine.items.map((i) => i.toJson()).toList()),
      createdAt: routine.createdAt,
    ));
    return routine;
  }

  static Future<void> delete(String id) => LocalDBService.deleteRoutine(id);

  static SavedRoutine _toDomain(LocalMealRoutine r) {
    List<RoutineItem> items;
    try {
      items = (jsonDecode(r.itemsJson) as List)
          .map((j) => RoutineItem.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // A row that fails to decode is worse than a routine with no items —
      // the latter still shows up and can be deleted from the UI.
      items = const [];
    }
    return SavedRoutine(
        id: r.id, name: r.name, items: items, createdAt: r.createdAt);
  }

  /// Copies anything still sitting under [_legacyKey] into the new store, then
  /// removes the key so this never runs twice. Guarded by an in-memory flag
  /// rather than re-reading the (by-then-absent) key on every call, which
  /// would otherwise mean a SharedPreferences round trip on every [loadAll].
  static Future<void> _migrateLegacy(String uid) async {
    if (_migrated) return;
    _migrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyKey);
      if (raw == null) return;

      final list = jsonDecode(raw) as List;
      for (final j in list) {
        final legacy = SavedRoutine.fromJson(j as Map<String, dynamic>);
        // The legacy id came from `millisecondsSinceEpoch.toString()`, not a
        // UUID, so it cannot become the primary key of a `uuid` column — a
        // fresh id is generated exactly as `create` would for a new routine,
        // and only the name/items/createdAt make the trip.
        await LocalDBService.saveRoutine(LocalMealRoutine(
          id: LocalDBService.newId(),
          userId: uid,
          name: legacy.name,
          itemsJson: jsonEncode(legacy.items.map((i) => i.toJson()).toList()),
          createdAt: legacy.createdAt,
        ));
      }
      await prefs.remove(_legacyKey);
    } catch (_) {
      // A corrupt legacy blob must not block routines from loading at all.
    }
  }
}
