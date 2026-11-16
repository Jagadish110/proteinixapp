import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/models/sleep_result.dart';

SleepResult night({
  double hours = 7.5,
  int interruptions = 0,
  int pickups = 0,
  DateTime? start,
  DateTime? end,
}) =>
    SleepResult(
      sleepHours: hours,
      interruptions: interruptions,
      phonePickups: pickups,
      date: DateTime(2026, 8, 11),
      sleepStart: start,
      sleepEnd: end,
    );

void main() {
  group('sleepScore', () {
    test('a full undisturbed night scores 100', () {
      expect(night(hours: 8, interruptions: 0).sleepScore, 100);
    });

    test('duration bands step down as sleep gets shorter', () {
      int score(double h) => night(hours: h, interruptions: 0).sleepScore;
      // 30 of every score below is the interruption half, held constant.
      expect(score(8), 100); // 70 + 30
      expect(score(6.5), 85); // 55 + 30
      expect(score(5.5), 70); // 40 + 30
      expect(score(3), 55); // 25 + 30
    });

    // Oversleeping is not better than sleeping well. A score that kept rising
    // would congratulate someone on eleven hours.
    test('over nine hours scores below the 7-9 band', () {
      expect(night(hours: 11).sleepScore, lessThan(night(hours: 8).sleepScore));
      expect(night(hours: 11).sleepScore, 90); // 60 + 30
    });

    test('the band edges are inclusive of 7 and 9', () {
      expect(night(hours: 7).sleepScore, 100);
      expect(night(hours: 9).sleepScore, 100);
      expect(night(hours: 9.5).sleepScore, 90);
    });

    test('interruptions cost progressively more', () {
      int score(int i) => night(hours: 8, interruptions: i).sleepScore;
      expect(score(0), 100);
      expect(score(1), 95);
      expect(score(2), 88);
      expect(score(3), 80);
      expect(score(9), 75);
    });

    test('never leaves 0-100', () {
      for (final h in [0.0, 0.5, 4.0, 8.0, 24.0]) {
        for (final i in [0, 1, 5, 50]) {
          final s = night(hours: h, interruptions: i).sleepScore;
          expect(s, inInclusiveRange(0, 100), reason: 'h=$h i=$i');
        }
      }
    });
  });

  group('labels', () {
    test('duration reads as hours and padded minutes', () {
      expect(night(hours: 7.2).durationLabel, '7h 12m');
      expect(night(hours: 6.05).durationLabel, '6h 03m');
    });

    test('score label tracks the score', () {
      expect(night(hours: 8, interruptions: 0).scoreLabel, 'Excellent');
      expect(night(hours: 6.5, interruptions: 2).scoreLabel, 'Good'); // 73
      expect(night(hours: 5.5, interruptions: 1).scoreLabel, 'Fair'); // 65
      expect(night(hours: 3, interruptions: 5).scoreLabel, 'Poor');
    });
  });

  group('timeAwake', () {
    // The span is bed-to-rise; the hours are only the dark parts of it. What
    // is left is the time spent awake in between.
    test('is the observed span minus the time asleep', () {
      final result = night(
        hours: 6,
        start: DateTime(2026, 8, 11, 23, 0),
        end: DateTime(2026, 8, 12, 6, 0),
      );
      expect(result.timeAwake, const Duration(hours: 1));
    });

    test('is null when the span was never recorded', () {
      expect(night(hours: 6).timeAwake, isNull);
    });

    // Health Connect can report more sleep than the sampler saw a span for,
    // which would otherwise produce a negative stretch of wakefulness.
    test('never goes negative', () {
      final result = night(
        hours: 9,
        start: DateTime(2026, 8, 11, 23, 0),
        end: DateTime(2026, 8, 12, 6, 0),
      );
      expect(result.timeAwake, Duration.zero);
    });
  });

  group('serialisation', () {
    test('round-trips through a map', () {
      final original = night(
        hours: 7.25,
        interruptions: 2,
        pickups: 4,
        start: DateTime(2026, 8, 11, 23, 30),
        end: DateTime(2026, 8, 12, 7, 0),
      );
      final restored = SleepResult.fromMap({
        ...original.toMap(),
        // toMap writes the storage column name; fromMap reads the native one.
        'interruptions': original.interruptions,
      });

      expect(restored.sleepHours, original.sleepHours);
      expect(restored.interruptions, original.interruptions);
      expect(restored.phonePickups, original.phonePickups);
      expect(restored.sleepStart, original.sleepStart);
      expect(restored.sleepEnd, original.sleepEnd);
      expect(restored.sleepScore, original.sleepScore);
    });

    test('reads epoch millis as well as ISO strings', () {
      final at = DateTime(2026, 8, 11, 23, 30);
      final restored = SleepResult.fromMap({
        'sleep_hours': 7.0,
        'interruptions': 0,
        'phone_pickups': 0,
        'date': '2026-08-12',
        'sleep_start': at.millisecondsSinceEpoch,
        'sleep_end': 0,
      });

      expect(restored.sleepStart, at);
      expect(restored.sleepEnd, isNull, reason: '0 means absent');
    });

    test('survives a map with nothing in it', () {
      final empty = SleepResult.fromMap(const {});
      expect(empty.sleepHours, 0);
      expect(empty.sleepScore, 55, reason: '25 for duration + 30 for no wakes');
    });
  });
}
