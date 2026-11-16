import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/utils/food_icon_resolver.dart';

void main() {
  void expectsIcon(String foodName, FoodCategory expected) {
    test('"$foodName" resolves to ${expected.name}', () {
      expect(FoodIconResolver.resolve(foodName), expected);
    });
  }

  group('quick-add suggestions', () {
    expectsIcon('Greek Yogurt with Berries', FoodCategory.yogurt);
    expectsIcon('Boiled Eggs (2)', FoodCategory.egg);
    expectsIcon('Chapati (2)', FoodCategory.flatbread);
    expectsIcon('Dal (1 katori)', FoodCategory.dal);
    expectsIcon('Paneer Bhurji', FoodCategory.paneer);
    expectsIcon('Chicken Breast (grilled, 150g)', FoodCategory.chicken);
    expectsIcon('Plain Rice (1 cup)', FoodCategory.rice);
    expectsIcon('Banana (medium)', FoodCategory.banana);
    expectsIcon('Masala Oats', FoodCategory.oats);
    expectsIcon('Sprouts Salad', FoodCategory.dal);
    expectsIcon('Idli (3)', FoodCategory.steamedCake);
    expectsIcon('Curd (1 bowl)', FoodCategory.yogurt);
  });

  group('composite dishes beat their ingredients', () {
    expectsIcon('Chicken Biryani', FoodCategory.rice);
    expectsIcon('Egg Fried Rice', FoodCategory.rice);
    expectsIcon('Paneer Tikka Masala', FoodCategory.paneer);
    expectsIcon('Palak Paneer', FoodCategory.paneer);
    expectsIcon('Mixed Veg Curry', FoodCategory.curry);
    expectsIcon('Chicken Soup', FoodCategory.soup);
    expectsIcon('Peanut Butter Toast', FoodCategory.nuts);
    expectsIcon('Protein Shake', FoodCategory.proteinShake);
    expectsIcon('Aloo Paratha', FoodCategory.flatbread);
    expectsIcon('Cheese Pizza', FoodCategory.pizza);
  });

  group('plurals and punctuation', () {
    expectsIcon('eggs', FoodCategory.egg);
    expectsIcon('2 ROTIS', FoodCategory.flatbread);
    expectsIcon('almonds, 10 pcs', FoodCategory.nuts);
    expectsIcon('mixed berries', FoodCategory.berries);
    expectsIcon('french fries', FoodCategory.friedSnack);
  });

  group('no false positives on substrings', () {
    // "oil" must not fire inside "boiled", nor "tea" inside "steak".
    expectsIcon('Boiled Potato', FoodCategory.potato);
    expectsIcon('Grilled Steak', FoodCategory.redMeat);
  });

  // Counted snacks are what the AI returns for "4 almonds, cashew and dates",
  // one entry per food. Each has to find its own icon rather than falling
  // through to the generic plate.
  group('counted nuts and dried fruit', () {
    expectsIcon('Almonds', FoodCategory.nuts);
    expectsIcon('4 Almonds', FoodCategory.nuts);
    expectsIcon('Cashews', FoodCategory.nuts);
    expectsIcon('Dates', FoodCategory.fruit);
    expectsIcon('Dates (2 pieces)', FoodCategory.fruit);
    expectsIcon('Walnut halves', FoodCategory.nuts);
    expectsIcon('Makhana', FoodCategory.nuts);
  });

  // Users type these far more often than the English names.
  group('Indian names for nuts and dried fruit', () {
    expectsIcon('Badam', FoodCategory.nuts);
    expectsIcon('Kaju', FoodCategory.nuts);
    expectsIcon('Akhrot', FoodCategory.nuts);
    expectsIcon('Khajoor', FoodCategory.fruit);
    expectsIcon('Anjeer', FoodCategory.fruit);
    expectsIcon('Kishmish', FoodCategory.fruit);
  });

  group('dry fruits reads as nuts, not produce', () {
    // The Indian term for a nut-and-dried-fruit mix. It contains the token
    // "fruit", so it only lands here because its rule precedes the bare
    // 'fruit' rule — this test is what keeps that ordering honest.
    expectsIcon('Dry Fruits', FoodCategory.nuts);
    expectsIcon('Dried Fruit Mix', FoodCategory.nuts);
    // And the plain word must still be produce.
    expectsIcon('Mixed Fruit Bowl', FoodCategory.fruit);
  });

  group('coconut splits by form', () {
    // Adding 'coconut' to the nuts block silently shadowed the drink, which
    // the catalog test caught. Both directions are pinned here now.
    expectsIcon('Coconut Water', FoodCategory.water);
    expectsIcon('Nariyal Pani', FoodCategory.water);
    expectsIcon('Coconut', FoodCategory.nuts);
    expectsIcon('Nariyal', FoodCategory.nuts);
  });

  test('unknown food falls back to other', () {
    expect(FoodIconResolver.resolve('zzz mystery item'), FoodCategory.other);
  });

  test('empty name falls back to other', () {
    expect(FoodIconResolver.resolve(''), FoodCategory.other);
  });

  test('every category has a style', () {
    for (final category in FoodCategory.values) {
      expect(() => category.icon, returnsNormally, reason: category.name);
      expect(() => category.tint, returnsNormally, reason: category.name);
    }
  });
}
