// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_meal.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalMealAdapter extends TypeAdapter<LocalMeal> {
  @override
  final int typeId = 1;

  @override
  LocalMeal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalMeal(
      id: fields[0] as String,
      userId: fields[1] as String,
      date: fields[2] as DateTime,
      mealType: fields[3] as String,
      foodName: fields[4] as String,
      quantity: fields[5] as double?,
      unit: fields[6] as String?,
      calories: fields[7] as int,
      proteinG: fields[8] as double,
      carbsG: fields[9] as double,
      fatG: fields[10] as double,
      fiberG: fields[11] as double,
      logMethod: fields[12] as String,
      isSynced: fields[13] as bool,
      loggedAt: fields[14] as DateTime,
      scanConfidence: fields[15] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, LocalMeal obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.mealType)
      ..writeByte(4)
      ..write(obj.foodName)
      ..writeByte(5)
      ..write(obj.quantity)
      ..writeByte(6)
      ..write(obj.unit)
      ..writeByte(7)
      ..write(obj.calories)
      ..writeByte(8)
      ..write(obj.proteinG)
      ..writeByte(9)
      ..write(obj.carbsG)
      ..writeByte(10)
      ..write(obj.fatG)
      ..writeByte(11)
      ..write(obj.fiberG)
      ..writeByte(12)
      ..write(obj.logMethod)
      ..writeByte(13)
      ..write(obj.isSynced)
      ..writeByte(14)
      ..write(obj.loggedAt)
      ..writeByte(15)
      ..write(obj.scanConfidence);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalMealAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
