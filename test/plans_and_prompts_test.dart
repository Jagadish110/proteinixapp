import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/utils/coach_nudge.dart';
import 'package:proteinix/models/daily_log.dart';
import 'package:proteinix/models/meal_slot.dart';
import 'package:proteinix/models/user_profile.dart';
import 'package:proteinix/services/notification_service.dart';
import 'package:proteinix/services/plan_limits.dart';
import 'package:proteinix/services/routine_logger.dart';
import 'package:proteinix/services/routine_service.dart';
import 'package:proteinix/services/subscription_service.dart';
import 'package:proteinix/services/welcome_back_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserProfile profile({
  int calories = 2000,
  double protein = 100,
  int water = 2500,
}) =>
    UserProfile(
      id: 'u1',
      calorieGoal: calories,
      proteinGoalG: protein,
      waterGoalMl: water,
    );

DailyLog log({int calories = 0, double protein = 0, int water = 0}) =>
    DailyLog(
      userId: 'u1',
      date: DateTime(2026, 11, 16),
      caloriesConsumed: calories,
      proteinG: protein,
      waterMl: water,
    );

SavedRoutine routine(String id, String name, {int calories = 300}) =>
    SavedRoutine(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      items: [
        RoutineItem(
          name: name,
          quantity: 1,
          unit: 'katori',
          calories: calories,
          proteinG: 10,
          carbsG: 30,
          fatG: 5,
          fiberG: 4,
        ),
      ],
    );

