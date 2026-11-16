// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_profile.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalProfileAdapter extends TypeAdapter<LocalProfile> {
  @override
  final int typeId = 2;

  @override
  LocalProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalProfile(
      id: fields[0] as String,
      name: fields[1] as String?,
      age: fields[2] as int?,
      gender: fields[3] as String?,
      heightCm: fields[4] as double?,
      weightKg: fields[5] as double?,
      goal: fields[6] as String?,
      activityLevel: fields[7] as String?,
      calorieGoal: fields[8] as int,
      proteinGoalG: fields[9] as double,
      carbsGoalG: fields[10] as double,
      fatGoalG: fields[11] as double,
      waterGoalMl: fields[12] as int,
      stepsGoal: fields[13] as int,
      sleepGoalHrs: fields[14] as double,
      isSynced: fields[15] as bool,
      fiberGoalG: fields[16] as double,
      language: fields[17] as String,
      theme: fields[18] as String,
      avatarUrl: fields[19] as String?,
      onboardingComplete: fields[20] as bool,
      createdAt: fields[21] as DateTime?,
      targetWeightKg: fields[22] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, LocalProfile obj) {
    writer
      ..writeByte(23)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.age)
      ..writeByte(3)
      ..write(obj.gender)
      ..writeByte(4)
      ..write(obj.heightCm)
      ..writeByte(5)
      ..write(obj.weightKg)
      ..writeByte(6)
      ..write(obj.goal)
      ..writeByte(7)
      ..write(obj.activityLevel)
      ..writeByte(8)
      ..write(obj.calorieGoal)
      ..writeByte(9)
      ..write(obj.proteinGoalG)
      ..writeByte(10)
      ..write(obj.carbsGoalG)
      ..writeByte(11)
      ..write(obj.fatGoalG)
      ..writeByte(12)
      ..write(obj.waterGoalMl)
      ..writeByte(13)
      ..write(obj.stepsGoal)
      ..writeByte(14)
      ..write(obj.sleepGoalHrs)
      ..writeByte(15)
      ..write(obj.isSynced)
      ..writeByte(16)
      ..write(obj.fiberGoalG)
      ..writeByte(17)
      ..write(obj.language)
      ..writeByte(18)
      ..write(obj.theme)
      ..writeByte(19)
      ..write(obj.avatarUrl)
      ..writeByte(20)
      ..write(obj.onboardingComplete)
      ..writeByte(21)
      ..write(obj.createdAt)
      ..writeByte(22)
      ..write(obj.targetWeightKg);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
