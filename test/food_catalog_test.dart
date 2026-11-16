import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/utils/food_icon_resolver.dart';
import 'fixtures/terra_food_catalog.dart';

/// The catalog's cuisine groups are not food types, so only the four that do
/// imply one are checked — the rest just have to resolve to something.
const _families = {
  'Fruits': {
    FoodCategory.apple,
    FoodCategory.banana,
    FoodCategory.citrus,
    FoodCategory.berries,
    FoodCategory.tropicalFruit,
    FoodCategory.fruit,
  },
  'Vegetables': {
    FoodCategory.salad,
    FoodCategory.vegetable,
    FoodCategory.potato,
    FoodCategory.avocado,
  },
  'Drinks': {
    FoodCategory.water,
    FoodCategory.tea,
    FoodCategory.coffee,
    FoodCategory.juice,
    FoodCategory.soda,
    FoodCategory.milk,
    FoodCategory.proteinShake,
  },
  'Protein': {
    FoodCategory.egg,
    FoodCategory.chicken,
    FoodCategory.redMeat,
    FoodCategory.fish,
    FoodCategory.sushi,
    FoodCategory.paneer,
    FoodCategory.proteinShake,
  },
};

void main() {
  test('every catalog item resolves to a real category', () {
    final misses = [
      for (final (group, name) in terraFoodCatalog)
        if (FoodIconResolver.resolve(name) == FoodCategory.other) '$group / $name',
    ];
    expect(misses, isEmpty, reason: '${misses.length} unmapped foods');
  });

  test('items land in the family their catalog group implies', () {
    final wrong = <String>[];
    for (final (group, name) in terraFoodCatalog) {
      final family = _families[group];
      if (family == null) continue;
      final category = FoodIconResolver.resolve(name);
      if (!family.contains(category)) {
        wrong.add('$group / $name -> ${category.name}');
      }
    }
    expect(wrong, isEmpty);
  });

  group('orderings the catalog exposed', () {
    void expectsIcon(String name, FoodCategory expected) {
      test('"$name" resolves to ${expected.name}', () {
        expect(FoodIconResolver.resolve(name), expected);
      });
    }

    // Drinks sit ahead of produce in the rule list.
    expectsIcon('Green Tea', FoodCategory.tea);
    expectsIcon('Orange Juice', FoodCategory.juice);
    // ...but a whole-token match keeps 'water' out of "watermelon".
    expectsIcon('Watermelon', FoodCategory.tropicalFruit);
    // Composite names ahead of the ingredient they contain.
    expectsIcon('Rice Cakes', FoodCategory.rice);
    expectsIcon('Mac and Cheese', FoodCategory.pasta);
    expectsIcon('Pani Puri', FoodCategory.friedSnack);
    expectsIcon('Curd Rice', FoodCategory.rice);
    // "-ies" plurals need their own spelling; stemming only drops a final "s".
    expectsIcon('Blueberries', FoodCategory.berries);
    expectsIcon('Strawberries', FoodCategory.berries);
  });
}
