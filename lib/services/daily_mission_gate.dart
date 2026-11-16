import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/date_utils.dart';

/// Tracks whether the "Start My Day" mission screen has already been shown
/// today, so it appears once per calendar day on the first open rather than
/// every time the app is opened.
class DailyMissionGate {
  const DailyMissionGate._();

  static const _key = 'daily_mission_shown_date';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) != AppDateUtils.iso(DateTime.now());
  }

  static Future<void> markShownToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, AppDateUtils.iso(DateTime.now()));
  }
}
