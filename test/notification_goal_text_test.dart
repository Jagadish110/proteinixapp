import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/services/notification_service.dart';

/// Reminder and alert wording has to quote the target the user set in Profile.
///
/// It didn't: `NotificationSettings.waterGoalMl` defaulted to 2500 and nothing
/// ever assigned it, so every hydration reminder read "2.5L goal" no matter
/// what the profile said — and the step, protein and calorie alerts named no
/// figure at all. Nothing failed when that broke, which is what these are for.
void main() {
  group('water reminder', () {
    test('quotes the profile target, not the 2.5L default', () {
      final body =
          NotificationService.waterReminderBody(goalMl: 4000, shortfallMl: 900);
      expect(body, contains('4.0L'));
      expect(body, contains('900ml'));
      expect(body, isNot(contains('2.5L')));
    });

    test('stays generic when today\'s total cannot be read', () {
      final body = NotificationService.waterReminderBody(
          goalMl: 4000, shortfallMl: null);
      expect(body, contains('4.0L'));
      // No figure is invented for the part that isn't known.
      expect(body, isNot(contains('left')));
    });

    test('congratulates on the target once it is met', () {
      final body =
          NotificationService.waterReminderBody(goalMl: 3000, shortfallMl: 0);
      expect(body, contains('3.0L'));
      expect(body, isNot(contains('left')));
    });

    // Sub-litre targets are real — "0.8L" reads worse than "800ml".
    test('uses ml below a litre', () {
      expect(
        NotificationService.waterReminderBody(goalMl: 800, shortfallMl: null),
        contains('800ml'),
      );
    });
  });

  group('step reminder', () {
    test('quotes the profile target in both slots', () {
      for (final evening in [false, true]) {
        expect(NotificationService.stepReminderBody(7500, evening: evening),
            contains('7,500'));
      }
    });

    // The two slots are different times of day and must not read identically.
    test('the midday and evening wordings differ', () {
      expect(
        NotificationService.stepReminderBody(10000, evening: false),
        isNot(NotificationService.stepReminderBody(10000, evening: true)),
      );
    });
  });

  group('goal alerts', () {
    test('water names the target', () {
      expect(GoalAlerts.waterBody(4000), contains('4.0L'));
    });

    test('steps names the target with a thousands separator', () {
      expect(GoalAlerts.stepsBody(12000), contains('12,000'));
    });

    test('protein names the target without a trailing .0', () {
      expect(GoalAlerts.proteinBody(120), contains('120g'));
      expect(GoalAlerts.proteinBody(120), isNot(contains('120.0')));
    });

    test('protein keeps a real fraction', () {
      expect(GoalAlerts.proteinBody(122.5), contains('122.5g'));
    });

    test('calories names the target', () {
      expect(GoalAlerts.caloriesBody(3060), contains('3,060'));
    });

    // Every one of these was a fixed string that named no number at all.
    test('none of them is goal-independent', () {
      expect(GoalAlerts.waterBody(2500), isNot(GoalAlerts.waterBody(4000)));
      expect(GoalAlerts.stepsBody(10000), isNot(GoalAlerts.stepsBody(12000)));
      expect(GoalAlerts.proteinBody(150), isNot(GoalAlerts.proteinBody(120)));
      expect(
          GoalAlerts.caloriesBody(2000), isNot(GoalAlerts.caloriesBody(3060)));
    });
  });

  group('settings carry the goals through the notification screen', () {
    // The screen edits its loaded settings with copyWith. If a goal were
    // dropped there it would silently fall back to the default again.
    test('copyWith preserves goals it was not asked to change', () {
      const s = NotificationSettings(
        waterEnabled: true,
        waterIntervalHours: 2,
        waterStartTime: '08:00',
        waterEndTime: '22:00',
        waterGoalMl: 4000,
        stepsGoal: 7500,
        mealEnabled: true,
        mealTimes: ['08:00'],
        mealLabels: ['Breakfast'],
      );
      final next = s.copyWith(waterIntervalHours: 3, stepEnabled: true);
      expect(next.waterGoalMl, 4000);
      expect(next.stepsGoal, 7500);
    });
  });
}
