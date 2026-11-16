import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'food_photo_catalog.dart';

/// Visual family a logged food maps to. One entry per icon we ship — many food
/// names collapse into each.
enum FoodCategory {
  // Grains & staples
  rice,
  flatbread,
  bread,
  oats,
  pasta,
  noodles,
  steamedCake, // idli, dhokla, appam
  crepe, // dosa, chilla, pancake
  // Legumes & gravies
  dal,
  curry,
  soup,
  // Protein
  paneer,
  egg,
  chicken,
  redMeat,
  fish,
  sushi,
  proteinShake,
  proteinBar,
  // Dairy
  yogurt,
  milk,
  cheese,
  // Fruit
  banana,
  apple,
  citrus,
  berries,
  tropicalFruit,
  fruit,
  // Vegetables
  salad,
  vegetable,
  potato,
  avocado,
  nuts,
  // Prepared / indulgent
  friedSnack,
  sweet,
  pizza,
  burger,
  sandwich,
  // Drinks
  coffee,
  tea,
  juice,
  water,
  soda,
  // Nothing matched
  other,
}

/// Maps a free-text food name onto a [FoodCategory] so every log path — quick
/// add, search, voice and camera scan — renders the same icon for the same
/// food, without needing anything stored on the meal row.
class FoodIconResolver {
  const FoodIconResolver._();

