import 'package:hive/hive.dart';

part 'local_blocked_app.g.dart';

/// One row of `blocked_apps`, cached on device.
///
/// Like [LocalSleepSchedule] this mirrors state the native Sleep Guard service
/// owns at runtime; the copy here is what gets synced.
@HiveType(typeId: 6)
class LocalBlockedApp extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String userId;

  @HiveField(2)
  String packageName;

  @HiveField(3)
  String appName;

  @HiveField(4)
  bool isSynced;

  LocalBlockedApp({
    required this.id,
    required this.userId,
    required this.packageName,
    this.appName = '',
    this.isSynced = false,
  });

  static String keyFor(String userId, String packageName) =>
      '$userId|$packageName';

  String get hiveKey => keyFor(userId, packageName);

  factory LocalBlockedApp.fromRow(Map<String, dynamic> j) => LocalBlockedApp(
        id: j['id'] as String? ?? '',
        userId: j['user_id'] as String,
        packageName: j['package_name'] as String,
        appName: j['app_name'] as String? ?? '',
        isSynced: true,
      );

  Map<String, dynamic> toRow() => {
        'user_id': userId,
        'package_name': packageName,
        'app_name': appName,
      };
}
