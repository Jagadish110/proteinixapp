// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_sleep_schedule.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalSleepScheduleAdapter extends TypeAdapter<LocalSleepSchedule> {
  @override
  final int typeId = 5;

  @override
  LocalSleepSchedule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalSleepSchedule(
      id: fields[0] as String,
      userId: fields[1] as String,
      sleepTime: fields[2] as String,
      wakeTime: fields[3] as String,
      isActive: fields[4] as bool,
      isSynced: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, LocalSleepSchedule obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.sleepTime)
      ..writeByte(3)
      ..write(obj.wakeTime)
      ..writeByte(4)
      ..write(obj.isActive)
      ..writeByte(5)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalSleepScheduleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