  /// First match wins. Ordering is deliberate: composite dishes are listed
  /// ahead of their ingredients so "chicken biryani" reads as rice and
  /// "masala oats" as oats rather than curry.
  static const List<(String, FoodCategory)> _rules = [
    // ── Supplements (ahead of 'shake' and 'butter') ────────────────────────
    ('protein shake', FoodCategory.proteinShake),
    ('protein powder', FoodCategory.proteinShake),
    ('whey', FoodCategory.proteinShake),
    ('mass gainer', FoodCategory.proteinShake),
    ('scoop', FoodCategory.proteinShake),
    ('protein bar', FoodCategory.proteinBar),
    ('energy bar', FoodCategory.proteinBar),
    ('granola bar', FoodCategory.proteinBar),
    ('peanut butter', FoodCategory.nuts),
    ('almond butter', FoodCategory.nuts),

    // ── Composite rice dishes (ahead of chicken / vegetable / sweet) ───────
    ('biryani', FoodCategory.rice),
    ('pulao', FoodCategory.rice),
    ('pilaf', FoodCategory.rice),
    ('fried rice', FoodCategory.rice),
    ('khichdi', FoodCategory.rice),
    ('risotto', FoodCategory.rice),
    ('onigiri', FoodCategory.rice),
    ('bibimbap', FoodCategory.rice),
    ('tteokbokki', FoodCategory.rice),
    ('rice cake', FoodCategory.rice), // ahead of 'cake' in the sweets block

    // ── Fast food (ahead of bread / cheese / meat) ─────────────────────────
    ('pizza', FoodCategory.pizza),
    ('cheeseburger', FoodCategory.burger),
    ('burger', FoodCategory.burger),
    ('hot dog', FoodCategory.burger),
    ('sandwich', FoodCategory.sandwich),
    ('wrap', FoodCategory.sandwich),
    ('shawarma', FoodCategory.sandwich),
    ('frankie', FoodCategory.sandwich),
    ('taco', FoodCategory.sandwich),
    ('burrito', FoodCategory.sandwich),
    ('quesadilla', FoodCategory.sandwich),
    ('enchilada', FoodCategory.sandwich),
    ('momo', FoodCategory.steamedCake),
    ('dumpling', FoodCategory.steamedCake),

    // ── South Indian & griddle ─────────────────────────────────────────────
    ('idli', FoodCategory.steamedCake),
    ('dhokla', FoodCategory.steamedCake),
    ('appam', FoodCategory.steamedCake),
    ('puttu', FoodCategory.steamedCake),
    ('dosa', FoodCategory.crepe),
    ('uttapam', FoodCategory.crepe),
    ('chilla', FoodCategory.crepe),
    ('cheela', FoodCategory.crepe),
    ('pancake', FoodCategory.crepe),
    ('crepe', FoodCategory.crepe),
    ('waffle', FoodCategory.crepe),
    ('upma', FoodCategory.oats),
    ('poha', FoodCategory.rice),
    ('pav bhaji', FoodCategory.curry),

    // ── Fried snacks (ahead of potato / vegetable / flatbread) ─────────────
    ('samosa', FoodCategory.friedSnack),
    ('pakora', FoodCategory.friedSnack),
    ('pakoda', FoodCategory.friedSnack),
    ('vada', FoodCategory.friedSnack),
    ('kachori', FoodCategory.friedSnack),
    ('pani puri', FoodCategory.friedSnack), // ahead of 'puri' the flatbread
    ('spring roll', FoodCategory.friedSnack),
    ('french frie', FoodCategory.friedSnack),
    ('frie', FoodCategory.friedSnack), // "fries" stems to "frie"
    ('chip', FoodCategory.friedSnack),
    ('namkeen', FoodCategory.friedSnack),
    ('bhujia', FoodCategory.friedSnack),
    ('tempura', FoodCategory.friedSnack),
    ('falafel', FoodCategory.friedSnack),
    ('nacho', FoodCategory.friedSnack),
    ('popcorn', FoodCategory.friedSnack),

    // ── Sweets (ahead of milk / cheese / fruit) ────────────────────────────
    ('gulab jamun', FoodCategory.sweet),
    ('jalebi', FoodCategory.sweet),
    ('laddu', FoodCategory.sweet),
    ('ladoo', FoodCategory.sweet),
    ('barfi', FoodCategory.sweet),
    ('halwa', FoodCategory.sweet),
    ('kheer', FoodCategory.sweet),
    ('mithai', FoodCategory.sweet),
    ('rasgulla', FoodCategory.sweet),
    ('ice cream', FoodCategory.sweet),
    ('chocolate', FoodCategory.sweet),
    ('cake', FoodCategory.sweet),
    ('brownie', FoodCategory.sweet),
    ('cookie', FoodCategory.sweet),
    ('biscuit', FoodCategory.sweet),
    ('donut', FoodCategory.sweet),
    ('doughnut', FoodCategory.sweet),
    ('pastry', FoodCategory.sweet),
    ('dessert', FoodCategory.sweet),
    ('candy', FoodCategory.sweet),
    ('tiramisu', FoodCategory.sweet),

    // ── Soups (ahead of vegetable / chicken) ───────────────────────────────
    ('soup', FoodCategory.soup),
    ('rasam', FoodCategory.soup),
    ('shorba', FoodCategory.soup),
    ('broth', FoodCategory.soup),
    ('stew', FoodCategory.soup),

    // ── Pasta & noodles (ahead of cheese, for "mac and cheese") ────────────
    ('pasta', FoodCategory.pasta),
    ('spaghetti', FoodCategory.pasta),
    ('macaroni', FoodCategory.pasta),
    ('mac and cheese', FoodCategory.pasta),
    ('penne', FoodCategory.pasta),
    ('lasagna', FoodCategory.pasta),
    ('ravioli', FoodCategory.pasta),
    ('gnocchi', FoodCategory.pasta),
    ('noodle', FoodCategory.noodles),
    ('ramen', FoodCategory.noodles),
    ('udon', FoodCategory.noodles),
    ('maggi', FoodCategory.noodles),
    ('chowmein', FoodCategory.noodles),
    ('chow mein', FoodCategory.noodles),
    ('hakka', FoodCategory.noodles),
    ('pad thai', FoodCategory.noodles),
    ('japchae', FoodCategory.noodles),

    // ── Flatbreads ─────────────────────────────────────────────────────────
    ('roti', FoodCategory.flatbread),
    ('chapati', FoodCategory.flatbread),
    ('chapathi', FoodCategory.flatbread),
    ('phulka', FoodCategory.flatbread),
    ('naan', FoodCategory.flatbread),
    ('paratha', FoodCategory.flatbread),
    ('parantha', FoodCategory.flatbread),
    ('kulcha', FoodCategory.flatbread),
    ('thepla', FoodCategory.flatbread),
    ('puri', FoodCategory.flatbread),
    ('poori', FoodCategory.flatbread),
    ('bhatura', FoodCategory.flatbread),
    ('tortilla', FoodCategory.flatbread),
    ('pita', FoodCategory.flatbread),

    // ── Bread & cereal ─────────────────────────────────────────────────────
    ('bread', FoodCategory.bread),
    ('toast', FoodCategory.bread),
    ('bagel', FoodCategory.bread),
    ('croissant', FoodCategory.bread),
    ('rusk', FoodCategory.bread),
    ('bun', FoodCategory.bread),
    ('oat', FoodCategory.oats),
    ('oatmeal', FoodCategory.oats),
    ('porridge', FoodCategory.oats),
    ('muesli', FoodCategory.oats),
    ('granola', FoodCategory.oats),
    ('cereal', FoodCategory.oats),
    ('cornflake', FoodCategory.oats),
    ('dalia', FoodCategory.oats),
    ('rice', FoodCategory.rice),
    ('chawal', FoodCategory.rice),
    ('quinoa', FoodCategory.rice),

    // ── Legumes ────────────────────────────────────────────────────────────
    ('dal', FoodCategory.dal),
    ('daal', FoodCategory.dal),
    ('lentil', FoodCategory.dal),
    ('sambar', FoodCategory.dal),
    ('rajma', FoodCategory.dal),
    ('chana', FoodCategory.dal),
    ('chole', FoodCategory.dal),
    ('chickpea', FoodCategory.dal),
    ('hummus', FoodCategory.dal),
    ('sprout', FoodCategory.dal),
    ('moong', FoodCategory.dal),
    ('lobia', FoodCategory.dal),

    // ── Protein (paneer ahead of egg so "paneer bhurji" is paneer) ─────────
    ('paneer', FoodCategory.paneer),
    ('tofu', FoodCategory.paneer),
    ('tempeh', FoodCategory.paneer),
    ('soya', FoodCategory.paneer),
    ('soy chunk', FoodCategory.paneer),
    ('egg', FoodCategory.egg),
    ('anda', FoodCategory.egg),
    ('omelette', FoodCategory.egg),
    ('omelet', FoodCategory.egg),
    ('bhurji', FoodCategory.egg),
    ('chicken', FoodCategory.chicken),
    ('murgh', FoodCategory.chicken),
    ('tandoori', FoodCategory.chicken),
    ('kebab', FoodCategory.chicken),
    ('tikka', FoodCategory.chicken),
    ('nugget', FoodCategory.chicken),
    ('turkey', FoodCategory.chicken),
    ('duck', FoodCategory.chicken),
    ('mutton', FoodCategory.redMeat),
    ('lamb', FoodCategory.redMeat),
    ('beef', FoodCategory.redMeat),
    ('pork', FoodCategory.redMeat),
    ('bacon', FoodCategory.redMeat),
    ('sausage', FoodCategory.redMeat),
    ('salami', FoodCategory.redMeat),
    ('steak', FoodCategory.redMeat),
    ('keema', FoodCategory.redMeat),
    ('ham', FoodCategory.redMeat),
    ('bulgogi', FoodCategory.redMeat),
    ('rib', FoodCategory.redMeat),
    ('bbq', FoodCategory.redMeat),
    ('sushi', FoodCategory.sushi),
    ('sashimi', FoodCategory.sushi),
    ('maki', FoodCategory.sushi),
    ('kimbap', FoodCategory.sushi),
    ('gimbap', FoodCategory.sushi),
    ('fish', FoodCategory.fish),
    ('salmon', FoodCategory.fish),
    ('tuna', FoodCategory.fish),
    ('prawn', FoodCategory.fish),
    ('shrimp', FoodCategory.fish),
    ('crab', FoodCategory.fish),
    ('seafood', FoodCategory.fish),

    // ── Gravies. After the proteins, so "paneer tikka masala" is paneer;
    //    after oats, so "masala oats" is not a curry. ────────────────────────
    ('curry', FoodCategory.curry),
    ('sabzi', FoodCategory.curry),
    ('sabji', FoodCategory.curry),
    ('gravy', FoodCategory.curry),
    ('korma', FoodCategory.curry),
    ('kadhi', FoodCategory.curry),
    ('masala', FoodCategory.curry),

    // ── Dairy ──────────────────────────────────────────────────────────────
    ('curd', FoodCategory.yogurt),
    ('dahi', FoodCategory.yogurt),
    ('yogurt', FoodCategory.yogurt),
    ('yoghurt', FoodCategory.yogurt),
    ('raita', FoodCategory.yogurt),
    ('shrikhand', FoodCategory.yogurt),
    ('milk', FoodCategory.milk),
    ('doodh', FoodCategory.milk),
    ('lassi', FoodCategory.milk),
    ('buttermilk', FoodCategory.milk),
    ('chaa', FoodCategory.milk), // "chaas" stems to "chaa"
    ('cheese', FoodCategory.cheese),
    ('butter', FoodCategory.cheese),
    ('ghee', FoodCategory.cheese),
    ('cream', FoodCategory.cheese),
    ('mayonnaise', FoodCategory.cheese),
    ('oil', FoodCategory.cheese),

    // ── Nuts & seeds ───────────────────────────────────────────────────────
    // "dry fruits" is the Indian term for a nut-and-dried-fruit mix and is
    // mostly nuts by weight, so it sits here rather than under produce. It
    // must also precede the bare 'fruit' rule further down, which would
    // otherwise claim it.
    ('dry fruit', FoodCategory.nuts),
    ('dried fruit', FoodCategory.nuts),
    ('almond', FoodCategory.nuts),
    ('badam', FoodCategory.nuts),
    ('cashew', FoodCategory.nuts),
    ('kaju', FoodCategory.nuts),
    ('walnut', FoodCategory.nuts),
    ('akhrot', FoodCategory.nuts),
    ('peanut', FoodCategory.nuts),
    ('mungfali', FoodCategory.nuts),
    ('pista', FoodCategory.nuts),
    ('pistachio', FoodCategory.nuts),
    ('hazelnut', FoodCategory.nuts),
    ('makhana', FoodCategory.nuts),
    // Coconut flesh is a fat, but it lives below the drinks block so that
    // "coconut water" stays a drink — see the rule just after it.
    ('nut', FoodCategory.nuts),
    ('seed', FoodCategory.nuts),
    ('chia', FoodCategory.nuts),
    ('flax', FoodCategory.nuts),
    ('trail mix', FoodCategory.nuts),

    // ── Drinks. Ahead of produce, so "green tea" is not a vegetable and
    //    "orange juice" is not a citrus fruit. Whole-token matching keeps
    //    'water' out of "watermelon". ────────────────────────────────────────
    ('coffee', FoodCategory.coffee),
    ('espresso', FoodCategory.coffee),
    ('latte', FoodCategory.coffee),
    ('cappuccino', FoodCategory.coffee),
    ('tea', FoodCategory.tea),
    ('chai', FoodCategory.tea),
    ('juice', FoodCategory.juice),
    ('smoothie', FoodCategory.juice),
    ('shake', FoodCategory.juice),
    ('coconut water', FoodCategory.water),
    ('nariyal pani', FoodCategory.water),
    // The flesh, once both drink spellings above have had their chance.
    // Placing these in the nuts block instead made "coconut water" resolve to
    // nuts, which the catalog test caught.
    ('coconut', FoodCategory.nuts),
    ('nariyal', FoodCategory.nuts),
    ('water', FoodCategory.water),
    ('soda', FoodCategory.soda),
    ('cola', FoodCategory.soda),
    ('soft drink', FoodCategory.soda),
    ('energy drink', FoodCategory.soda),

    // ── Fruit ──────────────────────────────────────────────────────────────
    ('banana', FoodCategory.banana),
    ('kela', FoodCategory.banana),
    ('apple', FoodCategory.apple),
    ('orange', FoodCategory.citrus),
    ('lemon', FoodCategory.citrus),
    ('lime', FoodCategory.citrus),
    ('mosambi', FoodCategory.citrus),
    ('grapefruit', FoodCategory.citrus),
    // Stemming only drops a trailing "s", so an "-ies" plural needs its own
    // spelling: "blueberries" arrives here as "blueberrie".
    ('berry', FoodCategory.berries),
    ('berrie', FoodCategory.berries),
    ('strawberry', FoodCategory.berries),
    ('strawberrie', FoodCategory.berries),
    ('blueberry', FoodCategory.berries),
    ('blueberrie', FoodCategory.berries),
    ('raspberry', FoodCategory.berries),
    ('raspberrie', FoodCategory.berries),
    ('cranberry', FoodCategory.berries),
    ('cranberrie', FoodCategory.berries),
    ('mango', FoodCategory.tropicalFruit),
    ('papaya', FoodCategory.tropicalFruit),
    ('pineapple', FoodCategory.tropicalFruit),
    ('melon', FoodCategory.tropicalFruit),
    ('watermelon', FoodCategory.tropicalFruit),
    ('grape', FoodCategory.fruit),
    ('pomegranate', FoodCategory.fruit),
    ('guava', FoodCategory.fruit),
    ('pear', FoodCategory.fruit),
    ('kiwi', FoodCategory.fruit),
    ('chikoo', FoodCategory.fruit),
    ('date', FoodCategory.fruit),
    ('khajoor', FoodCategory.fruit),
    ('khajur', FoodCategory.fruit),
    ('fig', FoodCategory.fruit),
    ('anjeer', FoodCategory.fruit),
    ('raisin', FoodCategory.fruit),
    ('kishmish', FoodCategory.fruit),
    ('munakka', FoodCategory.fruit),
    ('prune', FoodCategory.fruit),
    ('apricot', FoodCategory.fruit),
    ('fruit', FoodCategory.fruit),

    // ── Vegetables ─────────────────────────────────────────────────────────
    ('potato', FoodCategory.potato),
    ('potatoe', FoodCategory.potato),
    ('aloo', FoodCategory.potato),
    ('avocado', FoodCategory.avocado),
    ('guacamole', FoodCategory.avocado),
    ('salad', FoodCategory.salad),
    ('tabbouleh', FoodCategory.salad),
    ('slaw', FoodCategory.salad),
    ('lettuce', FoodCategory.salad),
    ('cucumber', FoodCategory.salad),
    ('tomato', FoodCategory.salad),
    ('carrot', FoodCategory.salad),
    ('beetroot', FoodCategory.salad),
    ('vegetable', FoodCategory.vegetable),
    ('veggie', FoodCategory.vegetable),
    ('broccoli', FoodCategory.vegetable),
    ('spinach', FoodCategory.vegetable),
    ('palak', FoodCategory.vegetable),
    ('bhindi', FoodCategory.vegetable),
    ('okra', FoodCategory.vegetable),
    ('gobi', FoodCategory.vegetable),
    ('cauliflower', FoodCategory.vegetable),
    ('cabbage', FoodCategory.vegetable),
    ('pea', FoodCategory.vegetable),
    ('mushroom', FoodCategory.vegetable),
    ('corn', FoodCategory.vegetable),
    ('capsicum', FoodCategory.vegetable),
    ('bell pepper', FoodCategory.vegetable),
    ('kimchi', FoodCategory.vegetable),
    ('zucchini', FoodCategory.vegetable),
    ('pumpkin', FoodCategory.vegetable),
    ('green', FoodCategory.vegetable),
  ];

