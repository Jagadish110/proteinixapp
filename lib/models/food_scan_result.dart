class FoodItem {
  final String name;
  final double quantity; // actual grams/ml in the serving
  final String unit; // always "g" or "ml"
  final double caloriesPer100g; // reference value used
  final int calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double sugarG;
  final int sodiumMg;
  final String cookingMethod;
  final String confidenceNote;

  /// Other dishes this could plausibly be, best guess first.
  ///
  /// Vision models are far more reliable at ranking a short candidate list than
  /// at committing to one answer, so the model is asked for runners-up and the
  /// user resolves it in a single tap. Misidentification is unrecoverable
  /// otherwise — a wrong dish makes every macro wrong no matter how precise the
  /// portion is.
  final List<String> alternatives;

  FoodItem({
    required this.name,
    this.quantity = 100,
    this.unit = 'g',
    this.caloriesPer100g = 0,
    this.calories = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.fiberG = 0,
    this.sugarG = 0,
    this.sodiumMg = 0,
    this.cookingMethod = '',
    this.confidenceNote = '',
    this.alternatives = const [],
  });

  factory FoodItem.fromJson(Map<String, dynamic> j) => FoodItem(
        name: (j['name'] ?? '').toString(),
        // support both quantity_g (new) and quantity (legacy)
        quantity: (j['quantity_g'] as num?)?.toDouble() ??
            (j['quantity'] as num?)?.toDouble() ??
            100,
        unit: (j['unit'] ?? 'g').toString(),
        caloriesPer100g: (j['calories_per_100g'] as num?)?.toDouble() ?? 0,
        calories: (j['calories'] as num?)?.toInt() ?? 0,
        proteinG: (j['protein_g'] as num?)?.toDouble() ?? 0,
        carbsG: (j['carbs_g'] as num?)?.toDouble() ?? 0,
        fatG: (j['fat_g'] as num?)?.toDouble() ?? 0,
        fiberG: (j['fiber_g'] as num?)?.toDouble() ?? 0,
        sugarG: (j['sugar_g'] as num?)?.toDouble() ?? 0,
        sodiumMg: (j['sodium_mg'] as num?)?.toInt() ?? 0,
        cookingMethod: (j['cooking_method'] ?? '').toString(),
        confidenceNote: (j['confidence_note'] ?? '').toString(),
        alternatives: (j['alternatives'] as List? ?? const [])
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity_g': quantity,
        'unit': unit,
        'calories_per_100g': caloriesPer100g,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'fiber_g': fiberG,
        'sugar_g': sugarG,
        'sodium_mg': sodiumMg,
        'cooking_method': cookingMethod,
        'confidence_note': confidenceNote,
      };

  /// Replaces the identified food, keeping the current portion.
  ///
  /// Macros come from [source] — the freshly-priced version of the corrected
  /// food — rather than being carried over. Renaming without re-pricing would
  /// leave the right label attached to the wrong numbers, which is worse than
  /// the original mistake because it now looks correct.
  FoodItem renamedTo(String newName, {FoodItem? source}) {
    final s = source;
    if (s == null) {
      return FoodItem(
        name: newName,
        quantity: quantity,
        unit: unit,
        caloriesPer100g: caloriesPer100g,
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        fiberG: fiberG,
        sugarG: sugarG,
        sodiumMg: sodiumMg,
        cookingMethod: cookingMethod,
        confidenceNote: 'Renamed — macros not re-priced.',
        alternatives: alternatives,
      );
    }
    // Re-scale the freshly-priced item to the portion already on screen.
    final priced = s.copyWith(quantity: quantity, unit: unit);
    return FoodItem(
      name: newName,
      quantity: quantity,
      unit: unit,
      caloriesPer100g: priced.caloriesPer100g,
      calories: priced.calories,
      proteinG: priced.proteinG,
      carbsG: priced.carbsG,
      fatG: priced.fatG,
      fiberG: priced.fiberG,
      sugarG: priced.sugarG,
      sodiumMg: priced.sodiumMg,
      cookingMethod: priced.cookingMethod,
      confidenceNote: 'Corrected by you.',
      alternatives: alternatives,
    );
  }

  FoodItem copyWith({double? quantity, String? unit}) {
    final double newQty = quantity ?? this.quantity;
    final String newUnit = unit ?? this.unit;

    // Convert both to a base weight in grams/ml to compute the correct ratio
    final double currentBase =
        this.quantity * (this.unit.toLowerCase() == 'kg' ? 1000.0 : 1.0);
    final double newBase =
        newQty * (newUnit.toLowerCase() == 'kg' ? 1000.0 : 1.0);

    final double ratio = currentBase > 0 ? (newBase / currentBase) : 1.0;

    return FoodItem(
      name: name,
      quantity: newQty,
      unit: newUnit,
      caloriesPer100g: caloriesPer100g,
      calories: (calories * ratio).round(),
      proteinG: proteinG * ratio,
      carbsG: carbsG * ratio,
      fatG: fatG * ratio,
      fiberG: fiberG * ratio,
      sugarG: sugarG * ratio,
      sodiumMg: (sodiumMg * ratio).round(),
      cookingMethod: cookingMethod,
      confidenceNote: confidenceNote,
      alternatives: alternatives,
    );
  }
}

