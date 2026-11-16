import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/crash_log.dart';
import 'local_db_service.dart';
import 'supabase_service.dart';

/// Entry point for notification taps that arrive while the app is not running.
///
/// Android spins up a *separate* isolate for these, so nothing from the UI
/// isolate (providers, navigator, the tap stream below) is reachable here —
/// only durable side effects are. We drop a breadcrumb the UI isolate reads on
/// next launch.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  // Deliberately empty: acting on the payload requires the UI isolate, and the
  // foreground handler picks it up from the launch details on cold start.
  // Declaring the handler is still required — without it Android 12+ drops
  // action-button taps entirely.
}

/// Manages scheduled reminders (water, meals, steps, bedtime) and one-off
/// progress alerts.
///
/// Reliability on Android depends on four separate things, all of which are
/// handled here because failing any one of them looks identical to the user
/// ("my reminders never arrive"):
///   1. POST_NOTIFICATIONS granted (Android 13+),
///   2. exact-alarm access granted (Android 12+),
///   3. the alarm being registered against the *device's* timezone,
///   4. the channel existing with a high enough importance to make a sound.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // ── Channels ───────────────────────────────────────────────────────────────
  //
  // Android freezes a channel's importance AND its sound the moment it is first
  // created, and ignores every later change — including one made by a new app
  // version. Early builds let the plugin create these implicitly at schedule
  // time, which on some OEMs produced silent, low-importance channels that no
  // amount of code could repair. A version suffix forces a clean channel; the
  // superseded ids are deleted in [_createChannels] so they don't linger in
  // system settings.
  //
  // _v3 added the custom chime; _v4 exists because that chime was renamed
  // with the app (nutiai_chime -> proteinix_chime), and a channel keeps the
  // sound URI it was created with. Adding or changing [_chime] on an
  // existing channel does nothing at all — a new channel is the only way.
  static const _waterChannelId = 'water_reminders_v4';
  static const _mealChannelId = 'meal_reminders_v4';
  static const _stepChannelId = 'step_reminders_v4';
  static const _sleepChannelId = 'sleep_reminders_v4';
  static const _liveChannelId = 'live_progress_v4';
  static const _setupChannelId = 'setup_v1';

  /// The app's own notification sound, from `res/raw/proteinix_chime.wav`.
  ///
  /// Named without an extension deliberately — Android resolves raw resources
  /// by name, and including ".wav" yields a silent notification rather than an
  /// error, which is close to undebuggable.
  static const _chime = RawResourceAndroidNotificationSound('proteinix_chime');

  static const _legacyChannelIds = [
    'water_reminders',
    'meal_reminders',
    'step_reminders',
    'sleep_reminders',
    'live_progress',
    'water_reminders_v2',
    'water_reminders_v3',
    'meal_reminders_v2',
    'meal_reminders_v3',
    'step_reminders_v2',
    'step_reminders_v3',
    'sleep_reminders_v2',
    'sleep_reminders_v3',
    'live_progress_v2',
    'live_progress_v3',
  ];

  // ── Notification id ranges ─────────────────────────────────────────────────
  //
  // Ranges rather than a blanket cancelAll(), so rescheduling reminders can't
  // wipe the one-off goal alerts (900+) sitting in the shade.
  static const waterBaseId = 100;
  static const waterMaxSlots = 20;
  static const mealBaseId = 200;
  static const mealMaxSlots = 10;
  static const stepBaseId = 300;
  static const stepSlots = 2;
  static const sleepBaseId = 400;

  /// The "finish setting up" nudges. Outside every range [cancelReminders]
  /// sweeps, on purpose: rescheduling the daily reminders must not silently
  /// drop a follow-up, and a follow-up must not survive [clear] on completion.
  static const onboardingBaseId = 500;
  static const onboardingSlots = 2;

  static const testId = 999;

  // ── SharedPrefs keys ───────────────────────────────────────────────────────
  static const _keyWaterEnabled = 'notif_water_enabled';
  static const _keyWaterIntervalH = 'notif_water_interval_h';
  static const _keyWaterStart = 'notif_water_start'; // "08:00"
  static const _keyWaterEnd = 'notif_water_end'; // "22:00"
  static const _keyMealEnabled = 'notif_meal_enabled';
  static const _keyMealTimes = 'notif_meal_times'; // JSON ["08:00", …]
  static const _keyMealLabels = 'notif_meal_labels'; // JSON ["Breakfast", …]
  static const _keyStepEnabled = 'notif_step_enabled';
  static const _keySleepEnabled = 'notif_sleep_enabled';
  static const _keySleepBedtime = 'notif_sleep_bedtime'; // "23:00"

  /// Written by [NotificationBootReceiver] on the Kotlin side (into the same
  /// `FlutterSharedPreferences` file, so no method channel is needed).
  static const keyNeedsReschedule = 'notif_needs_reschedule';

  /// Last date (yyyy-MM-dd) the alarm set was written, so app launches can
  /// cheaply detect a schedule that an OEM task-killer silently dropped.
  static const _keyLastScheduled = 'notif_last_scheduled';

  // ── Tap routing ────────────────────────────────────────────────────────────

  static final _taps = StreamController<String>.broadcast();

  /// Payloads of tapped notifications (`water`, `meal:Lunch`, `step`, `sleep`),
  /// suffixed with `#<actionId>` when an action button was used.
  static Stream<String> get taps => _taps.stream;

  /// Payload of the notification that cold-started the app, if any. Read once
  /// by the router after the first frame.
  static String? launchPayload;

  // ── Init ───────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    await _setLocalTimezone();

    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    // Channels must exist before the first zonedSchedule call, otherwise the
    // plugin creates them from the per-notification details and any later
    // importance change is ignored by the OS forever.
    await _createChannels();

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      launchPayload = launch?.notificationResponse?.payload;
    }

    _initialized = true;
    // NOTE: POST_NOTIFICATIONS is deliberately *not* requested here. Firing it
    // during startup raced the other startup permission requests and threw
    // "a permission request is already in progress", which aborted the request
    // silently and left the app permanently unable to post. It is now asked for
    // explicitly — see NotificationPermissionService.
  }

  /// Binds `tz.local` to the device's real timezone.
  ///
  /// This was previously hard-coded to `Asia/Kolkata`. Every reminder for a
  /// user outside IST was therefore scheduled against Indian wall-clock time —
  /// an 08:00 reminder fired at 02:30 UTC, i.e. never when the user was
  /// looking. Falling back to IST keeps the old behaviour if the platform
  /// lookup fails, which is the safe default for this app's main market.
  static Future<void> _setLocalTimezone() async {
    var name = 'Asia/Kolkata';
    try {
      final device = await FlutterTimezone.getLocalTimezone();
      if (device.isNotEmpty) name = device;
    } catch (e, s) {
      await CrashLog.record('Timezone lookup failed, defaulting to IST: $e', s);
    }
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Unknown/aliased zone id — keep the database default rather than crash.
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }
  }

  static Future<void> _createChannels() async {
    final android = _android;
    if (android == null) return;

    for (final id in _legacyChannelIds) {
      try {
        await android.deleteNotificationChannel(id);
      } catch (_) {}
    }

    // Every channel carries the same chime. One sound across all reminder types
    // is the point: recognition comes from hearing the *app*, and a different
    // tone per category would just be five sounds nobody learns.
    const channels = [
      AndroidNotificationChannel(
        _waterChannelId,
        'Water Reminders',
        description: 'Hydration reminders through the day',
        importance: Importance.high,
        playSound: true,
        sound: _chime,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        _mealChannelId,
        'Meal Reminders',
        description: 'Reminders to log breakfast, lunch, dinner and snacks',
        importance: Importance.high,
        playSound: true,
        sound: _chime,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        _stepChannelId,
        'Step Reminders',
        description: 'Daily step goal check-ins',
        importance: Importance.defaultImportance,
        playSound: true,
        sound: _chime,
      ),
      AndroidNotificationChannel(
        _sleepChannelId,
        'Sleep Reminders',
        description: 'Bedtime wind-down reminders',
        importance: Importance.high,
        playSound: true,
        sound: _chime,
      ),
      AndroidNotificationChannel(
        _liveChannelId,
        'Progress Alerts',
        description: 'Celebrates goals as you hit them through the day',
        importance: Importance.high,
        playSound: true,
        sound: _chime,
      ),
      AndroidNotificationChannel(
        _setupChannelId,
        'Finish Setup',
        description: 'A nudge to complete your profile if you leave part-way',
        importance: Importance.defaultImportance,
        playSound: true,
        sound: _chime,
      ),
    ];

    for (final c in channels) {
      try {
        await android.createNotificationChannel(c);
      } catch (e, s) {
        await CrashLog.record('Channel ${c.id} creation failed: $e', s);
      }
    }
  }

  static void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final action = response.actionId;
    _taps.add(action == null || action.isEmpty ? payload : '$payload#$action');
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// True when the OS lets us set to-the-minute alarms.
  ///
  /// On Android 12+ SCHEDULE_EXACT_ALARM is special access the user grants
  /// manually; without it `zonedSchedule` throws `exact_alarms_not_permitted`.
  static bool _exactAlarmsAllowed = false;

  static Future<void> _refreshExactAlarmCapability() async {
    try {
      _exactAlarmsAllowed =
          await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      _exactAlarmsAllowed = false;
    }
  }

  /// Whether the app may post notifications at all (Android 13+ runtime grant).
  /// Everything else is irrelevant while this is false.
  static Future<bool> areNotificationsEnabled() async {
    try {
      final enabled = await _android?.areNotificationsEnabled();
      if (enabled != null) return enabled;
    } catch (_) {}
    try {
      return await Permission.notification.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Shows the Android 13+ runtime prompt. Returns the resulting grant state.
  static Future<bool> requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (e, s) {
      await CrashLog.record('POST_NOTIFICATIONS request failed: $e', s);
      return areNotificationsEnabled();
    }
  }

  static Future<bool> isNotificationPermissionPermanentlyDenied() async {
    try {
      return await Permission.notification.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  // No requestExactAlarmPermission or battery-optimisation request here on
  // purpose. Both are special access granted only from a system settings
  // screen, and the app is built so that enabling notifications is the entire
  // setup. [_refreshExactAlarmCapability] stays because it is the *detection*
  // that keeps `zonedSchedule` on the mode the OS will actually accept — it
  // simply always reports false now, and every reminder is scheduled inexactly.

  // ── Load / save settings ───────────────────────────────────────────────────

  /// Used only when there is genuinely no profile to read — signed out, or
  /// before Hive is open. Matches the defaults `UserProfile` ships with, so a
  /// reminder never quotes a target the app wouldn't also show on screen.
  static const defaultWaterGoalMl = 2500;
  static const defaultStepsGoal = 10000;

  /// The user's own targets, read from the profile the rest of the app shows.
  ///
  /// Reminder bodies quote these numbers, and quoting one the user never chose
  /// is worse than quoting none at all: "keep up your 2.5L goal" to somebody
  /// who set 4,000ml in Profile reads as the app ignoring them. That is exactly
  /// what shipped — [NotificationSettings.waterGoalMl] had a 2500 default and
  /// nothing ever assigned it, so every hydration reminder quoted the default
  /// no matter what the profile said.
  ///
  /// Deliberately *not* persisted alongside the notification preferences. The
  /// profile is the single source of truth for a target; a copy in
  /// SharedPreferences is one more thing to keep in step, and the way this
  /// broke once already.
  static ({int water, int steps}) _goals() {
    try {
      final uid = SupabaseService.currentUserId;
      final p = uid == null ? null : LocalDBService.getProfile(uid);
      if (p != null) return (water: p.waterGoalMl, steps: p.stepsGoal);
    } catch (_) {
      // Hive not open yet, or no session. Fall through to the defaults.
    }
    return (water: defaultWaterGoalMl, steps: defaultStepsGoal);
  }

  static Future<NotificationSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final goals = _goals();

    List<String> mealTimes = ['08:00', '13:00', '19:00', '16:00'];
    List<String> mealLabels = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

    final timesJson = prefs.getString(_keyMealTimes);
    final labelsJson = prefs.getString(_keyMealLabels);
    if (timesJson != null) {
      try {
        mealTimes = List<String>.from(jsonDecode(timesJson));
      } catch (_) {}
    }
    if (labelsJson != null) {
      try {
        mealLabels = List<String>.from(jsonDecode(labelsJson));
      } catch (_) {}
    }
    // Ensure labels and times always match in length
    while (mealLabels.length < mealTimes.length) {
      mealLabels.add('Meal');
    }

    return NotificationSettings(
      waterEnabled: prefs.getBool(_keyWaterEnabled) ?? true,
      waterIntervalHours: prefs.getInt(_keyWaterIntervalH) ?? 2,
      waterStartTime: prefs.getString(_keyWaterStart) ?? '08:00',
      waterEndTime: prefs.getString(_keyWaterEnd) ?? '22:00',
      waterGoalMl: goals.water,
      stepsGoal: goals.steps,
      mealEnabled: prefs.getBool(_keyMealEnabled) ?? true,
      mealTimes: mealTimes,
      mealLabels: mealLabels,
      stepEnabled: prefs.getBool(_keyStepEnabled) ?? false,
      sleepEnabled: prefs.getBool(_keySleepEnabled) ?? false,
      sleepBedtime: prefs.getString(_keySleepBedtime) ?? '23:00',
    );
  }

  /// Persists the settings only. Fast — a handful of SharedPreferences writes.
  static Future<void> savePreferences(NotificationSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWaterEnabled, s.waterEnabled);
    await prefs.setInt(_keyWaterIntervalH, s.waterIntervalHours);
    await prefs.setString(_keyWaterStart, s.waterStartTime);
    await prefs.setString(_keyWaterEnd, s.waterEndTime);
    await prefs.setBool(_keyMealEnabled, s.mealEnabled);
    await prefs.setString(_keyMealTimes, jsonEncode(s.mealTimes));
    await prefs.setString(_keyMealLabels, jsonEncode(s.mealLabels));
    await prefs.setBool(_keyStepEnabled, s.stepEnabled);
    await prefs.setBool(_keySleepEnabled, s.sleepEnabled);
    await prefs.setString(_keySleepBedtime, s.sleepBedtime);
  }

  static Future<void> saveAndSchedule(NotificationSettings s) async {
    await savePreferences(s);
    await reschedule(s);
  }

  /// Reminders belong to an account, not to an install.
  ///
  /// Someone exploring the app without signing up was still getting the full
  /// reminder set — water every two hours, meal prompts, a bedtime nudge — for
  /// an account that does not exist, about data that is not being saved
  /// anywhere. Tapping one dropped them into an app that could not show them
  /// what it had just reminded them about.
  ///
  /// Enforced here rather than only at the settings screen because scheduling
  /// has several entry points that never pass through it: [restoreIfNeeded] at
  /// every launch, [refreshWaterReminders] after a water log, the boot
  /// receiver's re-arm. Gating the one choke point they all share is the only
  /// version of this that actually holds.
  static bool get _hasAccount => SupabaseService.isLoggedIn;

  // ── Scheduling ─────────────────────────────────────────────────────────────

  /// Rewrites the alarm schedule. Slow — one platform round trip per alarm, so
  /// callers should let this run in the background rather than block the UI.
  ///
  /// Never throws for a single bad alarm — each one is scheduled independently
  /// inside [_schedule], so one failure can't take the rest of the batch down.
  /// This only throws if the notification channel itself is unusable (e.g. the
  /// plugin failed to initialise), which is the one case worth surfacing.
  static Future<void> reschedule(NotificationSettings s) async {
    await init();
    await _refreshExactAlarmCapability();

    await cancelReminders();

    // Signed out: the cancel above stands, and nothing is re-armed. Also
    // clears the "already scheduled today" marker, so signing in later goes
    // through [restoreIfNeeded] and arms the reminders for real.
    if (!_hasAccount) {
      final p = await SharedPreferences.getInstance();
      await p.remove(_keyLastScheduled);
      return;
    }

    if (s.waterEnabled) await _scheduleWaterReminders(s);
    if (s.mealEnabled) await _scheduleMealReminders(s);
    if (s.stepEnabled) await scheduleStepReminders(s);
    if (s.sleepEnabled) await scheduleSleepReminder(s.sleepBedtime);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastScheduled, _todayKey());
    await prefs.setBool(keyNeedsReschedule, false);
  }

  /// Rewrites just the water reminders, so their wording matches what the user
  /// has actually drunk.
  ///
  /// The body text is baked in when the alarm is registered — the plugin fires
  /// it natively with no Dart running — so "1.2L left" is only true if it is
  /// re-registered after every change to today's total. Called from
  /// `MealService.addWater`.
  ///
  /// Silent and unawaited-safe by design: a reminder whose wording is one glass
  /// out of date is not worth interrupting a water log for.
  static Future<void> refreshWaterReminders() async {
    try {
      if (!_hasAccount) return;
      final s = await load();
      if (!s.waterEnabled) return;
      await init();
      await _refreshExactAlarmCapability();
      for (var id = waterBaseId; id < waterBaseId + waterMaxSlots; id++) {
        await _plugin.cancel(id);
      }
      await _scheduleWaterReminders(s);
    } catch (e, st) {
      await CrashLog.record('Water reminder refresh failed: $e', st);
    }
  }

  /// Re-registers every reminder whose wording quotes one of the user's
  /// targets, so editing a goal in Profile takes effect on the next reminder
  /// rather than the next day.
  ///
  /// Needed because these bodies are fixed strings handed to the OS at
  /// registration time — the alarm fires with no Dart running, so nothing can
  /// re-read the profile at delivery. Without this, changing the water goal to
  /// 4,000ml left every already-scheduled reminder still saying 2.5L until the
  /// daily reschedule happened to rewrite them.
  ///
  /// Called from `ProfileNotifier.update`, which is the one choke point every
  /// goal edit passes through. Silent and safe to leave unawaited: a reminder
  /// quoting last week's target is not worth failing a profile save over.
  static Future<void> refreshGoalReminders() async {
    try {
      if (!_hasAccount) return;
      final s = await load();
      await init();
      await _refreshExactAlarmCapability();
      if (s.waterEnabled) {
        await cancelWater();
        await _scheduleWaterReminders(s);
      }
      if (s.stepEnabled) {
        await cancelSteps();
        await scheduleStepReminders(s);
      }
    } catch (e, st) {
      await CrashLog.record('Goal reminder refresh failed: $e', st);
    }
  }

  /// Re-registers alarms when the OS is likely to have dropped them.
  ///
  /// Two things wipe pending alarms without telling the app: a reboot (the
  /// Kotlin [NotificationBootReceiver] flags it) and OEM "app cleaners", which
  /// leave no trace at all — so a stale last-scheduled date is also treated as
  /// a wipe. Cheap enough to run unawaited at every launch.
  static Future<void> restoreIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rebooted = prefs.getBool(keyNeedsReschedule) ?? false;
      final stale = prefs.getString(_keyLastScheduled) != _todayKey();
      if (!rebooted && !stale) return;

      // A guest has nothing to restore, and restoring would be how a
      // signed-out install quietly re-armed itself at every launch.
      if (!_hasAccount) return;

      final settings = await load();
      if (!settings.anyEnabled) return;
      if (!await areNotificationsEnabled()) return;

      await reschedule(settings);
    } catch (e, s) {
      await CrashLog.record('Reminder restore failed: $e', s);
    }
  }

  /// Schedules one reminder, degrading to an inexact alarm rather than failing
  /// outright when exact alarms aren't permitted.
  ///
  /// Swallows its own failure after trying both modes — a single misbehaving
  /// alarm (OEM quirk, transient OS error) shouldn't cost the rest of the day's
  /// reminders. The failure is written to the crash log instead so it's still
  /// possible to diagnose which one didn't take.
  static Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required NotificationDetails details,
    required String payload,
  }) async {
    Future<void> attempt(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.time,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );

    // Every reminder now prefers an exact alarm. Water used to opt out on the
    // grounds that hydration nudges are approximate, but "inexact" on Doze-
    // happy OEMs means "whenever the device next wakes up", which in practice
    // was hours late or never — indistinguishable from broken.
    final mode = _exactAlarmsAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    try {
      await attempt(mode);
    } on PlatformException catch (e, st) {
      if (mode != AndroidScheduleMode.inexactAllowWhileIdle) {
        // Permission was likely revoked between the check and the call.
        _exactAlarmsAllowed = false;
        try {
          await attempt(AndroidScheduleMode.inexactAllowWhileIdle);
          return;
        } on PlatformException catch (e2, st2) {
          await CrashLog.record(
              'Notification $id (inexact retry) failed: $e2', st2);
          return;
        }
      }
      await CrashLog.record('Notification $id failed: $e', st);
    }
  }

  // ── Water reminders ────────────────────────────────────────────────────────

  /// How much water is still owed today, in ml, or null when it can't be read.
  ///
  /// Null and zero mean different things here: null is "no idea", which keeps
  /// the generic wording, while 0 is "goal met" and earns a different message.
  static int? _waterShortfall(int goalMl) {
    try {
      final uid = SupabaseService.currentUserId;
      if (uid == null) return null;
      final log = LocalDBService.getTodayLog(uid);
      final drunk = log?.waterMl ?? 0;
      return (goalMl - drunk).clamp(0, goalMl);
    } catch (_) {
      // Hive not open yet, or no session. Not worth failing a reminder over.
      return null;
    }
  }

  /// "1.2L" above a litre, "350ml" below it — nobody reads "1200ml" as a volume.
  static String _volume(int ml) =>
      ml >= 1000 ? '${(ml / 1000).toStringAsFixed(1)}L' : '${ml}ml';

  /// Thousands separators, so a step target reads "10,000" and not "10000".
  static String _count(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  /// Drops a meaningless ".0" — a 150g protein target should not read "150.0g".
  static String _grams(double g) =>
      '${g == g.roundToDouble() ? g.round() : g.toStringAsFixed(1)}g';

  /// The wording of a hydration reminder, given the user's target.
  ///
  /// Pure and separated from the scheduling on purpose: the number in this
  /// string is the part that was wrong in production — every reminder quoted
  /// 2.5L regardless of the profile — and a plugin call is not something a test
  /// can reach. [shortfallMl] is null when today's total can't be read, which
  /// keeps the wording generic rather than guessing.
  @visibleForTesting
  static String waterReminderBody({
    required int goalMl,
    required int? shortfallMl,
  }) =>
      switch (shortfallMl) {
        null => 'Time to drink water — keep up your ${_volume(goalMl)} goal.',
        0 => "You've hit your ${_volume(goalMl)} goal today. Keep sipping.",
        final left =>
          '${_volume(left)} left to reach your ${_volume(goalMl)} goal today.',
      };

  static Future<List<String>> _scheduleWaterReminders(
      NotificationSettings s) async {
    final start = _minutesOf(s.waterStartTime, fallbackHour: 8);
    final end = _minutesOf(s.waterEndTime, fallbackHour: 22);
    final interval = s.waterIntervalHours.clamp(1, 12) * 60;

    // Read once for the whole batch, so every slot carries the same figure
    // rather than drifting if a write lands mid-loop.
    final body = waterReminderBody(
      goalMl: s.waterGoalMl,
      shortfallMl: _waterShortfall(s.waterGoalMl),
    );

    final scheduled = <String>[];
    var id = waterBaseId;

    for (var t = start;
        t <= end && id < waterBaseId + waterMaxSlots;
        t += interval) {
      final hh = t ~/ 60;
      final mm = t % 60;
      await _schedule(
        id: id++,
        title: '💧 Stay Hydrated!',
        body: body,
        when: _nextOccurrence(hh, mm),
        payload: 'water',
        details: const NotificationDetails(
          android: AndroidNotificationDetails(
            _waterChannelId,
            'Water Reminders',
            channelDescription: 'Hydration reminders through the day',
            importance: Importance.high,
            priority: Priority.high,
            sound: _chime,
            icon: '@drawable/ic_notification',
            color: AppNotificationColors.water,
            category: AndroidNotificationCategory.reminder,
          ),
        ),
      );
      scheduled.add(_fmt(hh, mm));
    }
    return scheduled;
  }

  // ── Meal reminders ─────────────────────────────────────────────────────────

  static Future<List<String>> _scheduleMealReminders(
      NotificationSettings s) async {
    final scheduled = <String>[];

    for (var i = 0; i < s.mealTimes.length && i < mealMaxSlots; i++) {
      final label = i < s.mealLabels.length ? s.mealLabels[i] : 'Meal';
      await scheduleMealReminder(
        slot: i,
        label: label,
        time: s.mealTimes[i],
      );
      scheduled.add('$label at ${s.mealTimes[i]}');
    }
    return scheduled;
  }

  /// Schedules (or replaces) a single meal slot, so editing one time in the
  /// Reminders screen doesn't have to rewrite the whole set.
  static Future<void> scheduleMealReminder({
    required int slot,
    required String label,
    required String time,
  }) async {
    final id = mealBaseId + slot;
    await _plugin.cancel(id);
    if (!_hasAccount) return;

    final minutes = _minutesOf(time, fallbackHour: 8);
    await _schedule(
      id: id,
      title: '${_mealEmoji(label)} Time for $label!',
      body: 'Log your $label to stay on track with your goals.',
      when: _nextOccurrence(minutes ~/ 60, minutes % 60),
      payload: 'meal:$label',
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          _mealChannelId,
          'Meal Reminders',
          channelDescription:
              'Reminders to log breakfast, lunch, dinner and snacks',
          importance: Importance.high,
          priority: Priority.high,
          sound: _chime,
          icon: '@drawable/ic_notification',
          color: AppNotificationColors.meal,
          category: AndroidNotificationCategory.reminder,
          actions: [
            AndroidNotificationAction(
              actionLogMeal,
              'Log meal',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              actionSkipMeal,
              'Skip',
              cancelNotification: true,
            ),
          ],
        ),
      ),
    );
  }

  static const actionLogMeal = 'log_meal';
  static const actionSkipMeal = 'skip_meal';

  static String _mealEmoji(String label) {
    switch (label.toLowerCase()) {
      case 'breakfast':
        return '🍳';
      case 'lunch':
        return '🥗';
      case 'dinner':
        return '🍽️';
      case 'snack':
        return '🍎';
      default:
        return '🍴';
    }
  }

  // ── Step reminders ─────────────────────────────────────────────────────────

  /// Quotes the target, deliberately not the progress.
  ///
  /// Water reminders can say "1.2L left" because logging a glass is an explicit
  /// tap that re-registers them ([refreshWaterReminders]); the body is baked in
  /// when the alarm is registered and no Dart runs when it fires. Steps have no
  /// such moment — they arrive continuously from the sensor, and re-registering
  /// alarms on every reading would be a platform round trip per step batch. So
  /// a step body that quoted "6,200 to go" would be a figure from whenever the
  /// schedule was last written, which is usually the small hours. The target
  /// alone is always true and still the user's own number.
  @visibleForTesting
  static String stepReminderBody(int goal, {required bool evening}) => evening
      ? 'Push for your ${_count(goal)} steps before bedtime!'
      : 'Halfway through the day — on track for ${_count(goal)} steps?';

  static Future<void> scheduleStepReminders(NotificationSettings s) async {
    await _schedule(
      id: stepBaseId,
      title: '🚶 Step Check!',
      body: stepReminderBody(s.stepsGoal, evening: false),
      when: _nextOccurrence(12, 0),
      payload: 'step',
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          _stepChannelId,
          'Step Reminders',
          channelDescription: 'Daily step goal check-ins',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          sound: _chime,
          icon: '@drawable/ic_notification',
          color: AppNotificationColors.step,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
    );

    await _schedule(
      id: stepBaseId + 1,
      title: '🏃 Almost There!',
      body: stepReminderBody(s.stepsGoal, evening: true),
      when: _nextOccurrence(20, 0),
      payload: 'step',
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          _stepChannelId,
          'Step Reminders',
          channelDescription: 'Daily step goal check-ins',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          sound: _chime,
          icon: '@drawable/ic_notification',
          color: AppNotificationColors.step,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
    );
  }

  // ── Sleep reminder ─────────────────────────────────────────────────────────

  /// Fires 30 minutes before [bedtime] ("23:00"), wrapping correctly across
  /// midnight — 00:15 becomes 23:45 the previous evening.
  static Future<void> scheduleSleepReminder(String bedtime) async {
    final bed = _minutesOf(bedtime, fallbackHour: 23);
    final remindAt = (bed - 30 + 1440) % 1440;

    await _schedule(
      id: sleepBaseId,
      title: '🌙 Bedtime Soon!',
      body: 'Your sleep window opens in 30 minutes — start winding down.',
      when: _nextOccurrence(remindAt ~/ 60, remindAt % 60),
      payload: 'sleep',
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          _sleepChannelId,
          'Sleep Reminders',
          channelDescription: 'Bedtime wind-down reminders',
          importance: Importance.high,
          priority: Priority.high,
          sound: _chime,
          icon: '@drawable/ic_notification',
          color: AppNotificationColors.sleep,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
    );
  }

  // ── Cancellation ───────────────────────────────────────────────────────────

  static Future<void> cancelWater() =>
      _cancelRange(waterBaseId, waterBaseId + waterMaxSlots);

  static Future<void> cancelMeals() =>
      _cancelRange(mealBaseId, mealBaseId + mealMaxSlots);

  /// Cancels a single meal slot — used when a slot is removed with the minus
  /// button, which would otherwise leave its alarm firing forever.
  static Future<void> cancelMeal(int slot) => _plugin.cancel(mealBaseId + slot);

  static Future<void> cancelSteps() =>
      _cancelRange(stepBaseId, stepBaseId + stepSlots);

  static Future<void> cancelSleep() => _plugin.cancel(sleepBaseId);

  // ── Onboarding follow-up ───────────────────────────────────────────────────

  /// Nudges someone who walked out of the sign-up wizard part-way.
  ///
  /// Two of them, an hour and a day out. One is easy to miss; a third would be
  /// nagging about a form.
  ///
  /// Deliberately *not* routed through [_schedule]. That helper attaches
  /// `matchDateTimeComponents: DateTimeComponents.time`, which turns every
  /// alarm into a daily repeat — correct for a bedtime reminder and badly
  /// wrong here, where it would ask the user to finish signing up at 7pm every
  /// evening for the rest of the install.
  ///
  /// Cancelled by [cancelOnboardingFollowUp] the moment the profile saves, and
  /// untouched by [cancelReminders] so a reschedule cannot drop it.
  static Future<void> scheduleOnboardingFollowUp() async {
    if (!_hasAccount) return;
    await init();
    await _refreshExactAlarmCapability();
    await cancelOnboardingFollowUp();

    if (!await areNotificationsEnabled()) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _setupChannelId,
        'Finish Setup',
        channelDescription:
            'A nudge to complete your profile if you leave part-way',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        sound: _chime,
      ),
    );

    const nudges = [
      (0, Duration(hours: 1), 'Your plan is nearly ready',
          'You are a couple of taps from your daily targets — pick up where you left off.'),
      (1, Duration(hours: 24), 'Still want your plan?',
          'Your answers are saved. Finish setting up and Proteinix will work out your targets.'),
    ];

    final mode = _exactAlarmsAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    for (final (slot, delay, title, body) in nudges) {
      try {
        await _plugin.zonedSchedule(
          onboardingBaseId + slot,
          title,
          body,
          tz.TZDateTime.now(tz.local).add(delay),
          details,
          androidScheduleMode: mode,
          // No matchDateTimeComponents — see above. These fire once.
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'onboarding',
        );
      } catch (e, st) {
        await CrashLog.record('Onboarding follow-up $slot failed: $e', st);
      }
    }
  }

  static Future<void> cancelOnboardingFollowUp() =>
      _cancelRange(onboardingBaseId, onboardingBaseId + onboardingSlots);

  /// Clears every scheduled reminder but leaves one-off goal alerts alone.
  static Future<void> cancelReminders() async {
    await cancelWater();
    await cancelMeals();
    await cancelSteps();
    await cancelSleep();
  }

  /// Cancel everything, including goal alerts.
  static Future<void> cancelAll() => _plugin.cancelAll();

  static Future<void> _cancelRange(int from, int toExclusive) async {
    for (var i = from; i < toExclusive; i++) {
      await _plugin.cancel(i);
    }
  }

  // ── Diagnostics ────────────────────────────────────────────────────────────

  /// Alarms Android currently holds for this app — the ground truth when a user
  /// reports missing reminders.
  static Future<List<PendingNotificationRequest>> pending() async {
    await init();
    return _plugin.pendingNotificationRequests();
  }

  /// Posts a notification immediately so the user can confirm the whole chain
  /// (permission → channel → sound) works, without waiting for a real reminder.
  static Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      testId,
      '🔔 Reminders are working',
      'This is what your Proteinix reminders will look like.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _liveChannelId,
          'Progress Alerts',
          channelDescription:
              'Celebrates goals as you hit them through the day',
          importance: Importance.high,
          priority: Priority.high,
          sound: _chime,
          icon: '@drawable/ic_notification',
        ),
      ),
    );
  }

  // ── Instant (real-time) notifications ──────────────────────────────────────

  /// Posts a notification immediately, outside the scheduled reminder system.
  ///
  /// [id] must be stable per alert type so repeat posts replace rather than
  /// stack up in the shade.
  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _liveChannelId,
          'Progress Alerts',
          channelDescription:
              'Celebrates goals as you hit them through the day',
          importance: Importance.high,
          priority: Priority.high,
          sound: _chime,
          icon: '@drawable/ic_notification',
        ),
      ),
    );
  }

  // ── Utility ────────────────────────────────────────────────────────────────

  /// Parses "HH:mm" into minutes-since-midnight.
  static int _minutesOf(String hhmm, {required int fallbackHour}) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? fallbackHour;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (h.clamp(0, 23) * 60) + m.clamp(0, 59);
  }

  static String _fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  /// Returns the next local occurrence of [hour]:[minute].
  /// If today's time has already passed, returns tomorrow.
  static tz.TZDateTime _nextOccurrence(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static String _todayKey() =>
      DateTime.now().toIso8601String().split('T').first;
}

