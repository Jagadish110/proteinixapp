import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/services/pedometer_service.dart';

/// `TYPE_STEP_COUNTER` reports steps since the last *boot*, so turning today's
/// figure into a date-based one means holding a baseline — and that baseline is
/// wrong the moment either the date or the boot changes.
const today = '2026-08-12';
const yesterday = '2026-08-11';

int baselineFor({
  required int raw,
  int? lastRaw,
  String lastSyncDate = today,
  int baseline = 0,
  int todaySteps = 0,
}) =>
    PedometerService.resolveBaseline(
      raw: raw,
      lastRaw: lastRaw,
      lastSyncDate: lastSyncDate,
      today: today,
      baseline: baseline,
      todaySteps: todaySteps,
    );

/// What the caller computes from the baseline.
int stepsFrom(int raw, int baseline) => (raw - baseline).clamp(0, 999999);

void main() {
  group('steady state', () {
    test('keeps the baseline while the day and the boot both hold', () {
      final b = baselineFor(
          raw: 108000, lastRaw: 107500, baseline: 100000);
      expect(b, 100000);
      expect(stepsFrom(108000, b), 8000);
    });
  });

  group('reboot mid-day', () {
    // The bug this file exists for: the counter restarts at zero while the
    // baseline is still tens of thousands, so the difference clamps to 0 and
    // the day's steps vanish from the UI, from prefs and from the server.
    test('carries the pre-reboot total instead of wiping it', () {
      final b = baselineFor(
        raw: 5,
        lastRaw: 108000,
        baseline: 100000,
        todaySteps: 8000,
      );
      expect(b, -8000, reason: 'a negative baseline adds the two halves');
      expect(stepsFrom(5, b), 8005);
    });

    test('keeps accumulating on top after the rebase', () {
      // Second reading of the same boot: no longer lower than the last raw, so
      // the negative baseline just stays put.
      final b = baselineFor(
          raw: 900, lastRaw: 5, baseline: -8000,
          todaySteps: 8005);
      expect(b, -8000);
      expect(stepsFrom(900, b), 8900);
    });

    test('survives a second reboot on the same day', () {
      final b = baselineFor(
          raw: 3, lastRaw: 900, baseline: -8000,
          todaySteps: 8900);
      expect(stepsFrom(3, b), 8903);
    });

    // A reboot before any steps were logged today is still a reboot; it just
    // has nothing to carry.
    test('is a no-op when the day had no steps yet', () {
      final b = baselineFor(
          raw: 4, lastRaw: 50000, baseline: 50000);
      expect(stepsFrom(4, b), 4);
    });
  });

  group('new day', () {
    // The regression this group exists for. Yesterday's last raw reading was
    // taken whenever the app was last open — an evening walk sits between it
    // and midnight — so rebasing on it credited today with yesterday's
    // remainder. On a real device that read 1,149 steps at 07:49 against 54
    // actually taken.
    test('does not carry yesterdays post-close steps into today', () {
      final b = baselineFor(
        raw: 109200,
        lastRaw: 108000, // last seen yesterday evening, 1,200 steps ago
        lastSyncDate: yesterday,
        baseline: 100000,
        todaySteps: 8000,
      );
      expect(b, 109200);
      expect(stepsFrom(109200, b), 0,
          reason: 'the gap spans a midnight and cannot be split');
    });

    // Yesterday's reading belongs to a counter epoch that no longer exists, so
    // it could never have been subtracted from a two-digit one anyway.
    test('starts from the current value when the phone rebooted overnight', () {
      final b = baselineFor(
        raw: 300,
        lastRaw: 108000,
        lastSyncDate: yesterday,
        baseline: 100000,
        todaySteps: 8000,
      );
      expect(b, 300);
      expect(stepsFrom(300, b), 0, reason: 'never negative');
    });

    test('starts from the current value after a multi-day gap', () {
      final b = baselineFor(
        raw: 140000,
        lastRaw: 108000,
        lastSyncDate: '2026-08-04',
        baseline: 100000,
      );
      expect(b, 140000);
      expect(stepsFrom(140000, b), 0);
    });

    test('rebases on the current value with no history at all', () {
      final b = baselineFor(raw: 4200, lastSyncDate: '');
      expect(b, 4200);
      expect(stepsFrom(4200, b), 0);
    });
  });

  // Whatever happens, the figure handed to the UI and the database is never
  // negative and never silently resets a day that had real steps in it.
  group('invariants', () {
    test('never reports a negative count', () {
      for (final raw in [0, 1, 5, 900, 108000]) {
        for (final last in [null, 0, 5, 108000]) {
          for (final steps in [0, 8000]) {
            final b = baselineFor(
              raw: raw,
              lastRaw: last,
              baseline: 100000,
              todaySteps: steps,
            );
            expect(stepsFrom(raw, b), greaterThanOrEqualTo(0),
                reason: 'raw=$raw lastRaw=$last today=$steps');
          }
        }
      }
    });

    test('a mid-day reboot never loses steps already counted', () {
      for (final counted in [1, 500, 8000, 25000]) {
        final b = baselineFor(
          raw: 7,
          lastRaw: 99999,
          baseline: 90000,
          todaySteps: counted,
        );
        expect(stepsFrom(7, b), greaterThanOrEqualTo(counted));
      }
    });
  });
}
