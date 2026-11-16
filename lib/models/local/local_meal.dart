import 'package:hive/hive.dart';

import '../meal.dart';
import 'local_daily_log.dart' show LocalDailyLog;

part 'local_meal.g.dart';

/// One row of `meals`, cached on device.
///
/// [id] is generated client-side (uuid v4) the moment the meal is logged, so
/// the same identifier is used locally and on the server. That makes the push
/// an idempotent upsert — a retry after a flaky response can't create a
/// duplicate meal, which is the classic offline-queue failure.
@HiveType(typeId: 1)
class LocalMeal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String userId;

  @HiveField(2)
  DateTime date;

  @HiveField(3)
  String mealType;

  @HiveField(4)
  String foodName;

  @HiveField(5)
  double? quantity;

  @HiveField(6)
  String? unit;

  @HiveField(7)
  int calories;

  @HiveField(8)
  double proteinG;

  @HiveField(9)
  double carbsG;

  @HiveField(10)
  double fatG;

  @HiveField(11)
  double fiberG;

  @HiveField(12)
  String logMethod;

  @HiveField(13)
  bool isSynced;

  @HiveField(14)
  DateTime loggedAt;

  @HiveField(15)
  String? scanConfidence;

  LocalMeal({
    required this.id,
    required this.userId,
    required this.date,
    required this.mealType,
    required this.foodName,
    this.quantity,
    this.unit,
    this.calories = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.fiberG = 0,
    this.logMethod = 'manual',
    this.isSynced = false,
    required this.loggedAt,
    this.scanConfidence,
  });

  factory LocalMeal.fromRow(Map<String, dynamic> j) => LocalMeal(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        date: DateTime.parse(j['date'] as String),
        mealType: j['meal_type'] as String,
        foodName: j['food_name'] as String,
        quantity: (j['quantity'] as num?)?.toDouble(),
        unit: j['unit'] as String?,
        calories: (j['calories'] as num?)?.toInt() ?? 0,
        proteinG: (j['protein_g'] as num?)?.toDouble() ?? 0,
        carbsG: (j['carbs_g'] as num?)?.toDouble() ?? 0,
        fatG: (j['fat_g'] as num?)?.toDouble() ?? 0,
        fiberG: (j['fiber_g'] as num?)?.toDouble() ?? 0,
        logMethod: j['log_method'] as String? ?? 'manual',
        isSynced: true,
        loggedAt: j['logged_at'] != null
            ? DateTime.parse(j['logged_at'] as String)
            : DateTime.now(),
        scanConfidence: j['scan_confidence'] as String?,
      );

  factory LocalMeal.fromDomain(Meal m, {required String id}) => LocalMeal(
        id: m.id ?? id,
        userId: m.userId,
        date: m.date,
        mealType: m.mealType,
        foodName: m.foodName,
        quantity: m.quantity,
        unit: m.unit,
        calories: m.calories,
        proteinG: m.proteinG,
        carbsG: m.carbsG,
        fatG: m.fatG,
        fiberG: m.fiberG,
        logMethod: m.logMethod,
        isSynced: false,
        loggedAt: m.loggedAt ?? DateTime.now(),
        scanConfidence: m.scanConfidence,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'user_id': userId,
        'date': LocalDailyLog.isoDate(date),
        'meal_type': mealType,
        'food_name': foodName,
        'quantity': quantity,
        'unit': unit,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'fiber_g': fiberG,
        'log_method': logMethod,
        'scan_confidence': scanConfidence,
        'logged_at': loggedAt.toUtc().toIso8601String(),
      };

  Meal toDomain() => Meal(
        id: id,
        userId: userId,
        date: date,
        mealType: mealType,
        foodName: foodName,
        quantity: quantity,
        unit: unit,
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        fiberG: fiberG,
        logMethod: logMethod,
        scanConfidence: scanConfidence,
        loggedAt: loggedAt,
      );
}
