// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_daily_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalDailyLogAdapter extends TypeAdapter<LocalDailyLog> {
  @override
  final int typeId = 0;

  @override
  LocalDailyLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalDailyLog(
      id: fields[0] as String,
      userId: fields[1] as String,
      date: fields[2] as DateTime,
      caloriesConsumed: fields[3] as int,
      proteinG: fields[4] as double,
      carbsG: fields[5] as double,
      fatG: fields[6] as double,
      fiberG: fields[7] as double,
      waterMl: fields[8] as int,
      steps: fields[9] as int,
      sleepHrs: fields[10] as double,
      weightKg: fields[11] as double?,
      isSynced: fields[12] as bool,
      lastUpdated: fields[13] as DateTime,
      caloriesBurned: fields[14] as int,
      sleepQuality: fields[15] as int,
      sleepInterruptions: fields[16] as int,
      phonePickups: fields[17] as int,
      sleepScore: fields[18] as int,
      sleepStart: fields[19] as DateTime?,
      sleepEnd: fields[20] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, LocalDailyLog obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.caloriesConsumed)
      ..writeByte(4)
      ..write(obj.proteinG)
      ..writeByte(5)
      ..write(obj.carbsG)
      ..writeByte(6)
      ..write(obj.fatG)
      ..writeByte(7)
      ..write(obj.fiberG)
      ..writeByte(8)
      ..write(obj.waterMl)
      ..writeByte(9)
      ..write(obj.steps)
      ..writeByte(10)
      ..write(obj.sleepHrs)
      ..writeByte(11)
      ..write(obj.weightKg)
      ..writeByte(12)
      ..write(obj.isSynced)
      ..writeByte(13)
      ..write(obj.lastUpdated)
      ..writeByte(14)
      ..write(obj.caloriesBurned)
      ..writeByte(15)
      ..write(obj.sleepQuality)
      ..writeByte(16)
      ..write(obj.sleepInterruptions)
      ..writeByte(17)
      ..write(obj.phonePickups)
      ..writeByte(18)
      ..write(obj.sleepScore)
      ..writeByte(19)
      ..write(obj.sleepStart)
      ..writeByte(20)
      ..write(obj.sleepEnd);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalDailyLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
