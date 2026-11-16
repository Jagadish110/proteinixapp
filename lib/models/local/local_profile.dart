import 'package:hive/hive.dart';

import '../user_profile.dart';

part 'local_profile.g.dart';

/// The signed-in user's `profiles` row, cached on device.
///
/// This is what lets the app open with no network at all: [onboardingComplete]
/// is the single fact the splash screen needs in order to route, and reading it
/// from here means launch no longer depends on a Supabase round trip.
@HiveType(typeId: 2)
class LocalProfile extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String? name;

  @HiveField(2)
  int? age;

  @HiveField(3)
  String? gender;

  @HiveField(4)
  double? heightCm;

  @HiveField(5)
  double? weightKg;

  @HiveField(6)
  String? goal;

  @HiveField(7)
  String? activityLevel;

  @HiveField(8)
  int calorieGoal;

  @HiveField(9)
  double proteinGoalG;

  @HiveField(10)
  double carbsGoalG;

  @HiveField(11)
  double fatGoalG;

  @HiveField(12)
  int waterGoalMl;

  @HiveField(13)
  int stepsGoal;

  @HiveField(14)
  double sleepGoalHrs;

  @HiveField(15)
  bool isSynced;

  // Beyond the original spec, but all of these are already part of UserProfile
  // and round-tripping through Hive would silently reset them otherwise.
  @HiveField(16)
  double fiberGoalG;

  @HiveField(17)
  String language;

  @HiveField(18)
  String theme;

  @HiveField(19)
  String? avatarUrl;

  @HiveField(20)
  bool onboardingComplete;

  /// Account creation date, cached from the server so the free trial can be
  /// evaluated offline. See [UserProfile.createdAt] for why the server owns it.
  @HiveField(21)
  DateTime? createdAt;

  @HiveField(22)
  double? targetWeightKg;

  LocalProfile({
    required this.id,
    this.name,
    this.age,
    this.gender,
    this.heightCm,
    this.weightKg,
    this.goal,
    this.activityLevel,
    this.calorieGoal = 2000,
    this.proteinGoalG = 100,
    this.carbsGoalG = 250,
    this.fatGoalG = 65,
    this.waterGoalMl = 2500,
    this.stepsGoal = 10000,
    this.sleepGoalHrs = 8,
    this.isSynced = false,
    this.fiberGoalG = 30,
    this.language = 'en',
    this.theme = 'light',
    this.avatarUrl,
    this.onboardingComplete = false,
    this.createdAt,
    this.targetWeightKg,
  });

  factory LocalProfile.fromDomain(UserProfile p, {bool isSynced = false}) =>
      LocalProfile(
        id: p.id,
        name: p.name,
        age: p.age,
        gender: p.gender,
        heightCm: p.heightCm,
        weightKg: p.weightKg,
        targetWeightKg: p.targetWeightKg,
        goal: p.goal,
        activityLevel: p.activityLevel,
        calorieGoal: p.calorieGoal,
        proteinGoalG: p.proteinGoalG,
        carbsGoalG: p.carbsGoalG,
        fatGoalG: p.fatGoalG,
        waterGoalMl: p.waterGoalMl,
        stepsGoal: p.stepsGoal,
        sleepGoalHrs: p.sleepGoalHrs,
        isSynced: isSynced,
        fiberGoalG: p.fiberGoalG,
        language: p.language,
        theme: p.theme,
        avatarUrl: p.avatarUrl,
        onboardingComplete: p.onboardingComplete,
        // May be null: a profile the app builds itself never carries one, since
        // the column is server-owned. `LocalDBService._keepCreatedAt` is what
        // stops that null reaching disk and restarting the free trial.
        createdAt: p.createdAt,
      );

  factory LocalProfile.fromRow(Map<String, dynamic> j) =>
      LocalProfile.fromDomain(UserProfile.fromJson(j), isSynced: true);

  UserProfile toDomain() => UserProfile(
        id: id,
        name: name,
        age: age,
        gender: gender,
        heightCm: heightCm,
        weightKg: weightKg,
        targetWeightKg: targetWeightKg,
        goal: goal,
        activityLevel: activityLevel,
        calorieGoal: calorieGoal,
        proteinGoalG: proteinGoalG,
        carbsGoalG: carbsGoalG,
        fatGoalG: fatGoalG,
        fiberGoalG: fiberGoalG,
        waterGoalMl: waterGoalMl,
        stepsGoal: stepsGoal,
        sleepGoalHrs: sleepGoalHrs,
        language: language,
        theme: theme,
        avatarUrl: avatarUrl,
        onboardingComplete: onboardingComplete,
        createdAt: createdAt,
      );

  Map<String, dynamic> toRow() => toDomain().toJson();
}