/// Accent colours used on the notification itself (the tinted small icon and
/// app name). Kept next to the service so they stay `const` — `AndroidNotifica-
/// tionDetails` has to be const-constructible for the channel definitions.
class AppNotificationColors {
  const AppNotificationColors._();

  static const water = Color(0xFF00A2FF); // AppColors.hydrationBlue
  static const meal = Color(0xFFFF5F1F); // AppColors.primaryContainer
  static const step = Color(0xFFA9D300); // AppColors.secondaryContainer
  static const sleep = Color(0xFF7C3AED);
}

/// Fires a one-off congratulation the moment a daily goal is reached.
///
/// Each goal alerts at most once per calendar day; the last-fired date is kept
/// in SharedPreferences so restarting the app doesn't re-trigger it.
class GoalAlerts {
  const GoalAlerts._();

  static const _water =
      _Alert(key: 'water', id: 900, title: '💧 Hydration goal reached');
  static const _steps =
      _Alert(key: 'steps', id: 901, title: '🔥 Step goal smashed');
  static const _protein =
      _Alert(key: 'protein', id: 902, title: '💪 Protein goal met');
  static const _calories =
      _Alert(key: 'calories', id: 903, title: '🍽️ Calorie budget reached');

  // Bodies are built here rather than stored on [_Alert], so each names the
  // target the user actually set. Every caller already passes their real goal
  // from the profile — it was only ever used as a threshold and then thrown
  // away, leaving four congratulations that could have been written for anyone.
  //
  // Safe to do at this point in a way the scheduled reminders can't: these fire
  // through `showNow` the instant the goal is crossed, with the app running, so
  // the number is read at the moment it is shown and cannot go stale.