class FoodScanResult {
  final bool detected;
  final List<FoodItem> foodItems;
  final int totalCalories;
  final double totalProteinG;
  final double totalCarbsG;
  final double totalFatG;
  final double totalFiberG;
  final double totalSugarG;
  final int totalSodiumMg;
  final String confidence; // high / medium / low
  final String mealType;
  final String portionEstimationMethod;
  final String calorieCheck; // validation string from AI

  FoodScanResult({
    required this.detected,
    required this.foodItems,
    required this.totalCalories,
    required this.totalProteinG,
    required this.totalCarbsG,
    required this.totalFatG,
    required this.totalFiberG,
    this.totalSugarG = 0,
    this.totalSodiumMg = 0,
    required this.confidence,
    required this.mealType,
    this.portionEstimationMethod = '',
    this.calorieCheck = '',
  });

  factory FoodScanResult.fromJson(Map<String, dynamic> j) {
    final items = (j['food_items'] as List? ?? [])
        .map((e) => FoodItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (j['total'] ?? {}) as Map<String, dynamic>;

    // Recompute totals from items as a safety cross-check
    // (use AI total if items list is empty)
    int recomputedCal = 0;
    double recomputedProt = 0,
        recomputedCarb = 0,
        recomputedFat = 0,
        recomputedFiber = 0,
        recomputedSugar = 0;
    int recomputedSodium = 0;
    for (final item in items) {
      recomputedCal += item.calories;
      recomputedProt += item.proteinG;
      recomputedCarb += item.carbsG;
      recomputedFat += item.fatG;
      recomputedFiber += item.fiberG;
      recomputedSugar += item.sugarG;
      recomputedSodium += item.sodiumMg;
    }

    final aiTotalCal = (total['calories'] as num?)?.toInt() ?? 0;
    // Use recomputed sum if items exist, else trust AI total
    final finalCal = items.isNotEmpty ? recomputedCal : aiTotalCal;

    return FoodScanResult(
      detected: j['detected'] as bool? ?? false,
      foodItems: items,
      totalCalories: finalCal,
      totalProteinG: items.isNotEmpty
          ? recomputedProt
          : (total['protein_g'] as num?)?.toDouble() ?? 0,
      totalCarbsG: items.isNotEmpty
          ? recomputedCarb
          : (total['carbs_g'] as num?)?.toDouble() ?? 0,
      totalFatG: items.isNotEmpty
          ? recomputedFat
          : (total['fat_g'] as num?)?.toDouble() ?? 0,
      totalFiberG: items.isNotEmpty
          ? recomputedFiber
          : (total['fiber_g'] as num?)?.toDouble() ?? 0,
      totalSugarG: items.isNotEmpty
          ? recomputedSugar
          : (total['sugar_g'] as num?)?.toDouble() ?? 0,
      totalSodiumMg: items.isNotEmpty
          ? recomputedSodium
          : (total['sodium_mg'] as num?)?.toInt() ?? 0,
      confidence: (j['confidence'] ?? 'medium').toString(),
      mealType: (j['meal_type'] ?? 'snack').toString(),
      portionEstimationMethod:
          (j['portion_estimation_method'] ?? '').toString(),
      calorieCheck: (j['calorie_check'] ?? '').toString(),
    );
  }

  FoodScanResult copyWith({
    bool? detected,
    List<FoodItem>? foodItems,
    int? totalCalories,
    double? totalProteinG,
    double? totalCarbsG,
    double? totalFatG,
    double? totalFiberG,
    double? totalSugarG,
    int? totalSodiumMg,
    String? confidence,
    String? mealType,
    String? portionEstimationMethod,
    String? calorieCheck,
  }) =>
      FoodScanResult(
        detected: detected ?? this.detected,
        foodItems: foodItems ?? this.foodItems,
        totalCalories: totalCalories ?? this.totalCalories,
        totalProteinG: totalProteinG ?? this.totalProteinG,
        totalCarbsG: totalCarbsG ?? this.totalCarbsG,
        totalFatG: totalFatG ?? this.totalFatG,
        totalFiberG: totalFiberG ?? this.totalFiberG,
        totalSugarG: totalSugarG ?? this.totalSugarG,
        totalSodiumMg: totalSodiumMg ?? this.totalSodiumMg,
        confidence: confidence ?? this.confidence,
        mealType: mealType ?? this.mealType,
        portionEstimationMethod:
            portionEstimationMethod ?? this.portionEstimationMethod,
        calorieCheck: calorieCheck ?? this.calorieCheck,
      );
}
