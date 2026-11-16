// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_blocked_app.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalBlockedAppAdapter extends TypeAdapter<LocalBlockedApp> {
  @override
  final int typeId = 6;

  @override
  LocalBlockedApp read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalBlockedApp(
      id: fields[0] as String,
      userId: fields[1] as String,
      packageName: fields[2] as String,
      appName: fields[3] as String,
      isSynced: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, LocalBlockedApp obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.packageName)
      ..writeByte(3)
      ..write(obj.appName)
      ..writeByte(4)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalBlockedAppAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