  /// Each body names the target the user actually set, so the four are grouped
  /// here and kept pure — the number is the whole point of the change and the
  /// only part worth a test.
  @visibleForTesting
  static String waterBody(int goal) =>
      "That's your ${NotificationService._volume(goal)} of water for today. "
      'Nicely done.';

  @visibleForTesting
  static String stepsBody(int goal) =>
      'You reached your ${NotificationService._count(goal)}-step target. '
      'Keep the streak alive!';

  @visibleForTesting
  static String proteinBody(double goal) =>
      '${NotificationService._grams(goal)} of protein is in the bag.';

  @visibleForTesting
  static String caloriesBody(int goal) =>
      "You've hit your ${NotificationService._count(goal)} kcal target "
      'for today.';

  static Future<void> water(int consumed, int goal) =>
      _check(_water, consumed.toDouble(), goal.toDouble(), waterBody(goal));

  static Future<void> steps(int consumed, int goal) =>
      _check(_steps, consumed.toDouble(), goal.toDouble(), stepsBody(goal));

  static Future<void> protein(double consumed, double goal) =>
      _check(_protein, consumed, goal, proteinBody(goal));

  static Future<void> calories(int consumed, int goal) => _check(
      _calories, consumed.toDouble(), goal.toDouble(), caloriesBody(goal));

