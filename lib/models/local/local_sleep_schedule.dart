import 'package:hive/hive.dart';

part 'local_sleep_schedule.g.dart';

/// The user's `sleep_schedule` row, cached on device.
///
/// Note this is a *mirror*, not the source of truth at runtime: the Sleep Guard
/// foreground service reads its schedule from native SharedPreferences so it
/// keeps working with no Flutter engine alive. This copy exists so the schedule
/// can be shown and synced like everything else.
@HiveType(typeId: 5)
class LocalSleepSchedule extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String userId;

  @HiveField(2)
  String sleepTime; // "23:00"

  @HiveField(3)
  String wakeTime; // "07:00"

  @HiveField(4)
  bool isActive;

  @HiveField(5)
  bool isSynced;

  LocalSleepSchedule({
    required this.id,
    required this.userId,
    this.sleepTime = '23:00',
    this.wakeTime = '07:00',
    this.isActive = false,
    this.isSynced = false,
  });

  factory LocalSleepSchedule.fromRow(Map<String, dynamic> j) =>
      LocalSleepSchedule(
        id: j['id'] as String? ?? '',
        userId: j['user_id'] as String,
        sleepTime: j['sleep_time'] as String? ?? '23:00',
        wakeTime: j['wake_time'] as String? ?? '07:00',
        isActive: j['is_active'] as bool? ?? false,
        isSynced: true,
      );

  Map<String, dynamic> toRow() => {
        'user_id': userId,
        'sleep_time': sleepTime,
        'wake_time': wakeTime,
        'is_active': isActive,
      };
}
