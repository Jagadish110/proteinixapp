import 'package:intl/intl.dart';

class AppDateUtils {
  static String greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  static String today() => DateFormat('EEE, MMM d').format(DateTime.now());
  static String iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// Strips time component so DateTime keys always compare equal for same calendar day
  static DateTime toDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static List<DateTime> weekFrom(DateTime d) =>
      List.generate(7, (i) => toDateOnly(d.subtract(Duration(days: 6 - i))));
}