  static Future<void> _check(
      _Alert alert, double consumed, double goal, String body) async {
    if (goal <= 0 || consumed < goal) return;

    final prefs = await SharedPreferences.getInstance();
    final storeKey = 'goal_alert_${alert.key}';
    final today = DateTime.now().toIso8601String().split('T').first;
    if (prefs.getString(storeKey) == today) return;

    await prefs.setString(storeKey, today);
    await NotificationService.showNow(
      id: alert.id,
      title: alert.title,
      body: body,
    );
  }
}

class _Alert {
  const _Alert({required this.key, required this.id, required this.title});

  final String key;
  final int id;
  final String title;
}

// ── Settings model ───────────────────────────────────────────────────────────

class NotificationSettings {
  final bool waterEnabled;
  final int waterIntervalHours;
  final String waterStartTime;
  final String waterEndTime;
  /// Targets quoted in reminder bodies. Not preferences and not persisted with
  /// the rest of this object — [NotificationService.load] fills them from the
  /// user's profile on every read, and [NotificationService.savePreferences]
  /// deliberately ignores them. The defaults below apply only when there is no
  /// profile to read.
  final int waterGoalMl;
  final int stepsGoal;
  final bool mealEnabled;
  final List<String> mealTimes; // ["08:00", "13:00", "19:00", "16:00"]
  final List<String> mealLabels; // ["Breakfast", "Lunch", "Dinner", "Snack"]
  final bool stepEnabled;
  final bool sleepEnabled;
  final String sleepBedtime; // "23:00"

