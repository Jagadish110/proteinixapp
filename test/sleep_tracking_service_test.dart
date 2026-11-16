import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/services/sleep_tracking_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.proteinix/sleep_tracking');

SleepNight _night({required int interruptions, required int pickups}) =>
    SleepNight.fromNative({
      'date': '2026-08-07',
      'hours': 6.0,
      'interruptions': interruptions,
      'phonePickups': pickups,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  /// [responses] is keyed by method name; a missing entry throws, which is how
  /// a host without the native plugin behaves.
  void mockChannel(Map<String, Object?> responses) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (!responses.containsKey(call.method)) {
        throw MissingPluginException('no mock for ${call.method}');
      }
      return responses[call.method];
    });
  }

  setUp(() => calls.clear());

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('formatTime', () {
    test('converts 24h to 12h', () {
      expect(SleepTrackingService.formatTime('22:30', 'x'), '10:30 PM');
      expect(SleepTrackingService.formatTime('06:30', 'x'), '06:30 AM');
    });

    test('handles the midnight and noon edges', () {
      expect(SleepTrackingService.formatTime('00:15', 'x'), '12:15 AM');
      expect(SleepTrackingService.formatTime('12:00', 'x'), '12:00 PM');
    });

    test('falls back on anything unparseable', () {
      for (final bad in [null, '', 'nonsense', '25:00', '10:99', '10']) {
        expect(SleepTrackingService.formatTime(bad, 'fallback'), 'fallback',
            reason: 'input: $bad');
      }
    });
  });

  group('window', () {
    test('wraps past midnight', () {
      expect(SleepTrackingService.window('22:30', '06:30'),
          const Duration(hours: 8));
      expect(SleepTrackingService.window('23:00', '07:00'),
          const Duration(hours: 8));
    });

    test('handles a same-day window', () {
      expect(SleepTrackingService.window('01:00', '09:30'),
          const Duration(hours: 8, minutes: 30));
    });
  });

  group('status', () {
    test('reports the saved window and a running tracker', () async {
      SharedPreferences.setMockInitialValues({
        SleepTrackingService.prefsBedtime: '23:00',
        SleepTrackingService.prefsWake: '07:00',
      });
      mockChannel({
        'getTrackingState': {'armed': true, 'running': true},
      });

      final status = await SleepTrackingService.status();
      expect(status.bedtime, '23:00');
      expect(status.wake, '07:00');
      expect(status.phase, SleepTrackingPhase.active);
    });

    // Arming outside the sleep window schedules the alarms without starting the
    // service. Reading `running` alone made the card snap back to OFF as though
    // the tap had failed.
    test('armed outside the window is not off', () async {
      SharedPreferences.setMockInitialValues({});
      mockChannel({
        'getTrackingState': {'armed': true, 'running': false},
      });

      final status = await SleepTrackingService.status();
      expect(status.armed, isTrue);
      expect(status.phase, SleepTrackingPhase.armed);
    });

    test('is off only when the user switched it off', () async {
      SharedPreferences.setMockInitialValues({});
      mockChannel({
        'getTrackingState': {'armed': false, 'running': false},
      });

      expect((await SleepTrackingService.status()).phase,
          SleepTrackingPhase.off);
    });

    // The card always needs times to show and edit, so these can never be null.
    test('falls back to default times before anything is saved', () async {
      SharedPreferences.setMockInitialValues({});
      mockChannel({
        'getTrackingState': {'armed': false, 'running': false},
      });

      final status = await SleepTrackingService.status();
      expect(status.bedtime, SleepTrackingService.defaultBedtime);
      expect(status.wake, SleepTrackingService.defaultWake);
    });

    // The dashboard must still render on a host with no native plugin.
    test('survives a missing platform channel', () async {
      SharedPreferences.setMockInitialValues({
        SleepTrackingService.prefsBedtime: '23:00',
      });
      mockChannel({});

      final status = await SleepTrackingService.status();
      expect(status.phase, SleepTrackingPhase.off);
      expect(status.bedtime, '23:00', reason: 'prefs still readable');
    });
  });

  group('start', () {
    test('saves the window and hands it to the native service', () async {
      SharedPreferences.setMockInitialValues({});
      mockChannel({'startTracking': true});

      await SleepTrackingService.start(bedtime: '23:15', wake: '06:45');

      final call = calls.single;
      expect(call.method, 'startTracking');
      expect(call.arguments['sleepTime'], '23:15');
      expect(call.arguments['wakeTime'], '06:45');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SleepTrackingService.prefsBedtime), '23:15');
      expect(prefs.getString(SleepTrackingService.prefsWake), '06:45');
    });

    // Editing a time while tracking is off must not arm it.
    test('saveSchedule persists without touching the native service', () async {
      SharedPreferences.setMockInitialValues({});
      mockChannel({'startTracking': true});

      await SleepTrackingService.saveSchedule(bedtime: '00:30', wake: '08:00');

      expect(calls, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SleepTrackingService.prefsBedtime), '00:30');
    });
  });

  test('stop calls through to the native service', () async {
    mockChannel({'stopTracking': true});
    await SleepTrackingService.stop();
    expect(calls.single.method, 'stopTracking');
  });

  group('lastNight', () {
    test('reads the night the receiver observed', () async {
      mockChannel({
        'getSleepResult': {
          'date': '2026-08-07',
          'hours': 7.6,
          'interruptions': 2,
          'status': 'complete',
        },
      });

      final night = await SleepTrackingService.lastNight();
      expect(night.date, DateTime(2026, 8, 7));
      expect(night.interruptions, 2);
      expect(night.status, SleepNightStatus.complete);
      expect(night.usable, isTrue);
      expect(night.summary, '7h 36m');
    });

    // Still being observed: safe to write, because the figures only grow and
    // MealService.setSleep ignores anything shorter than what it already holds.
    test('a night in progress is usable', () async {
      mockChannel({
        'getSleepResult': {
          'date': '2026-08-07',
          'hours': 3.5,
          'interruptions': 0,
          'status': 'in_progress',
        },
      });

      expect((await SleepTrackingService.lastNight()).usable, isTrue);
    });

    // The heartbeat case: the sampler stopped mid-night, so what it saw is a
    // floor of unknown depth — but a floor is still worth writing. Withholding
    // it left daily_logs permanently empty on every phone whose battery
    // manager drops an alarm, and setSleep only ever raises what it holds.
    test('a night the sampler did not finish is still usable', () async {
      mockChannel({
        'getSleepResult': {
          'date': '2026-08-07',
          'hours': 4.2,
          'interruptions': 1,
          'status': 'partial',
        },
      });

      final night = await SleepTrackingService.lastNight();
      expect(night.status, SleepNightStatus.partial);
      expect(night.usable, isTrue, reason: 'a floor is better than nothing');
    });

    test('reads pickups and the observed sleep span', () async {
      mockChannel({
        'getSleepResult': {
          'date': '2026-08-07',
          'hours': 6.0,
          'interruptions': 1,
          'phonePickups': 3,
          'sleepStart': 1786000000000,
          'sleepEnd': 1786021600000,
          'status': 'complete',
        },
      });

      final night = await SleepTrackingService.lastNight();
      expect(night.interruptions, 1);
      expect(night.phonePickups, 3);
      expect(night.sleepStart,
          DateTime.fromMillisecondsSinceEpoch(1786000000000));
      expect(night.sleepEnd, DateTime.fromMillisecondsSinceEpoch(1786021600000));
    });

    // Nights recorded before the span was tracked send 0, which is a missing
    // value and not the epoch.
    test('treats a zero timestamp as absent', () async {
      mockChannel({
        'getSleepResult': {
          'date': '2026-08-07',
          'hours': 6.0,
          'sleepStart': 0,
          'sleepEnd': 0,
          'status': 'complete',
        },
      });

      final night = await SleepTrackingService.lastNight();
      expect(night.sleepStart, isNull);
      expect(night.sleepEnd, isNull);
    });
  });

  group('wakeUps', () {
    // Pickups include the one that ends the night, so folding them in would
    // report an undisturbed night as one wake-up.
    test('counts interruptions only, never pickups', () {
      expect(_night(interruptions: 0, pickups: 1).wakeUps, 0);
      expect(_night(interruptions: 2, pickups: 5).wakeUps, 2);
    });

    test('is empty before a night has been recorded', () async {
      mockChannel({
        'getSleepResult': {
          'date': null,
          'hours': 0.0,
          'interruptions': 0,
          'status': 'in_progress',
        },
      });

      final night = await SleepTrackingService.lastNight();
      expect(night.isEmpty, isTrue);
      expect(night.summary, isNull);
    });

    test('survives a missing platform channel', () async {
      mockChannel({});
      expect((await SleepTrackingService.lastNight()).usable, isFalse);
    });
  });

  // The banked nights. Without these, a night existed only until the next
  // bedtime wiped the counters — so waking up and not opening the app before
  // going to bed again lost it, and nothing was ever written to daily_logs.
  group('history', () {
    test('reads every banked night', () async {
      mockChannel({
        'getSleepHistory': [
          {
            'date': '2026-08-06',
            'hours': 7.0,
            'interruptions': 0,
            'phonePickups': 0,
            'status': 'complete',
          },
          {
            'date': '2026-08-07',
            'hours': 5.5,
            'interruptions': 2,
            'phonePickups': 1,
            'status': 'partial',
          },
        ],
      });

      final nights = await SleepTrackingService.history();
      expect(nights.map((n) => n.date),
          [DateTime(2026, 8, 6), DateTime(2026, 8, 7)]);
      expect(nights.last.wakeUps, 2);
      expect(nights.every((n) => n.usable), isTrue);
    });

    // Nothing downstream should have to filter these out before writing.
    test('drops entries with nothing in them', () async {
      mockChannel({
        'getSleepHistory': [
          {'date': '2026-08-06', 'hours': 0.0, 'status': 'complete'},
          {'date': null, 'hours': 6.0, 'status': 'complete'},
        ],
      });

      expect(await SleepTrackingService.history(), isEmpty);
    });

    test('survives a missing platform channel', () async {
      mockChannel({});
      expect(await SleepTrackingService.history(), isEmpty);
    });
  });

  // The morning report is posted natively, with no engine alive to hold a
  // notification payload, so it hands its destination over as an Intent extra.
  group('consumeLaunchRoute', () {
    test('returns the route a tapped report left behind', () async {
      mockChannel({'consumeLaunchRoute': '/sleep'});
      expect(await SleepTrackingService.consumeLaunchRoute(), '/sleep');
    });

    test('is null when nothing is waiting', () async {
      mockChannel({'consumeLaunchRoute': null});
      expect(await SleepTrackingService.consumeLaunchRoute(), isNull);
    });

    // Called on every startup, including on hosts with no native side.
    test('survives a missing platform channel', () async {
      mockChannel({});
      expect(await SleepTrackingService.consumeLaunchRoute(), isNull);
    });
  });

  group('noteAppOpen', () {
    test('tells the native sampler the app came to the foreground', () async {
      mockChannel({'noteAppOpen': true});
      await SleepTrackingService.noteAppOpen();
      expect(calls.single.method, 'noteAppOpen');
    });

    // Called on every resume, including on hosts with no native side.
    test('survives a missing platform channel', () async {
      mockChannel({});
      await expectLater(SleepTrackingService.noteAppOpen(), completes);
    });
  });
}
