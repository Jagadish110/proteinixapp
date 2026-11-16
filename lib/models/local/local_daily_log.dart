import 'package:hive/hive.dart';

import '../daily_log.dart';

part 'local_daily_log.g.dart';

/// One row of `daily_logs`, cached on device.
///
/// Keyed in Hive by `"<userId>|<yyyy-MM-dd>"` rather than by the server id,
/// because a log created offline has no server id yet and the day it belongs to
/// is the only stable identity we have. That key also matches the
/// `(user_id, date)` unique constraint the Supabase table uses, so an upsert
/// pushed later lands on the right row.
@HiveType(typeId: 0)
class LocalDailyLog extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String userId;

  @HiveField(2)
  DateTime date;

  @HiveField(3)
  int caloriesConsumed;

  @HiveField(4)
  double proteinG;

  @HiveField(5)
  double carbsG;

  @HiveField(6)
  double fatG;

  @HiveField(7)
  double fiberG;

  @HiveField(8)
  int waterMl;

  @HiveField(9)
  int steps;

  @HiveField(10)
  double sleepHrs;

  @HiveField(11)
  double? weightKg;

  @HiveField(12)
  bool isSynced;

  @HiveField(13)
  DateTime lastUpdated;

  // Fields beyond the original spec — the app already reads both of these from
  // `daily_logs`, and dropping them would make the offline copy lossy.
  @HiveField(14)
  int caloriesBurned;

  @HiveField(15)
  int sleepQuality;

  /// Wake-ups observed by Sleep Guard's screen-state receiver. Absent on rows
  /// written before the feature shipped, which Hive reads back as 0 — the same
  /// value a night with no disturbances produces. `sleepHrs > 0` is what tells
  /// the two apart, so the UI keys off that rather than off this being zero.
  @HiveField(16)
  int sleepInterruptions;

  /// Times the screen was found on during the sleep window. Absent on older
  /// rows, which Hive reads back as 0 — same as a night nobody touched the
  /// phone. `sleepHrs > 0` is what tells those apart.
  @HiveField(17)
  int phonePickups;

  /// 0–100, recomputed on every write rather than stored authoritatively, so a
  /// change to the scoring rules applies to history the next time it syncs.
  @HiveField(18)
  int sleepScore;

  /// Observed sleep span, as opposed to the window the user set. Null on rows
  /// written before these were tracked, which is why the sleep screen falls
  /// back to the scheduled times rather than showing a blank.
  @HiveField(19)
  DateTime? sleepStart;

  @HiveField(20)
  DateTime? sleepEnd;

  LocalDailyLog({
    required this.id,
    required this.userId,
    required this.date,
    this.caloriesConsumed = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.fiberG = 0,
    this.waterMl = 0,
    this.steps = 0,
    this.sleepHrs = 0,
    this.weightKg,
    this.isSynced = false,
    required this.lastUpdated,
    this.caloriesBurned = 0,
    this.sleepQuality = 0,
    this.sleepInterruptions = 0,
    this.phonePickups = 0,
    this.sleepScore = 0,
    this.sleepStart,
    this.sleepEnd,
  });

  /// Hive key. Stable across the offline→online transition.
  static String keyFor(String userId, DateTime date) =>
      '$userId|${isoDate(date)}';

  String get hiveKey => keyFor(userId, date);

  static String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Builds from a Supabase `daily_logs` row.
  factory LocalDailyLog.fromRow(Map<String, dynamic> j) => LocalDailyLog(
        id: j['id'] as String? ?? '',
        userId: j['user_id'] as String,
        date: DateTime.parse(j['date'] as String),
        caloriesConsumed: (j['calories_consumed'] as num?)?.toInt() ?? 0,
        proteinG: (j['protein_g'] as num?)?.toDouble() ?? 0,
        carbsG: (j['carbs_g'] as num?)?.toDouble() ?? 0,
        fatG: (j['fat_g'] as num?)?.toDouble() ?? 0,
        fiberG: (j['fiber_g'] as num?)?.toDouble() ?? 0,
        waterMl: (j['water_ml'] as num?)?.toInt() ?? 0,
        steps: (j['steps'] as num?)?.toInt() ?? 0,
        sleepHrs: (j['sleep_hrs'] as num?)?.toDouble() ?? 0,
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        isSynced: true,
        lastUpdated: DateTime.now(),
        caloriesBurned: (j['calories_burned'] as num?)?.toInt() ?? 0,
        sleepQuality: (j['sleep_quality'] as num?)?.toInt() ?? 0,
        sleepInterruptions: (j['sleep_interruptions'] as num?)?.toInt() ?? 0,
        phonePickups: (j['phone_pickups'] as num?)?.toInt() ?? 0,
        sleepScore: (j['sleep_score'] as num?)?.toInt() ?? 0,
        sleepStart: DateTime.tryParse(j['sleep_start']?.toString() ?? ''),
        sleepEnd: DateTime.tryParse(j['sleep_end']?.toString() ?? ''),
      );

  /// Payload for the Supabase upsert.
  ///
  /// The server id is omitted deliberately: rows created offline don't have
  /// one, and the `(user_id, date)` conflict target is what the upsert keys on.
  Map<String, dynamic> toRow() => {
        'user_id': userId,
        'date': isoDate(date),
        'calories_consumed': caloriesConsumed,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'fiber_g': fiberG,
        'water_ml': waterMl,
        'steps': steps,
        'calories_burned': caloriesBurned,
        'sleep_hrs': sleepHrs,
        'sleep_quality': sleepQuality,
        'sleep_interruptions': sleepInterruptions,
        'phone_pickups': phonePickups,
        'sleep_score': sleepScore,
        'sleep_start': sleepStart?.toUtc().toIso8601String(),
        'sleep_end': sleepEnd?.toUtc().toIso8601String(),
        'weight_kg': weightKg,
      };

  DailyLog toDomain() => DailyLog(
        id: id.isEmpty ? null : id,
        userId: userId,
        date: date,
        caloriesConsumed: caloriesConsumed,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        fiberG: fiberG,
        waterMl: waterMl,
        steps: steps,
        caloriesBurned: caloriesBurned,
        sleepHrs: sleepHrs,
        sleepQuality: sleepQuality,
        sleepInterruptions: sleepInterruptions,
        phonePickups: phonePickups,
        sleepScore: sleepScore,
        sleepStart: sleepStart,
        sleepEnd: sleepEnd,
        weightKg: weightKg,
      );
}
