class SleepSchedule {
  final String? id;
  final String userId;
  final String sleepTime; // HH:MM
  final String wakeTime; // HH:MM
  final List<String> days;
  final bool isActive;

  SleepSchedule({
    this.id,
    required this.userId,
    required this.sleepTime,
    required this.wakeTime,
    this.days = const ['all'],
    this.isActive = true,
  });

  factory SleepSchedule.fromJson(Map<String, dynamic> j) => SleepSchedule(
        id: j['id'] as String?,
        userId: j['user_id'] as String,
        sleepTime: j['sleep_time'] as String,
        wakeTime: j['wake_time'] as String,
        days:
            (j['days'] as List?)?.map((e) => e.toString()).toList() ?? ['all'],
        isActive: j['is_active'] as bool? ?? true,
      );
}

class BlockedApp {
  final String? id;
  final String userId;
  final String packageName;
  final String appName;

  BlockedApp({
    this.id,
    required this.userId,
    required this.packageName,
    required this.appName,
  });

  factory BlockedApp.fromJson(Map<String, dynamic> j) => BlockedApp(
        id: j['id'] as String?,
        userId: j['user_id'] as String,
        packageName: j['package_name'] as String,
        appName: j['app_name'] as String,
      );
}
