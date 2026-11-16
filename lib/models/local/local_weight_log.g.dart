// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_weight_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalWeightLogAdapter extends TypeAdapter<LocalWeightLog> {
  @override
  final int typeId = 3;

  @override
  LocalWeightLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalWeightLog(
      id: fields[0] as String,
      userId: fields[1] as String,
      weightKg: fields[2] as double,
      date: fields[3] as DateTime,
      isSynced: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, LocalWeightLog obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.weightKg)
      ..writeByte(3)
      ..write(obj.date)
      ..writeByte(4)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalWeightLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
