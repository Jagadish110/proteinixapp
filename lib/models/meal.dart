class Meal {
  final String? id;
  final String userId;
  final DateTime date;
  final String mealType; // breakfast/lunch/dinner/snack
  final String foodName;
  final double? quantity;
  final String? unit;
  final int calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final String logMethod; // manual / scan / search / quick / barcode
  final String? scanConfidence;
  final DateTime? loggedAt;

  Meal({
    this.id,
    required this.userId,
    required this.date,
    required this.mealType,
    required this.foodName,
    this.quantity,
    this.unit,
    this.calories = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.fiberG = 0,
    this.logMethod = 'manual',
    this.scanConfidence,
    this.loggedAt,
  });

  factory Meal.fromJson(Map<String, dynamic> j) => Meal(
        id: j['id'] as String?,
        userId: j['user_id'] as String,
        date: DateTime.parse(j['date'] as String),
        mealType: j['meal_type'] as String,
        foodName: j['food_name'] as String,
        quantity: (j['quantity'] as num?)?.toDouble(),
        unit: j['unit'] as String?,
        calories: (j['calories'] as num?)?.toInt() ?? 0,
        proteinG: (j['protein_g'] as num?)?.toDouble() ?? 0,
        carbsG: (j['carbs_g'] as num?)?.toDouble() ?? 0,
        fatG: (j['fat_g'] as num?)?.toDouble() ?? 0,
        fiberG: (j['fiber_g'] as num?)?.toDouble() ?? 0,
        logMethod: j['log_method'] as String? ?? 'manual',
        scanConfidence: j['scan_confidence'] as String?,
        loggedAt: j['logged_at'] != null
            ? DateTime.parse(j['logged_at'] as String)
            : null,
      );

  Map<String, dynamic> toInsertJson() => {
        'user_id': userId,
        'date': date.toIso8601String().split('T').first,
        'meal_type': mealType,
        'food_name': foodName,
        'quantity': quantity,
        'unit': unit,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'fiber_g': fiberG,
        'log_method': logMethod,
        'scan_confidence': scanConfidence,
      };
}
