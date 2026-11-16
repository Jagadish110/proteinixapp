import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import '../core/utils/date_utils.dart';

/// Fallback step tracker using the phone's hardware pedometer sensor.
/// Used when Health Connect is unavailable (e.g., Infinix, older devices).
///
/// Only listens to the sensor while the app is running — deliberately no
/// background service. A persistent foreground service was tried and works,
/// but costs a permanent notification and background battery drain, which
/// isn't a trade-off worth making for step counting alone.
///
/// The underlying TYPE_STEP_COUNTER sensor keeps counting while the app is
/// closed, but it reports a single total since boot and carries no history, so
/// steps taken while the app was shut cannot be attributed to a date *from
/// this stream alone*. On the first read of a new day the count below
/// therefore starts from the current reading.
///
/// That gap is now covered natively rather than only by Health Connect. A
/// half-hourly alarm-driven broadcast (`StepCounter.kt`) reads the same
/// hardware counter while the app is closed, so a reading always exists from
/// just before midnight to anchor the new day against. [todaySteps] returns
/// the larger of that figure and this stream's, and the dashboard then takes
/// the larger again of that and Health Connect. Every source is a floor;
/// whichever knows most wins, and none of them can inflate another.
///
/// This mattered on exactly the devices Health Connect does not cover — the
/// same Infinix / older-Android phones this fallback exists for. Walk before
/// opening the app and the entire morning was gone.
class PedometerService {
  static final PedometerService _instance = PedometerService._();
  factory PedometerService() => _instance;
  PedometerService._();

  static final StreamController<int> stepsController =
      StreamController<int>.broadcast();

  static const _ch = MethodChannel('com.proteinix/step_tracking');

  /// Today's total as counted by the native sampler, which runs whether or not
  /// the app is open. Refreshed by [start] and [syncNative].
  int _nativeSteps = 0;

  StreamSubscription<StepCount>? _stepSub;
  StreamSubscription<PedestrianStatus>? _statusSub;

  int _stepsAtDayStart = 0;
  int _todaySteps = 0;
  String _lastSyncDate = '';
  bool _isWalking = false;

  double _weightKg = 70.0;
  double _heightCm = 170.0;
  String _gender = 'male';

  bool get isWalking => _isWalking;

  /// Steps so far today — but only if `_todaySteps` actually belongs to
  /// today.
  ///
  /// It's only ever updated *inside* `_onStep`, which needs a fresh sensor
  /// callback to run at all. Cross midnight with the app open and no step
  /// taken yet since, and nothing had a reason to touch it — this kept
  /// reporting yesterday's count until the first step of the new day, and
  /// callers had no way to tell a real number from a leftover one. Checked
  /// against the wall clock on every read instead of waiting for the sensor.
  int get todaySteps {
    final live =
        _lastSyncDate == AppDateUtils.iso(DateTime.now()) ? _todaySteps : 0;
    // The native sampler saw the parts of today this stream could not — the
    // walk taken before the app was opened, most of all — so it is usually the
    // larger and always the safer of the two. Neither can invent steps, so
    // taking the maximum can only improve the figure.
    return live > _nativeSteps ? live : _nativeSteps;
  }

  /// Takes a native reading now and re-books the sampling alarms.
  ///
  /// Never throws — there is no channel on a non-Android host, and a phone
  /// that refuses the sensor must still render a dashboard.
  Future<void> syncNative() async {
    try {
      final steps = await _ch.invokeMethod<int>('syncSteps');
      // Assigned even when zero. The native side reports 0 once the stored
      // total belongs to a previous day, and skipping that would leave
      // yesterday's figure standing as a floor for today on any app left open
      // across midnight — the exact staleness [todaySteps] guards against on
      // the stream side.
      if (steps != null) {
        _nativeSteps = steps;
        stepsController.add(todaySteps);
      }
    } catch (_) {
      // No native host, or no step sensor. The stream below still counts.
    }
  }

  /// Calories burned using a height/gender-based stride formula:
  ///   stride = gender == 'male' ? heightCm * 0.00415 : heightCm * 0.00413
  ///   distKm = (steps * stride) / 1000
  ///   kcal = distKm * weightKg * 1.036
  int get caloriesBurned =>
      _calcCalories(todaySteps, _weightKg, _heightCm, _gender);

  static int _calcCalories(
    int steps,
    double weightKg,
    double heightCm,
    String gender,
  ) {
    final stride = gender.toLowerCase() == 'male'
        ? heightCm * 0.00415
        : heightCm * 0.00413;
    final distKm = (steps * stride) / 1000;
    return (distKm * weightKg * 1.036).round();
  }

