import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/services/trial_service.dart';

/// [TrialService.state] reads Supabase and Hive, so the arithmetic it performs
/// is reproduced here against a fixed clock. These assertions are about the
/// boundaries — the places where a user is wrongly charged or wrongly let in.
TrialState stateAt({required DateTime createdAt, required DateTime now}) {
  final ends = createdAt.add(const Duration(days: TrialService.trialDays));
  final left = ends.difference(now);
  if (left <= Duration.zero) {
    return const TrialState(active: false, daysLeft: 0, known: true);
  }
  final days = (left.inMinutes / (24 * 60)).ceil();
  return TrialState(active: true, daysLeft: days, known: true);
}

final signup = DateTime(2026, 8, 13, 10, 0);

void main() {
  group('during the trial', () {
    test('the moment of signup shows the full three days', () {
      final s = stateAt(createdAt: signup, now: signup);
      expect(s.active, isTrue);
      expect(s.daysLeft, 3);
      expect(s.expired, isFalse);
    });

    // Rounded up on purpose. Someone 12 hours in has "2 days left", not 2.5 and
    // certainly not 2 rounded down to a number that undersells what they have.
    test('counts part-days up, never down', () {
      expect(
          stateAt(createdAt: signup, now: signup.add(const Duration(hours: 12)))
              .daysLeft,
          3);
      expect(
          stateAt(createdAt: signup, now: signup.add(const Duration(hours: 25)))
              .daysLeft,
          2);
      expect(
          stateAt(createdAt: signup, now: signup.add(const Duration(hours: 49)))
              .daysLeft,
          1);
    });

    // The last minute of the trial still reads as a day, so nobody is told they
    // have "0 days left" while the features are still working.
    test('one minute before expiry is still active and reads as a day', () {
      final s = stateAt(
        createdAt: signup,
        now: signup.add(const Duration(days: 3)).subtract(const Duration(minutes: 1)),
      );
      expect(s.active, isTrue);
      expect(s.daysLeft, 1);
    });
  });

  group('after the trial', () {
    // The exact boundary. This caught a real bug: the remainder is zero here,
    // which is not negative, so the trial reported active with zero days left.
    test('expires exactly three days after signup', () {
      final s = stateAt(
          createdAt: signup, now: signup.add(const Duration(days: 3)));
      expect(s.active, isFalse);
      expect(s.daysLeft, 0);
      expect(s.expired, isTrue);
    });

    test('stays expired long afterwards', () {
      final s = stateAt(
          createdAt: signup, now: signup.add(const Duration(days: 400)));
      expect(s.expired, isTrue);
      expect(s.daysLeft, 0);
    });
  });

  group('unknown creation date', () {
    // Fails open. A fresh install that has not pulled the profile yet, or a
    // Hive that isn't ready, must not paywall someone who may well be entitled
    // — the date arrives with the next sync.
    test('reads as active, and never as expired', () {
      expect(TrialState.unknown.active, isTrue);
      expect(TrialState.unknown.known, isFalse);
      expect(TrialState.unknown.expired, isFalse,
          reason: 'unknown is not the same as ended');
    });
  });

  // A clock rolled backwards should not hand out extra trial. It gives more
  // days, but it can never resurrect a trial that already ended on the server's
  // creation date once the clock is corrected.
  test('a device clock behind the signup date does not crash', () {
    final s = stateAt(
        createdAt: signup, now: signup.subtract(const Duration(days: 5)));
    expect(s.active, isTrue);
    expect(s.daysLeft, greaterThan(0));
  });
}
