import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/date_utils.dart';
import 'supabase_service.dart';

/// A count that belongs to one calendar day and reads as zero on any other.
///
/// Stored as a single `"yyyy-MM-dd:count"` string rather than a date key and a
/// count key, so the two can never be written half-way and disagree.
class DailyCounter {
  const DailyCounter({required this.day, required this.count});

  final String day;
  final int count;

  /// The count for [today], or zero when [raw] is missing, malformed, or was
  /// written on a different day.
  static int countFor(String? raw, String today) {
    if (raw == null) return 0;
    final sep = raw.lastIndexOf(':');
    if (sep <= 0) return 0;
    if (raw.substring(0, sep) != today) return 0;
    final n = int.tryParse(raw.substring(sep + 1));
    return (n == null || n < 0) ? 0 : n;
  }

  static String encode(String today, int count) => '$today:$count';
}

/// The two daily allowances the app meters for itself:
///
///  - photo scans on the Free plan ([freeScansPerDay] a day)
///  - AI Coach messages for everyone ([coachMessagesPerDay] a day)
///
/// Counted on the device, per account, by local calendar day. Search, barcode
/// and the dashboard are never counted — they are unlimited on every plan.
///
/// This is the limit the user *sees*. It is not tamper-proof: clearing app
/// data resets it. The server-side quota in the `gemini-proxy` function is
/// the hard ceiling behind it.
class PlanLimits {
  const PlanLimits._();

  static const freeScansPerDay = 3;
  static const coachMessagesPerDay = 30;

  static const _scanKey = 'plan_scans';
  static const _coachKey = 'plan_coach_messages';

  static String _key(String base) =>
      '${base}_${SupabaseService.currentUserId ?? 'guest'}';

  static String _today() => AppDateUtils.iso(DateTime.now());

  static Future<int> _used(String base) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return DailyCounter.countFor(prefs.getString(_key(base)), _today());
    } catch (_) {
      // Unreadable storage must not lock anyone out of a feature.
      return 0;
    }
  }

  static Future<void> _increment(String base) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _today();
      final used = DailyCounter.countFor(prefs.getString(_key(base)), today);
      await prefs.setString(_key(base), DailyCounter.encode(today, used + 1));
    } catch (_) {}
  }

  /// Free photo scans still available today. Never negative.
  static Future<int> freeScansLeft() async {
    final left = freeScansPerDay - await _used(_scanKey);
    return left < 0 ? 0 : left;
  }

  /// Call once per photo scan that actually produced a result. A scan that
  /// failed, or found no food, does not cost the user one of their three.
  static Future<void> recordScan() => _increment(_scanKey);

  /// Coach messages still available today. Never negative.
  static Future<int> coachMessagesLeft() async {
    final left = coachMessagesPerDay - await _used(_coachKey);
    return left < 0 ? 0 : left;
  }

  /// Call once per coach message that got a reply.
  static Future<void> recordCoachMessage() => _increment(_coachKey);
}
