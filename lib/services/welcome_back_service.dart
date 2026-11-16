import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/date_utils.dart';

/// Notices when someone returns after missing days, so the dashboard can say
/// "welcome back" instead of leading with a streak that has gone to zero.
///
/// Missing a few days is the normal way people use an app like this. Opening
/// it again is the behaviour worth rewarding, and a broken-streak message at
/// that exact moment is the most reliable way to make it the last time.
class WelcomeBackService {
  const WelcomeBackService._();

  static const _keyLastOpen = 'last_open_day';
  static const _keyGreetDay = 'welcome_back_day';
  static const _keyGreetGap = 'welcome_back_gap';

  /// Full days missed between [lastOpen] and [today], both date-only.
  ///
  /// Opened Monday, back on Thursday → Tuesday and Wednesday were missed → 2.
  /// Zero for consecutive days, the same day, or a clock that went backwards.
  static int missedDays(DateTime lastOpen, DateTime today) {
    final a = DateTime.utc(lastOpen.year, lastOpen.month, lastOpen.day);
    final b = DateTime.utc(today.year, today.month, today.day);
    final gap = b.difference(a).inDays - 1;
    return gap < 0 ? 0 : gap;
  }

  /// Records that the app was opened today and returns how many days were
  /// missed before it, or 0 when there is nothing to greet.
  ///
  /// The answer is pinned to the day: calling this again later the same day
  /// returns the same number, so the message stays put until it is dismissed
  /// rather than vanishing the second time the dashboard builds.
  static Future<int> checkIn({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = AppDateUtils.toDateOnly(now ?? DateTime.now());
      final todayIso = AppDateUtils.iso(today);

      if (prefs.getString(_keyGreetDay) == todayIso) {
        return prefs.getInt(_keyGreetGap) ?? 0;
      }

      final lastIso = prefs.getString(_keyLastOpen);
      await prefs.setString(_keyLastOpen, todayIso);
      if (lastIso == null || lastIso == todayIso) return 0;

      final last = DateTime.tryParse(lastIso);
      if (last == null) return 0;
      final missed = missedDays(last, today);
      if (missed < 1) return 0;

      await prefs.setString(_keyGreetDay, todayIso);
      await prefs.setInt(_keyGreetGap, missed);
      return missed;
    } catch (_) {
      return 0;
    }
  }

  /// The user has read the message; do not show it again today.
  static Future<void> dismiss() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyGreetGap, 0);
    } catch (_) {}
  }

  static String message(int missedDays) => missedDays >= 7
      ? 'Good to see you again. Nothing to catch up on — log one meal and '
          'today counts.'
      : 'No catching up needed. Log one meal and today counts.';
}