void main() {
  group('DailyCounter', () {
    test('reads the count written today', () {
      expect(DailyCounter.countFor('2026-11-16:2', '2026-11-16'), 2);
    });

    test('a count from another day reads as zero', () {
      expect(DailyCounter.countFor('2026-11-15:3', '2026-11-16'), 0);
    });

    test('missing or malformed storage reads as zero, never throws', () {
      expect(DailyCounter.countFor(null, '2026-11-16'), 0);
      expect(DailyCounter.countFor('', '2026-11-16'), 0);
      expect(DailyCounter.countFor('garbage', '2026-11-16'), 0);
      expect(DailyCounter.countFor('2026-11-16:x', '2026-11-16'), 0);
      expect(DailyCounter.countFor('2026-11-16:-4', '2026-11-16'), 0);
    });

    test('encode round-trips', () {
      final raw = DailyCounter.encode('2026-11-16', 3);
      expect(DailyCounter.countFor(raw, '2026-11-16'), 3);
    });
  });

  group('PlanLimits', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a free user starts the day with three scans', () async {
      expect(PlanLimits.freeScansPerDay, 3);
      expect(await PlanLimits.freeScansLeft(), 3);
    });

    test('each recorded scan uses one, and it never goes below zero',
        () async {
      await PlanLimits.recordScan();
      expect(await PlanLimits.freeScansLeft(), 2);
      await PlanLimits.recordScan();
      await PlanLimits.recordScan();
      expect(await PlanLimits.freeScansLeft(), 0);
      await PlanLimits.recordScan();
      expect(await PlanLimits.freeScansLeft(), 0);
    });

    test('the coach allows thirty messages a day', () async {
      expect(PlanLimits.coachMessagesPerDay, 30);
      for (var i = 0; i < 30; i++) {
        expect(await PlanLimits.coachMessagesLeft(), 30 - i);
        await PlanLimits.recordCoachMessage();
      }
      expect(await PlanLimits.coachMessagesLeft(), 0);
    });

    test('scans and coach messages are counted separately', () async {
      await PlanLimits.recordCoachMessage();
      expect(await PlanLimits.freeScansLeft(), 3);
      expect(await PlanLimits.coachMessagesLeft(), 29);
    });
  });

  group('CoachNudge', () {
    final evening = DateTime(2026, 11, 16, 20);
    final morning = DateTime(2026, 11, 16, 9);

    test('names the protein gap and what to eat for it', () {
      final n = CoachNudge.forToday(
          profile(), log(calories: 1400, protein: 74), evening);
      expect(n.kind, CoachNudgeKind.protein);
      expect(n.headline, '26g protein short');
      expect(n.body, startsWith('Eat this: '));
      expect(n.followUp, contains('26g'));
    });

    test('does not call the morning a shortfall', () {
      // 15g by 9am is on pace for a 100g day.
      final n = CoachNudge.forToday(
          profile(), log(calories: 350, protein: 15), morning);
      expect(n.kind, isNot(CoachNudgeKind.protein));
    });

    test('suggests lean protein when the calorie budget is nearly spent', () {
      final n = CoachNudge.forToday(
          profile(), log(calories: 1900, protein: 60), evening);
      expect(n.kind, CoachNudgeKind.protein);
      expect(n.body, contains('without many extra calories'));
    });

    test('an empty day asks for a first meal, not a 100g shortfall', () {
      final n = CoachNudge.forToday(profile(), null, evening);
      expect(n.kind, CoachNudgeKind.start);
      expect(n.body, contains('100g'));
    });

    test('over on calories with protein met', () {
      final n = CoachNudge.forToday(
          profile(), log(calories: 2300, protein: 110, water: 2500), evening);
      expect(n.kind, CoachNudgeKind.calories);
      expect(n.headline, '300 kcal over today');
    });

    test('behind on water when food is on track', () {
      final n = CoachNudge.forToday(
          profile(), log(calories: 1800, protein: 100, water: 500), evening);
      expect(n.kind, CoachNudgeKind.water);
    });

    test('everything met reads as a win', () {
      final n = CoachNudge.forToday(
          profile(), log(calories: 1900, protein: 105, water: 2600), evening);
      expect(n.kind, CoachNudgeKind.onTrack);
      expect(n.headline, 'Protein goal met');
    });

    test('bigger gaps get bigger suggestions', () {
      expect(CoachNudge.proteinFoods(6), contains('boiled egg'));
      expect(CoachNudge.proteinFoods(26), contains('chicken'));
      expect(CoachNudge.proteinFoods(6), isNot(CoachNudge.proteinFoods(60)));
    });

    test('expected fraction is floored early and capped late', () {
      expect(CoachNudge.expectedFraction(DateTime(2026, 1, 1, 5)), 0.15);
      expect(CoachNudge.expectedFraction(DateTime(2026, 1, 1, 14)), 0.5);
      expect(CoachNudge.expectedFraction(DateTime(2026, 1, 1, 23)), 1.0);
    });
  });

  group('WelcomeBackService', () {
    test('counts the full days missed in between', () {
      final monday = DateTime(2026, 11, 9);
      expect(WelcomeBackService.missedDays(monday, DateTime(2026, 11, 9)), 0);
      expect(WelcomeBackService.missedDays(monday, DateTime(2026, 11, 10)), 0);
      expect(WelcomeBackService.missedDays(monday, DateTime(2026, 11, 11)), 1);
      expect(WelcomeBackService.missedDays(monday, DateTime(2026, 11, 12)), 2);
    });

    test('a clock set backwards is not a negative gap', () {
      expect(
          WelcomeBackService.missedDays(
              DateTime(2026, 11, 12), DateTime(2026, 11, 9)),
          0);
    });

    test('a daylight-saving day is still one day', () {
      // 25-hour day in Europe; date-only arithmetic must not see a gap.
      expect(
          WelcomeBackService.missedDays(
              DateTime(2026, 10, 24), DateTime(2026, 10, 25)),
          0);
    });

    group('checkIn', () {
      setUp(() => SharedPreferences.setMockInitialValues({}));

      test('first ever open greets nobody', () async {
        expect(
            await WelcomeBackService.checkIn(now: DateTime(2026, 11, 9, 8)),
            0);
      });

      test('consecutive days greet nobody', () async {
        await WelcomeBackService.checkIn(now: DateTime(2026, 11, 9, 8));
        expect(
            await WelcomeBackService.checkIn(now: DateTime(2026, 11, 10, 8)),
            0);
      });

      test('returning after missed days greets, and keeps greeting that day',
          () async {
        await WelcomeBackService.checkIn(now: DateTime(2026, 11, 9, 8));
        expect(
            await WelcomeBackService.checkIn(now: DateTime(2026, 11, 13, 8)),
            3);
        // A second build of the dashboard the same day must not lose it.
        expect(
            await WelcomeBackService.checkIn(now: DateTime(2026, 11, 13, 19)),
            3);
      });

      test('dismissing ends it for the day, and the next day is normal',
          () async {
        await WelcomeBackService.checkIn(now: DateTime(2026, 11, 9, 8));
        await WelcomeBackService.checkIn(now: DateTime(2026, 11, 13, 8));
        await WelcomeBackService.dismiss();
        expect(
            await WelcomeBackService.checkIn(now: DateTime(2026, 11, 13, 19)),
            0);
        expect(
            await WelcomeBackService.checkIn(now: DateTime(2026, 11, 14, 8)),
            0);
      });
    });

    test('the message never mentions a streak', () {
      for (final days in [1, 3, 30]) {
        expect(WelcomeBackService.message(days).toLowerCase(),
            isNot(contains('streak')));
      }
    });
  });

  group('RoutineLogger', () {
    test('scales every macro and the quantity by the portion count', () {
      final half = RoutineLogger.scaled(routine('r', 'Rajma').items.first, 0.5);
      expect(half.quantity, 0.5);
      expect(half.calories, 150);
      expect(half.proteinG, 5);
      expect(half.carbsG, 15);
      expect(half.fatG, 2.5);
      expect(half.fiberG, 2);
      expect(half.unit, 'katori');
    });

    test('one portion is the dish exactly as saved', () {
      final r = routine('r', 'Rajma');
      expect(RoutineLogger.caloriesFor(r, 1), r.totalCalories);
      expect(RoutineLogger.caloriesFor(r, 2), r.totalCalories * 2);
    });

    test('portion labels read naturally', () {
      expect(RoutineLogger.portionLabel(0.5), '½');
      expect(RoutineLogger.portionLabel(1), '1');
      expect(RoutineLogger.portionLabel(1.5), '1½');
      expect(RoutineLogger.portionLabel(2), '2');
    });
  });

  group('RoutineUsage', () {
    const breakfast =
        MealSlot(key: 'breakfast', label: 'Breakfast', time: '08:00');
    const dinner = MealSlot(key: 'dinner', label: 'Dinner', time: '20:00');

    final routines = [
      routine('a', 'Idli sambar'),
      routine('b', 'Oats and eggs'),
      routine('c', 'My usual dinner'),
    ];

    test('the meal logged most often for a slot is the usual', () {
      final usage = RoutineUsage.empty
          .recorded('a', 'breakfast')
          .recorded('b', 'breakfast')
          .recorded('b', 'breakfast');
      expect(usage.usualFor(routines, breakfast)?.id, 'b');
    });

    test('history in one slot says nothing about another', () {
      final usage = RoutineUsage.empty.recorded('a', 'breakfast');
      expect(usage.usualFor([routines[0], routines[1]], dinner), isNull);
    });

    test('with no history, a routine named after the slot is used', () {
      expect(RoutineUsage.empty.usualFor(routines, dinner)?.id, 'c');
    });

    test('with no history and no matching name, nothing is suggested', () {
      expect(RoutineUsage.empty.usualFor(routines, breakfast), isNull);
    });

    test('survives a round trip through storage', () {
      final usage = RoutineUsage.empty
          .recorded('a', 'breakfast')
          .recorded('a', 'breakfast');
      final restored = RoutineUsage.decode(usage.encode());
      expect(restored.count('a', 'breakfast'), 2);
      expect(restored.count('a', 'dinner'), 0);
    });

    test('corrupt storage reads as empty', () {
      expect(RoutineUsage.decode('not json').count('a', 'breakfast'), 0);
      expect(RoutineUsage.decode(null).count('a', 'breakfast'), 0);
    });
  });

  group('trial', () {
    test('period lengths convert to days', () {
      expect(SubscriptionService.periodDays(PeriodUnit.day, 7), 7);
      expect(SubscriptionService.periodDays(PeriodUnit.week, 1), 7);
      expect(SubscriptionService.periodDays(PeriodUnit.month, 1), 30);
      expect(SubscriptionService.periodDays(PeriodUnit.unknown, 5), 0);
    });

    test('reminder goes out at least two days before the trial ends', () {
      final start = DateTime(2026, 11, 16, 21, 30);
      final end = start.add(const Duration(days: 7));
      final when = NotificationService.trialReminderTime(end, start)!;

      expect(end.difference(when) >= NotificationService.trialReminderLead,
          isTrue);
      expect(when.isAfter(start), isTrue);
      expect(when.hour, 10);
    });

    test('a trial started in the small hours still gets a daytime reminder',
        () {
      final start = DateTime(2026, 11, 16, 3);
      final end = start.add(const Duration(days: 7));
      final when = NotificationService.trialReminderTime(end, start)!;
      expect(when.hour, 10);
      expect(end.difference(when) >= NotificationService.trialReminderLead,
          isTrue);
    });

    test('with under two days left the reminder comes within the hour', () {
      final now = DateTime(2026, 11, 16, 12);
      final end = now.add(const Duration(hours: 30));
      final when = NotificationService.trialReminderTime(end, now)!;
      expect(when, now.add(const Duration(hours: 1)));
    });

    test('nothing is scheduled for a trial that is already over', () {
      final now = DateTime(2026, 11, 16, 12);
      expect(
          NotificationService.trialReminderTime(
              now.subtract(const Duration(hours: 1)), now),
          isNull);
    });
  });
}