  static final RegExp _nonAlnum = RegExp(r'[^a-z0-9]+');

  /// Rules pre-normalised once, so matching is a plain substring scan.
  static final List<(String, FoodCategory)> _matchers = [
    for (final (keyword, category) in _rules) (_normalize(keyword), category),
  ];

  /// Lowercases, strips punctuation and drops a trailing "s" from every token
  /// longer than three characters. The same stemming runs over the rule
  /// keywords, so "Boiled Eggs (2)" and "egg" meet in the middle without the
  /// table needing a plural for each entry.
  static String _normalize(String raw) {
    final cleaned = raw.toLowerCase().replaceAll(_nonAlnum, ' ').trim();
    if (cleaned.isEmpty) return ' ';
    final tokens = cleaned.split(' ').map(_stem).join(' ');
    return ' $tokens ';
  }

  static String _stem(String token) => token.length > 3 && token.endsWith('s')
      ? token.substring(0, token.length - 1)
      : token;

  /// Best-guess category for [foodName]. Falls back to [FoodCategory.other].
  static FoodCategory resolve(String foodName) {
    final name = _normalize(foodName);
    for (final (keyword, category) in _matchers) {
      if (name.contains(keyword)) return category;
    }
    return FoodCategory.other;
  }

  /// [foodPhotoAssets], normalised like [resolve]'s own rules and sorted
  /// longest-first so a composite dish ("chicken biryani") wins over a
  /// shorter one that also happens to appear in the name ("chicken curry"
  /// logged as "leftover chicken curry" must not match a hypothetical
  /// generic "chicken" entry first). Built once on first access.
  static final List<(String, String)> _photoMatchers = [
    for (final entry in foodPhotoAssets.entries)
      (_normalize(entry.key), entry.value),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));

  /// Photo for [foodName], if the pack has one.
  ///
  /// A real logged name is rarely the bare dish name alone — "Grilled Chicken
  /// Biryani with raita", "2 Idli" — so like [resolve] this scans for the
  /// catalog entry anywhere in the normalised name rather than requiring an
  /// exact match, which matched almost nothing in practice.
  static String? photoFor(String foodName) {
    final name = _normalize(foodName);
    for (final (key, asset) in _photoMatchers) {
      if (name.contains(key)) return asset;
    }
    return null;
  }
}

