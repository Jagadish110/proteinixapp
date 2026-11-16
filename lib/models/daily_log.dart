class DailyLog {
  final String? id;
  final String userId;
  final DateTime date;
  final int caloriesConsumed;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final int waterMl;
  final int steps;
  final int caloriesBurned;
  final double sleepHrs;
  final int sleepQuality;

  /// Wake-ups the user returned to sleep from, as inferred by the sampler.
  final int sleepInterruptions;

  /// Times the screen was found on during the sleep window. A floor — sampling
  /// every 15 minutes cannot see a phone picked up and put down in between.
  final int phonePickups;

  /// 0–100, from hours slept and interruptions. See `SleepResult`.
  final int sleepScore;

  /// When sleep was observed to start and end, as opposed to the window the
  /// user set. Null on rows written before these were tracked.
  final DateTime? sleepStart;
  final DateTime? sleepEnd;

  final double? weightKg;

  DailyLog({
    this.id,
    required this.userId,
    required this.date,
    this.caloriesConsumed = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.fiberG = 0,
    this.waterMl = 0,
    this.steps = 0,
    this.caloriesBurned = 0,
    this.sleepHrs = 0,
    this.sleepQuality = 0,
    this.sleepInterruptions = 0,
    this.phonePickups = 0,
    this.sleepScore = 0,
    this.sleepStart,
    this.sleepEnd,
    this.weightKg,
  });

  factory DailyLog.fromJson(Map<String, dynamic> j) => DailyLog(
        id: j['id'] as String?,
        userId: j['user_id'] as String,
        date: DateTime.parse(j['date'] as String),
        caloriesConsumed: (j['calories_consumed'] as num?)?.toInt() ?? 0,
        proteinG: (j['protein_g'] as num?)?.toDouble() ?? 0,
        carbsG: (j['carbs_g'] as num?)?.toDouble() ?? 0,
        fatG: (j['fat_g'] as num?)?.toDouble() ?? 0,
        fiberG: (j['fiber_g'] as num?)?.toDouble() ?? 0,
        waterMl: (j['water_ml'] as num?)?.toInt() ?? 0,
        steps: (j['steps'] as num?)?.toInt() ?? 0,
        caloriesBurned: (j['calories_burned'] as num?)?.toInt() ?? 0,
        sleepHrs: (j['sleep_hrs'] as num?)?.toDouble() ?? 0,
        sleepQuality: (j['sleep_quality'] as num?)?.toInt() ?? 0,
        sleepInterruptions: (j['sleep_interruptions'] as num?)?.toInt() ?? 0,
        phonePickups: (j['phone_pickups'] as num?)?.toInt() ?? 0,
        sleepScore: (j['sleep_score'] as num?)?.toInt() ?? 0,
        sleepStart: DateTime.tryParse(j['sleep_start']?.toString() ?? ''),
        sleepEnd: DateTime.tryParse(j['sleep_end']?.toString() ?? ''),
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
      );
}
