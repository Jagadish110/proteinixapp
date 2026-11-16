import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local/local_sleep_schedule.dart';
import 'local_db_service.dart';

/// Where sleep tracking is in its daily cycle.
enum SleepTrackingPhase {
  /// The user hasn't switched it on; no alarms are scheduled.
  off,

  /// Switched on and scheduled, but the sleep window hasn't opened yet.
  armed,

  /// Inside the window — screen state is being sampled.
  active;

  String get label => switch (this) {
        SleepTrackingPhase.off => 'OFF',
        SleepTrackingPhase.armed => 'ARMED',
        SleepTrackingPhase.active => 'TRACKING',
      };
}

/// What the dashboard needs to draw the Sleep Cycle card.
class SleepTrackingStatus {
  const SleepTrackingStatus({
    required this.armed,
    required this.running,
    required this.bedtime,
    required this.wake,
  });

  /// The user has switched tracking on. Stays true through the day, while
  /// nothing is actually sampling — this is what the button reflects.
  final bool armed;

  /// The sleep window is open right now.
  final bool running;

  /// "HH:mm". Never null — the card always has times to show and edit.
  final String bedtime;
  final String wake;

  SleepTrackingPhase get phase => !armed
      ? SleepTrackingPhase.off
      : running
          ? SleepTrackingPhase.active
          : SleepTrackingPhase.armed;

  static const defaults = SleepTrackingStatus(
    armed: false,
    running: false,
    bedtime: '22:30',
    wake: '06:30',
  );
}

/// How far a tracked night got.
enum SleepNightStatus {
  /// The window is open and samples are arriving. Figures only grow from here.
  inProgress,

  /// The wake alarm closed the night; the figures are final.
  complete,

  /// Samples stopped before the wake time — a dropped alarm, most likely.
  /// Whatever was seen is a floor of unknown depth, not a measurement.
  partial;

  static SleepNightStatus parse(String? raw) => switch (raw) {
        'complete' => SleepNightStatus.complete,
        'partial' => SleepNightStatus.partial,
        _ => SleepNightStatus.inProgress,
      };
}

/// One night as observed by the native sampler.
class SleepNight {
  const SleepNight({
    required this.date,
    required this.hours,
    required this.interruptions,
    required this.status,
    this.phonePickups = 0,
    this.sleepStart,
    this.sleepEnd,
    this.lastSample,
    this.samples = 0,
    this.observed = Duration.zero,
    this.minimum = Duration.zero,
  });

  /// Builds from the native payload, which `getSleepResult` and each entry of
  /// `getSleepHistory` share.
  factory SleepNight.fromNative(Map<String, dynamic> raw) {
    DateTime? at(String key) => switch ((raw[key] as num?)?.toInt() ?? 0) {
          0 => null,
          final ms => DateTime.fromMillisecondsSinceEpoch(ms),
        };

    final iso = raw['date'] as String?;
    return SleepNight(
      date: iso == null ? null : DateTime.tryParse(iso),
      hours: (raw['hours'] as num?)?.toDouble() ?? 0,
      interruptions: (raw['interruptions'] as num?)?.toInt() ?? 0,
      phonePickups: (raw['phonePickups'] as num?)?.toInt() ?? 0,
      sleepStart: at('sleepStart'),
      sleepEnd: at('sleepEnd'),
      status: SleepNightStatus.parse(raw['status'] as String?),
      lastSample: at('lastSample'),
      samples: (raw['samples'] as num?)?.toInt() ?? 0,
      observed: Duration(milliseconds: (raw['observedMs'] as num?)?.toInt() ?? 0),
      minimum: Duration(milliseconds: (raw['minimumMs'] as num?)?.toInt() ?? 0),
    );
  }

  /// The day the night is credited to — the day the user woke, not the evening
  /// they went to bed. Null when nothing has been recorded yet.
  final DateTime? date;

  /// Dark time inside the window, summed across the stretches long enough to
  /// be sleep and excluding the minutes spent awake between them. 0 when too
  /// little was observed to call it a night.
  final double hours;

  /// Wake-ups the user returned to sleep from, grouped into episodes.
  final int interruptions;

  /// Times the screen was found on inside the window.
  ///
  /// Distinct from [interruptions], and neither contains the other: an
  /// interruption is a wake the user went back to sleep from, while a pickup is
  /// simply the phone in use — including the one that ends the night, which is
  /// never an interruption.
  ///
  /// A floor, not a count. Sampling every 15 minutes cannot see a phone picked
  /// up and put down between two checks, which is what the in-app disclaimer
  /// says out loud.
  final int phonePickups;

  /// When sleep was observed to start and end, as opposed to the window the
  /// user set. Null until there is enough of a night to say.
  ///
  /// These are what makes "went to bed at 23:30, fell asleep at 00:40" visible
  /// rather than hidden inside a single hours figure.
  final DateTime? sleepStart;
  final DateTime? sleepEnd;

  final SleepNightStatus status;