/// Which OpenMoji set to draw from: full-colour glyphs, or line art that takes
/// the category tint.
enum FoodIconStyle { color, mono }

/// Presentation for a [FoodCategory]. The tint follows the macro the food
/// mostly contributes, reusing the dashboard's macro colours.
extension FoodCategoryStyle on FoodCategory {
  /// Fallback glyph, used if the SVG can't be drawn.
  IconData get icon => _styles[this]!.icon;
  Color get tint => _styles[this]!.tint;

  /// The bundled OpenMoji SVG for this category. Every category has one in
  /// both styles — `food_assets_test.dart` holds that guarantee.
  String assetFor(FoodIconStyle style) =>
      'assets/icons/food/${style.name}/$name.svg';
}

typedef _Style = ({IconData icon, Color tint});

const Map<FoodCategory, _Style> _styles = {
  // Carb-led
  FoodCategory.rice: (icon: Icons.rice_bowl_rounded, tint: AppColors.carbs),
  FoodCategory.flatbread: (icon: Icons.flatware_rounded, tint: AppColors.carbs),
  FoodCategory.bread: (
    icon: Icons.bakery_dining_rounded,
    tint: AppColors.carbs
  ),
  FoodCategory.oats: (
    icon: Icons.breakfast_dining_rounded,
    tint: AppColors.carbs
  ),
  FoodCategory.pasta: (
    icon: Icons.dinner_dining_rounded,
    tint: AppColors.carbs
  ),
  FoodCategory.noodles: (
    icon: Icons.ramen_dining_rounded,
    tint: AppColors.carbs
  ),
  FoodCategory.steamedCake: (
    icon: Icons.brunch_dining_rounded,
    tint: AppColors.carbs
  ),
  FoodCategory.crepe: (icon: Icons.local_pizza_rounded, tint: AppColors.carbs),
  FoodCategory.pizza: (icon: Icons.local_pizza_rounded, tint: AppColors.carbs),
  FoodCategory.burger: (
    icon: Icons.lunch_dining_rounded,
    tint: AppColors.carbs
  ),
  FoodCategory.sandwich: (
    icon: Icons.lunch_dining_rounded,
    tint: AppColors.carbs
  ),
  FoodCategory.sweet: (icon: Icons.cake_rounded, tint: AppColors.carbs),
  FoodCategory.potato: (icon: Icons.set_meal_rounded, tint: AppColors.carbs),
  FoodCategory.banana: (icon: Icons.eco_rounded, tint: AppColors.carbs),

  // Protein-led
  FoodCategory.dal: (icon: Icons.soup_kitchen_rounded, tint: AppColors.protein),
  FoodCategory.paneer: (
    icon: Icons.breakfast_dining_rounded,
    tint: AppColors.protein
  ),
  FoodCategory.egg: (icon: Icons.egg_rounded, tint: AppColors.protein),
  FoodCategory.chicken: (
    icon: Icons.kebab_dining_rounded,
    tint: AppColors.protein
  ),
  FoodCategory.redMeat: (
    icon: Icons.kebab_dining_rounded,
    tint: AppColors.protein
  ),
  FoodCategory.fish: (icon: Icons.set_meal_rounded, tint: AppColors.protein),
  FoodCategory.sushi: (icon: Icons.set_meal_rounded, tint: AppColors.protein),
  FoodCategory.proteinShake: (
    icon: Icons.local_drink_rounded,
    tint: AppColors.protein
  ),
  FoodCategory.proteinBar: (icon: Icons.bolt_rounded, tint: AppColors.protein),
  FoodCategory.yogurt: (icon: Icons.icecream_rounded, tint: AppColors.protein),
  FoodCategory.milk: (icon: Icons.local_drink_rounded, tint: AppColors.protein),

  // Fat-led
  FoodCategory.cheese: (icon: Icons.local_pizza_rounded, tint: AppColors.fat),
  FoodCategory.nuts: (icon: Icons.grain_rounded, tint: AppColors.fat),
  FoodCategory.avocado: (icon: Icons.eco_rounded, tint: AppColors.fat),
  FoodCategory.friedSnack: (icon: Icons.fastfood_rounded, tint: AppColors.fat),
  FoodCategory.curry: (icon: Icons.ramen_dining_rounded, tint: AppColors.fat),

  // Fibre-led
  FoodCategory.salad: (icon: Icons.grass_rounded, tint: AppColors.fiber),
  FoodCategory.vegetable: (icon: Icons.grass_rounded, tint: AppColors.fiber),
  FoodCategory.fruit: (
    icon: Icons.local_florist_rounded,
    tint: AppColors.fiber
  ),
  FoodCategory.apple: (
    icon: Icons.local_florist_rounded,
    tint: AppColors.fiber
  ),
  FoodCategory.citrus: (
    icon: Icons.local_florist_rounded,
    tint: AppColors.fiber
  ),
  FoodCategory.berries: (
    icon: Icons.local_florist_rounded,
    tint: AppColors.fiber
  ),
  FoodCategory.tropicalFruit: (
    icon: Icons.local_florist_rounded,
    tint: AppColors.fiber
  ),
  FoodCategory.soup: (icon: Icons.soup_kitchen_rounded, tint: AppColors.fiber),

  // Hydration
  FoodCategory.water: (icon: Icons.water_drop_rounded, tint: AppColors.water),
  FoodCategory.tea: (
    icon: Icons.emoji_food_beverage_rounded,
    tint: AppColors.water
  ),
  FoodCategory.coffee: (icon: Icons.coffee_rounded, tint: AppColors.water),
  FoodCategory.juice: (icon: Icons.local_bar_rounded, tint: AppColors.water),
  FoodCategory.soda: (icon: Icons.local_bar_rounded, tint: AppColors.water),

  FoodCategory.other: (icon: Icons.restaurant_rounded, tint: AppColors.primary),
};
