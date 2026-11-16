import 'package:hive/hive.dart';

import 'local_daily_log.dart' show LocalDailyLog;

part 'local_weight_log.g.dart';

/// One row of `weight_logs`, cached on device.
@HiveType(typeId: 3)
class LocalWeightLog extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String userId;

  @HiveField(2)
  double weightKg;

  @HiveField(3)
  DateTime date;

  @HiveField(4)
  bool isSynced;

  LocalWeightLog({
    required this.id,
    required this.userId,
    required this.weightKg,
    required this.date,
    this.isSynced = false,
  });

  factory LocalWeightLog.fromRow(Map<String, dynamic> j) => LocalWeightLog(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        weightKg: (j['weight_kg'] as num?)?.toDouble() ?? 0,
        date: DateTime.parse(j['date'] as String),
        isSynced: true,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'user_id': userId,
        'weight_kg': weightKg,
        'date': LocalDailyLog.isoDate(date),
      };
}