  /// When the screen state was last sampled. Null before the first ever
  /// sample. Diagnostics reads this: samples that stop hours before the wake
  /// time mean the alarm chain broke, not that no sleep happened.
  final DateTime? lastSample;

  /// How many screen checks landed this night. Zero on a night that reported
  /// nothing means the alarms never fired; a healthy count means they did and
  /// there genuinely was no sleep to see. Nothing else separates those.
  final int samples;

  /// Dark time seen before the "is this really a night?" floor is applied, and
  /// the floor itself.
  ///
  /// [hours] is zeroed below [minimum], which makes a night that was watched
  /// and found too short indistinguishable from one that was never watched at
  /// all. It isn't the same thing, and saying so is the difference between
  /// "nothing recorded yet" and "37m so far — a night has to reach 20m".
  final Duration observed;
  final Duration minimum;

  /// Something was measured, and then discarded for being too short to call a
  /// night. [isEmpty] is still true — this only explains why.
  bool get belowMinimum =>
      date != null && hours <= 0 && observed > Duration.zero;

  /// [observed] as "37m" / "1h 05m", or null when nothing was seen.
  String? get observedLabel => _hm(observed);

  /// [minimum] in the same shape, for naming the bar that was missed.
  String? get minimumLabel => _hm(minimum);

  static String? _hm(Duration d) {
    final mins = d.inMinutes;
    if (mins <= 0) return null;
    return mins < 60
        ? '${mins}m'
        : '${mins ~/ 60}h ${(mins % 60).toString().padLeft(2, '0')}m';
  }

  /// Nothing worth writing to the log yet.
  bool get isEmpty => date == null || hours <= 0;

  /// Time awake between stretches of sleep, or null when the span is unknown.
  ///
  /// Derived rather than counted: the observed span minus the time actually
  /// asleep is what is left over. Mirrors `SleepResult.timeAwake` so the
  /// dashboard card and the sleep screen can never disagree about the figure.
  Duration? get awakeInBed {
    final from = sleepStart;
    final to = sleepEnd;
    if (from == null || to == null) return null;
    final awake = to.difference(from) - Duration(minutes: (hours * 60).round());
    return awake.isNegative ? Duration.zero : awake;
  }

  /// What gets written to `sleep_interruptions`.
  ///
  /// [interruptions] alone. [phonePickups] is deliberately not folded in: it
  /// includes the pickup that ends the night, so a clean night would report as
  /// one wake-up.
  int get wakeUps => interruptions;

  /// Safe to persist.
  ///
  /// A [SleepNightStatus.partial] night counts. Its figure is truncated by an
  /// unknowable amount, which is why the card labels it — but withholding it
  /// entirely meant that on any phone whose battery manager drops an alarm
  /// mid-night, which is most of them, `daily_logs` never received a single
  /// row and the sleep ring stayed empty forever. `MealService.setSleep` only
  /// ever raises the stored value, so a truncated night is a floor that a
  /// better reading corrects upward rather than a wrong number that sticks.
  bool get usable => !isEmpty;

  /// "7h 35m", or null when there is nothing to report.
  String? get summary {
    if (isEmpty) return null;
    final total = (hours * 60).round();
    return '${total ~/ 60}h ${(total % 60).toString().padLeft(2, '0')}m';
  }

  static const none = SleepNight(
    date: null,
    hours: 0,
    interruptions: 0,
    status: SleepNightStatus.inProgress,
  );
}

/// Drives sleep tracking: the schedule, the on/off switch, and last night.
///
/// Nothing runs in the background. The native side samples the screen state
/// from short alarm-driven broadcasts across the window, so there is no
/// foreground service and therefore no permanent notification — and no
/// permissions at all. See `SleepTracker.kt` for why sampling beats the
/// screen-state broadcasts it replaced.
class SleepTrackingService {
  const SleepTrackingService._();

  static const _ch = MethodChannel('com.proteinix/sleep_tracking');

  static const prefsBedtime = 'sleep_guard_bedtime';
  static const prefsWake = 'sleep_guard_wake';

  static const defaultBedtime = '22:30';
  static const defaultWake = '06:30';

  /// Never throws — the platform channel is absent on non-Android hosts, and
  /// the dashboard must still render.
  static Future<SleepTrackingStatus> status() async {
    final prefs = await SharedPreferences.getInstance();

    var armed = false;
    var running = false;
    try {
      final res = await _ch.invokeMethod<Map>('getTrackingState');
      final state =
          (res ?? {}).map((k, v) => MapEntry(k.toString(), v == true));
      armed = state['armed'] ?? false;
      running = state['running'] ?? false;
    } catch (_) {
      // Channel unavailable; fall back to "off".
    }

    return SleepTrackingStatus(
      armed: armed,
      running: running,
      bedtime: prefs.getString(prefsBedtime) ?? defaultBedtime,
      wake: prefs.getString(prefsWake) ?? defaultWake,
    );
  }

