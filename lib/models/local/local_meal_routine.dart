import 'dart:convert';

import 'package:hive/hive.dart';

part 'local_meal_routine.g.dart';

/// One row of `meal_routines`, cached on device.
///
/// This is the server-backed replacement for what used to be pure
/// SharedPreferences storage — see `RoutineService`. [itemsJson] is stored
/// as a JSON string rather than a nested Hive object because the shape it
/// carries is already owned by `RoutineItem` in `routine_service.dart`;
/// duplicating that as a second Hive-adapted type would be two sources of
/// truth for the same four-field record.
@HiveType(typeId: 7)
class LocalMealRoutine extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String userId;

  @HiveField(2)
  String name;

  /// JSON-encoded `List<RoutineItem>`, matching the `items` jsonb column.
  @HiveField(3)
  String itemsJson;

  @HiveField(4)
  DateTime createdAt;

  @HiveField(5)
  bool isSynced;

  LocalMealRoutine({
    required this.id,
    required this.userId,
    required this.name,
    required this.itemsJson,
    required this.createdAt,
    this.isSynced = false,
  });

  factory LocalMealRoutine.fromRow(Map<String, dynamic> j) => LocalMealRoutine(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        name: j['name'] as String,
        // Supabase hands back jsonb already decoded into a List/Map, not a
        // string — re-encode so storage is uniform regardless of source.
        itemsJson: jsonEncode(j['items'] ?? const []),
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'] as String)
            : DateTime.now(),
        isSynced: true,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'items': jsonDecode(itemsJson),
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}
