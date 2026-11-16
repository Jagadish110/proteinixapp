// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_meal_routine.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalMealRoutineAdapter extends TypeAdapter<LocalMealRoutine> {
  @override
  final int typeId = 7;

  @override
  LocalMealRoutine read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalMealRoutine(
      id: fields[0] as String,
      userId: fields[1] as String,
      name: fields[2] as String,
      itemsJson: fields[3] as String,
      createdAt: fields[4] as DateTime,
      isSynced: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, LocalMealRoutine obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.itemsJson)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalMealRoutineAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