  const NotificationSettings({
    required this.waterEnabled,
    required this.waterIntervalHours,
    required this.waterStartTime,
    required this.waterEndTime,
    this.waterGoalMl = NotificationService.defaultWaterGoalMl,
    this.stepsGoal = NotificationService.defaultStepsGoal,
    required this.mealEnabled,
    required this.mealTimes,
    required this.mealLabels,
    this.stepEnabled = false,
    this.sleepEnabled = false,
    this.sleepBedtime = '23:00',
  });

  bool get anyEnabled =>
      waterEnabled || mealEnabled || stepEnabled || sleepEnabled;

  NotificationSettings copyWith({
    bool? waterEnabled,
    int? waterIntervalHours,
    String? waterStartTime,
    String? waterEndTime,
    int? waterGoalMl,
    int? stepsGoal,
    bool? mealEnabled,
    List<String>? mealTimes,
    List<String>? mealLabels,
    bool? stepEnabled,
    bool? sleepEnabled,
    String? sleepBedtime,
  }) {
    return NotificationSettings(
      waterEnabled: waterEnabled ?? this.waterEnabled,
      waterIntervalHours: waterIntervalHours ?? this.waterIntervalHours,
      waterStartTime: waterStartTime ?? this.waterStartTime,
      waterEndTime: waterEndTime ?? this.waterEndTime,
      waterGoalMl: waterGoalMl ?? this.waterGoalMl,
      stepsGoal: stepsGoal ?? this.stepsGoal,
      mealEnabled: mealEnabled ?? this.mealEnabled,
      mealTimes: mealTimes ?? this.mealTimes,
      mealLabels: mealLabels ?? this.mealLabels,
      stepEnabled: stepEnabled ?? this.stepEnabled,
      sleepEnabled: sleepEnabled ?? this.sleepEnabled,
      sleepBedtime: sleepBedtime ?? this.sleepBedtime,
    );
  }
}
