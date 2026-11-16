class UserProfile {
  final String id;
  final String? name;
  final int? age;
  final String? gender;
  final double? heightCm;
  final double? weightKg;
  final double? targetWeightKg;
  final String? goal;
  final String? activityLevel;
  final int calorieGoal;
  final double proteinGoalG;
  final double carbsGoalG;
  final double fatGoalG;
  final double fiberGoalG;
  final int waterGoalMl;
  final int stepsGoal;
  final double sleepGoalHrs;
  final String language;
  final String theme;
  final String? avatarUrl;
  final bool onboardingComplete;

  /// When the account was created, straight from `profiles.created_at`.
  ///
  /// This is the anchor for the free trial, and it lives on the server for
  /// exactly that reason: clearing app data or reinstalling cannot move it, so
  /// the three days can't be restarted. Deliberately absent from [toJson] —
  /// the column defaults to now() and the client must never overwrite it.
  ///
  /// Null on a profile that predates this field, or one built locally before
  /// the first pull.
  final DateTime? createdAt;

  UserProfile({
    required this.id,
    this.name,
    this.age,
    this.gender,
    this.heightCm,
    this.weightKg,
    this.targetWeightKg,
    this.goal,
    this.activityLevel,
    this.calorieGoal = 2000,
    this.proteinGoalG = 100,
    this.carbsGoalG = 250,
    this.fatGoalG = 65,
    this.fiberGoalG = 30,
    this.waterGoalMl = 2500,
    this.stepsGoal = 10000,
    this.sleepGoalHrs = 8,
    this.language = 'en',
    this.theme = 'light',
    this.avatarUrl,
    this.onboardingComplete = false,
    this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
        name: j['name'] as String?,
        age: j['age'] as int?,
        gender: j['gender'] as String?,
        heightCm: (j['height_cm'] as num?)?.toDouble(),
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        targetWeightKg: (j['target_weight_kg'] as num?)?.toDouble(),
        goal: j['goal'] as String?,
        activityLevel: j['activity_level'] as String?,
        calorieGoal: (j['calorie_goal'] as num?)?.toInt() ?? 2000,
        proteinGoalG: (j['protein_goal_g'] as num?)?.toDouble() ?? 100,
        carbsGoalG: (j['carbs_goal_g'] as num?)?.toDouble() ?? 250,
        fatGoalG: (j['fat_goal_g'] as num?)?.toDouble() ?? 65,
        fiberGoalG: (j['fiber_goal_g'] as num?)?.toDouble() ?? 30,
        waterGoalMl: (j['water_goal_ml'] as num?)?.toInt() ?? 2500,
        stepsGoal: (j['steps_goal'] as num?)?.toInt() ?? 10000,
        sleepGoalHrs: (j['sleep_goal_hrs'] as num?)?.toDouble() ?? 8,
        language: j['language'] as String? ?? 'en',
        theme: j['theme'] as String? ?? 'light',
        avatarUrl: j['avatar_url'] as String?,
        onboardingComplete: j['onboarding_complete'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'gender': gender,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'target_weight_kg': targetWeightKg,
        'goal': goal,
        'activity_level': activityLevel,
        'calorie_goal': calorieGoal,
        'protein_goal_g': proteinGoalG,
        'carbs_goal_g': carbsGoalG,
        'fat_goal_g': fatGoalG,
        'fiber_goal_g': fiberGoalG,
        'water_goal_ml': waterGoalMl,
        'steps_goal': stepsGoal,
        'sleep_goal_hrs': sleepGoalHrs,
        'language': language,
        'theme': theme,
        'avatar_url': avatarUrl,
        'onboarding_complete': onboardingComplete,
      };

  UserProfile copyWith({
    String? name,
    int? age,
    String? gender,
    double? heightCm,
    double? weightKg,
    double? targetWeightKg,
    String? goal,
    String? activityLevel,
    int? calorieGoal,
    double? proteinGoalG,
    double? carbsGoalG,
    double? fatGoalG,
    double? fiberGoalG,
    int? waterGoalMl,
    int? stepsGoal,
    double? sleepGoalHrs,
    String? language,
    String? theme,
    String? avatarUrl,
    bool? onboardingComplete,
  }) =>
      UserProfile(
        id: id,
        name: name ?? this.name,
        age: age ?? this.age,
        gender: gender ?? this.gender,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        targetWeightKg: targetWeightKg ?? this.targetWeightKg,
        goal: goal ?? this.goal,
        activityLevel: activityLevel ?? this.activityLevel,
        calorieGoal: calorieGoal ?? this.calorieGoal,
        proteinGoalG: proteinGoalG ?? this.proteinGoalG,
        carbsGoalG: carbsGoalG ?? this.carbsGoalG,
        fatGoalG: fatGoalG ?? this.fatGoalG,
        fiberGoalG: fiberGoalG ?? this.fiberGoalG,
        waterGoalMl: waterGoalMl ?? this.waterGoalMl,
        stepsGoal: stepsGoal ?? this.stepsGoal,
        sleepGoalHrs: sleepGoalHrs ?? this.sleepGoalHrs,
        language: language ?? this.language,
        theme: theme ?? this.theme,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      );
}
