import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/models/local/local_meal_routine.dart';
import 'package:proteinix/services/local_db_service.dart';
import 'package:proteinix/services/routine_service.dart';

const _uuidLike =
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

RoutineItem item({String name = 'Brown rice'}) => RoutineItem(
      name: name,
      quantity: 150,
      unit: 'g',
      calories: 200,
      proteinG: 4.5,
      carbsG: 44,
      fatG: 0.5,
      fiberG: 1.2,
    );

void main() {
  group('RoutineItem', () {
    test('round-trips through JSON with no field loss', () {
      final original = item();
      final restored = RoutineItem.fromJson(original.toJson());

      expect(restored.name, original.name);
      expect(restored.quantity, original.quantity);
      expect(restored.unit, original.unit);
      expect(restored.calories, original.calories);
      expect(restored.proteinG, original.proteinG);
      expect(restored.carbsG, original.carbsG);
      expect(restored.fatG, original.fatG);
      expect(restored.fiberG, original.fiberG);
    });
  });

  group('SavedRoutine', () {
    test('round-trips through JSON, including every item', () {
      final original = SavedRoutine(
        id: 'r1',
        name: 'Breakfast bowl',
        items: [item(name: 'Oats'), item(name: 'Banana')],
        createdAt: DateTime.utc(2026, 8, 14, 9, 0),
      );
      final restored = SavedRoutine.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.items.map((i) => i.name), ['Oats', 'Banana']);
      expect(restored.createdAt, original.createdAt);
    });

    test('totals sum every item, not just the first', () {
      final routine = SavedRoutine(
        id: 'r1',
        name: 'Two eggs and rice',
        items: [item(), item()],
        createdAt: DateTime.now(),
      );
      expect(routine.totalCalories, 400);
      expect(routine.totalProtein, closeTo(9.0, 0.001));
    });
  });

  group('LocalMealRoutine', () {
    // This is the bug the rewrite fixes: the old id was
    // DateTime.now().millisecondsSinceEpoch.toString(), which is not a valid
    // uuid and would have failed the first insert into a `uuid` primary key
    // column the moment routines started reaching Supabase at all.
    test('newId always produces a real v4 UUID', () {
      for (var i = 0; i < 20; i++) {
        expect(LocalDBService.newId(), matches(RegExp(_uuidLike)));
      }
    });

    test('toRow decodes items back into a List for the jsonb column', () {
      final local = LocalMealRoutine(
        id: 'a1b2',
        userId: 'user-1',
        name: 'Lunch',
        itemsJson: '[{"name":"Rice","quantity":150,"unit":"g",'
            '"calories":200,"protein_g":4.5,"carbs_g":44,'
            '"fat_g":0.5,"fiber_g":1.2}]',
        createdAt: DateTime.utc(2026, 8, 14),
      );
      final row = local.toRow();

      expect(row['id'], 'a1b2');
      expect(row['user_id'], 'user-1');
      // Not a string — Supabase's jsonb column wants an actual List/Map, and
      // sending it JSON-encoded twice would store a string inside the column
      // instead of structured data.
      expect(row['items'], isA<List>());
      expect((row['items'] as List).single['name'], 'Rice');
    });

    test('fromRow re-encodes Supabase\'s already-decoded jsonb', () {
      final row = {
        'id': 'a1b2',
        'user_id': 'user-1',
        'name': 'Lunch',
        // Supabase hands back jsonb as a decoded List<Map>, not a String —
        // this is what a real response looks like.
        'items': [
          {
            'name': 'Rice',
            'quantity': 150,
            'unit': 'g',
            'calories': 200,
            'protein_g': 4.5,
            'carbs_g': 44.0,
            'fat_g': 0.5,
            'fiber_g': 1.2,
          }
        ],
        'created_at': '2026-08-14T00:00:00Z',
      };
      final local = LocalMealRoutine.fromRow(row);

      expect(local.itemsJson, contains('"name":"Rice"'));
      expect(local.isSynced, isTrue,
          reason: 'a row pulled from the server is already synced');
    });

    test('fromRow survives a missing items column', () {
      final local = LocalMealRoutine.fromRow({
        'id': 'a1b2',
        'user_id': 'user-1',
        'name': 'Empty',
        'created_at': '2026-08-14T00:00:00Z',
      });
      expect(local.itemsJson, '[]');
    });
  });
}