  /// [weightKg], [heightCm], [gender] — pass the user's profile info for accurate estimates.
  Future<void> start({
    double weightKg = 70.0,
    double heightCm = 170.0,
    String gender = 'male',
  }) async {
    _weightKg = weightKg;
    _heightCm = heightCm;
    _gender = gender;

    // Before the stream, so a dashboard drawn on the first frame already has
    // the morning in hand rather than a zero that fills in a second later.
    await syncNative();

    final prefs = await SharedPreferences.getInstance();
    _stepsAtDayStart = prefs.getInt('steps_day_start') ?? 0;
    _lastSyncDate = prefs.getString('steps_sync_date') ?? '';
    _todaySteps = prefs.getInt('steps_today') ?? 0;

    // If already subscribed (resumed from background), don't re-subscribe
    if (_stepSub != null) return;

    _stepSub = Pedometer.stepCountStream.listen(
      _onStep,
      onError: (_) {}, // silently ignore if sensor unavailable
    );

    _statusSub = Pedometer.pedestrianStatusStream.listen(
      (status) => _isWalking = status.status == 'walking',
      onError: (_) {},
    );
  }

  /// Where today's count starts from, given a raw sensor reading.
  ///
  /// Pure, and separated from the plumbing on purpose: this arithmetic is the
  /// whole feature and it has been wrong in production once already.
  ///
  /// `TYPE_STEP_COUNTER` counts from the last boot, not from any date, and it
  /// restarts at zero when the phone does. Everything below exists to keep
  /// "steps today" correct across the two events that break that mapping — a
  /// midnight, and a reboot.
  @visibleForTesting
  static int resolveBaseline({
    required int raw,
    required int? lastRaw,
    required String lastSyncDate,
    required String today,
    required int baseline,
    required int todaySteps,
  }) {
    // The counter is monotonic within a boot, so a reading lower than the last
    // one we saw can only mean the device restarted.
    final rebooted = lastRaw != null && raw < lastRaw;

    if (lastSyncDate != today) {
      // A new day starts from the reading in hand.
      //
      // This used to rebase on yesterday's last raw reading instead, to recover
      // a morning walk taken before the app was reopened. But that reading is
      // from whenever the app was last open yesterday — not from midnight — so
      // everything walked between the two got credited to today as well. A
      // phone put down after an evening walk and picked up the next morning
      // opened on ~1,100 steps against 54 actually taken: the gap crosses a
      // midnight, and the sensor gives one cumulative total with no timestamps
      // to split it on.
      //
      // Neither half of that gap can be identified, so the choice is to count
      // all of it or none of it. None: a fitness app that invents steps is
      // worse than one that misses the ones taken before it was opened. It
      // also makes this figure a floor rather than a guess, which is what lets
      // the dashboard safely take the higher of it and Health Connect —
      // whichever source knows more wins, and neither can inflate the other.
      return raw;
    }

    // Same day, fresh counter. Everything walked before the reboot is already
    // in [todaySteps] and the sensor is now counting the rest from zero, so a
    // negative baseline makes the usual subtraction add the two together
    // instead of discarding the first half.
    //
    // Without this the baseline stayed at its pre-reboot value — tens of
    // thousands — against a sensor reading in single digits, so the difference
    // clamped to 0. Restarting the phone wiped the day's steps from the
    // display, from SharedPreferences, and via forceSync from the server row.
    if (rebooted) return -todaySteps;

    return baseline;
  }

  void _onStep(StepCount event) async {
    final now = DateTime.now();
    final today = AppDateUtils.iso(now);
    final prefs = await SharedPreferences.getInstance();

    final resolved = resolveBaseline(
      raw: event.steps,
      lastRaw: prefs.getInt('steps_raw_cumulative'),
      lastSyncDate: _lastSyncDate,
      today: today,
      baseline: _stepsAtDayStart,
      todaySteps: _todaySteps,
    );

    if (resolved != _stepsAtDayStart || _lastSyncDate != today) {
      if (_lastSyncDate != today) _todaySteps = 0;
      _stepsAtDayStart = resolved;
      _lastSyncDate = today;
      await _persistBaseline(resolved, today);
    }

    final newSteps = (event.steps - _stepsAtDayStart).clamp(0, 999999);
    _todaySteps = newSteps;
    // Publish the reconciled figure, not the raw stream one. Emitting
    // `newSteps` here would drop the ring back to the morning's leftovers on
    // every step, because this stream restarts from zero each day while the
    // native count does not.
    stepsController.add(todaySteps);

    // Persist today's step count, plus the raw cumulative reading — the latter
    // is how the next callback tells a reboot (reading went backwards) from an
    // ordinary increment.
    await prefs.setInt('steps_today', newSteps);
    await prefs.setInt('steps_raw_cumulative', event.steps);

    // Sync to Supabase every 50 steps
    if (newSteps > 0 && newSteps % 50 == 0) {
      await _syncToSupabase(today, newSteps);
    }
  }

  Future<void> _syncToSupabase(String dateIso, int steps) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    try {
      final calories = _calcCalories(steps, _weightKg, _heightCm, _gender);
      await SupabaseService.client.from('daily_logs').upsert({
        'user_id': uid,
        'date': dateIso,
        'steps': steps,
        'calories_burned': calories,
      }, onConflict: 'user_id,date');
    } catch (_) {}
  }

  Future<void> _persistBaseline(int steps, String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('steps_day_start', steps);
    await prefs.setString('steps_sync_date', date);
  }

  void stop() {
    _stepSub?.cancel();
    _stepSub = null;
    _statusSub?.cancel();
    _statusSub = null;
  }
}
