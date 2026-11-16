import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/models/meal_slot.dart';
import 'package:proteinix/services/meal_schedule_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('load', () {
    test('falls back to the four built-ins on a fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await MealScheduleService.load(), MealScheduleService.defaults);
    });

    // Installs predating the key array stored slots positionally.
    test('migrates legacy label/time arrays to canonical keys', () async {
      SharedPreferences.setMockInitialValues({
        'notif_meal_labels':
            jsonEncode(['Breakfast', 'Lunch', 'Dinner', 'Tea']),
        'notif_meal_times': jsonEncode(['07:30', '13:00', '20:00', '17:00']),
      });

      final slots = await MealScheduleService.load();
      expect([for (final s in slots) s.key],
          ['breakfast', 'lunch', 'dinner', 'snack']);
      // A renamed fourth slot keeps the 'snack' key so old rows still match.
      expect(slots.last.label, 'Tea');
      expect(slots.first.time, '07:30');
    });

    test('a legacy fifth slot gets a generated key', () async {
      SharedPreferences.setMockInitialValues({
        'notif_meal_labels':
            jsonEncode(['Breakfast', 'Lunch', 'Dinner', 'Snack', 'Supper']),
        'notif_meal_times':
            jsonEncode(['08:00', '13:00', '19:00', '16:00', '22:00']),
      });
      final slots = await MealScheduleService.load();
      expect(slots.last.key, 'meal_4');
    });

    test('survives corrupt json', () async {
      SharedPreferences.setMockInitialValues({
        'notif_meal_labels': 'not json',
        'notif_meal_times': 'not json',
      });
      expect(await MealScheduleService.load(), MealScheduleService.defaults);
    });
  });

  group('save', () {
    test('round-trips keys, labels and times', () async {
      SharedPreferences.setMockInitialValues({});
      const slots = [
        MealSlot(key: 'breakfast', label: 'Early bite', time: '06:15'),
        MealSlot(key: 'meal_7', label: 'Pre-workout', time: '17:00'),
      ];
      await MealScheduleService.save(slots);
      expect(await MealScheduleService.load(), slots);
    });

    // The regression the key array exists to prevent: without it, removing a
    // middle slot shifts every later slot's identity by one.
    test('removing a middle slot leaves later keys intact', () async {
      SharedPreferences.setMockInitialValues({});
      await MealScheduleService.save(MealScheduleService.defaults);

      final trimmed = List<MealSlot>.from(MealScheduleService.defaults)
        ..removeAt(1); // drop lunch
      await MealScheduleService.save(trimmed);

      final slots = await MealScheduleService.load();
      expect([for (final s in slots) s.key], ['breakfast', 'dinner', 'snack']);
      expect(slots[1].label, 'Dinner', reason: 'dinner must not become lunch');
    });
  });

  group('newKey', () {
    test('never collides with an existing key', () {
      const existing = [
        MealSlot(key: 'breakfast', label: 'B', time: '08:00'),
        MealSlot(key: 'meal_1', label: 'X', time: '10:00'),
      ];
      final key = MealScheduleService.newKey(existing);
      expect(existing.any((s) => s.key == key), isFalse);
    });
  });

  group('labelFor', () {
    const slots = [MealSlot(key: 'breakfast', label: 'Early bite', time: '07:00')];

    test('resolves a known key to its label', () {
      expect(MealScheduleService.labelFor(slots, 'breakfast'), 'Early bite');
    });

    // Meals logged before a slot was deleted must still render a name.
    test('falls back to a readable name for an orphaned key', () {
      expect(MealScheduleService.labelFor(slots, 'dinner'), 'Dinner');
      expect(MealScheduleService.labelFor(slots, 'meal_4'), 'Meal 4');
    });
  });

  group('currentKey', () {
    const slots = [
      MealSlot(key: 'breakfast', label: 'Breakfast', time: '08:00'),
      MealSlot(key: 'lunch', label: 'Lunch', time: '13:00'),
      MealSlot(key: 'dinner', label: 'Dinner', time: '21:30'),
    ];

    test('picks the most recent slot whose time has passed', () {
      expect(
          MealScheduleService.currentKey(slots, DateTime(2026, 1, 1, 14)), 'lunch');
      expect(MealScheduleService.currentKey(slots, DateTime(2026, 1, 1, 22)),
          'dinner');
    });

    // A late dinner should not leave the picker on lunch at 21:45.
    test('honours a custom schedule rather than fixed clock hours', () {
      expect(MealScheduleService.currentKey(slots, DateTime(2026, 1, 1, 21, 45)),
          'dinner');
      expect(MealScheduleService.currentKey(slots, DateTime(2026, 1, 1, 20, 0)),
          'lunch');
    });

    test('before the first slot, falls to the earliest', () {
      expect(MealScheduleService.currentKey(slots, DateTime(2026, 1, 1, 5)),
          'breakfast');
    });

    test('handles an empty schedule', () {
      expect(MealScheduleService.currentKey(const [], DateTime(2026, 1, 1, 12)),
          'breakfast');
    });
  });
}