  /// Saves the window and arms the alarms. Starts immediately if the window is
  /// already open.
  static Future<void> start({
    required String bedtime,
    required String wake,
    String? userId,
  }) async {
    await _persist(bedtime: bedtime, wake: wake, userId: userId, active: true);

    await _ch.invokeMethod('startTracking', {
      'sleepTime': bedtime,
      'wakeTime': wake,
    });
  }

  static Future<void> stop({String? userId}) async {
    if (userId != null) {
      final prefs = await SharedPreferences.getInstance();
      await _persist(
        bedtime: prefs.getString(prefsBedtime) ?? defaultBedtime,
        wake: prefs.getString(prefsWake) ?? defaultWake,
        userId: userId,
        active: false,
      );
    }
    await _ch.invokeMethod('stopTracking');
  }

  /// Persists a changed window without altering whether tracking is on. Callers
  /// re-arm separately, since rescheduling alarms while off would start it.
  static Future<void> saveSchedule({
    required String bedtime,
    required String wake,
    String? userId,
    bool active = false,
  }) =>
      _persist(bedtime: bedtime, wake: wake, userId: userId, active: active);

  /// Writes the window to device prefs *and* queues it for `sleep_schedule`.
  ///
  /// The prefs copy is what the card and the native sampler read; the queued
  /// row is what survives a reinstall or a second device. Only the first of
  /// those existed before, so the schedule the user set never reached the
  /// server at all — `LocalDBService.saveSleepSchedule` was written for this
  /// and then never called from anywhere.
  static Future<void> _persist({
    required String bedtime,
    required String wake,
    required String? userId,
    required bool active,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsBedtime, bedtime);
    await prefs.setString(prefsWake, wake);

    if (userId == null) return;
    try {
      final existing = LocalDBService.getSleepSchedule(userId);
      await LocalDBService.saveSleepSchedule(
        LocalSleepSchedule(
          id: existing?.id ?? '',
          userId: userId,
          sleepTime: bedtime,
          wakeTime: wake,
          isActive: active,
        ),
      );
    } catch (_) {
      // Hive not open (tests, or a sign-out mid-write). The prefs above still
      // hold the window, so tracking itself is unaffected.
    }
  }

  /// Reads the night the native sampler observed. Never throws — returns
  /// [SleepNight.none] on any host without the channel.
  static Future<SleepNight> lastNight() async {
    try {
      final res = await _ch.invokeMethod<Map>('getSleepResult');
      return SleepNight.fromNative(Map<String, dynamic>.from(res ?? const {}));
    } catch (_) {
      return SleepNight.none;
    }
  }

  /// Finished nights the sampler banked, oldest first.
  ///
  /// The in-progress night is wiped when the next one opens, so a user who
  /// woke up and didn't open the app before the following bedtime lost that
  /// night entirely. These are kept for a week so the dashboard can write them
  /// whenever it is next opened. Never throws.
  static Future<List<SleepNight>> history() async {
    try {
      final res = await _ch.invokeMethod<List>('getSleepHistory');
      return (res ?? const [])
          .map(
              (e) => SleepNight.fromNative(Map<String, dynamic>.from(e as Map)))
          .where((n) => !n.isEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Where a tapped morning report wants the app to go, or null.
  ///
  /// The report is posted natively — there is no Flutter engine alive at the
  /// wake time to use the normal notification payload route — so it hands the
  /// destination over as an Intent extra instead. Draining it clears it, so
  /// calling this on every resume is safe.
  static Future<String?> consumeLaunchRoute() async {
    try {
      return await _ch.invokeMethod<String>('consumeLaunchRoute');
    } catch (_) {
      return null;
    }
  }

  /// Tells the sampler the app was brought to the foreground.
  ///
  /// A no-op outside an open window. Inside one it counts a wake-up the
  /// 15-minute samples cannot see, and closes the dark run at the moment the
  /// screen actually came on rather than at the next scheduled check.
  static Future<void> noteAppOpen() async {
    try {
      await _ch.invokeMethod('noteAppOpen');
    } catch (_) {
      // No native host; nothing to record.
    }
  }

  /// "22:30" → "10:30 PM". Returns [fallback] for anything unparseable.
  static String formatTime(String? hhmm, String fallback) {
    if (hhmm == null) return fallback;
    final parts = hhmm.split(':');
    if (parts.length != 2) return fallback;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return fallback;
    }
    final suffix = h < 12 ? 'AM' : 'PM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '${hour12.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')} $suffix';
  }

  /// Length of the window, wrapping past midnight.
  static Duration window(String bedtime, String wake) {
    int mins(String hhmm, int fallback) {
      final parts = hhmm.split(':');
      final h = int.tryParse(parts.first) ?? fallback;
      final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return h.clamp(0, 23) * 60 + m.clamp(0, 59);
    }

    final start = mins(bedtime, 22);
    final end = mins(wake, 6);
    return Duration(
        minutes: end >= start ? end - start : (24 * 60 - start) + end);
  }
}
