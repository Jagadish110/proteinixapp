// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_pending_sync.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalPendingSyncAdapter extends TypeAdapter<LocalPendingSync> {
  @override
  final int typeId = 4;

  @override
  LocalPendingSync read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalPendingSync(
      id: fields[0] as String,
      table: fields[1] as String,
      operation: fields[2] as String,
      dataJson: fields[3] as String,
      createdAt: fields[4] as DateTime,
      retryCount: fields[5] as int,
      dedupeKey: fields[6] as String?,
      lastError: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, LocalPendingSync obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.table)
      ..writeByte(2)
      ..write(obj.operation)
      ..writeByte(3)
      ..write(obj.dataJson)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.retryCount)
      ..writeByte(6)
      ..write(obj.dedupeKey)
      ..writeByte(7)
      ..write(obj.lastError);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalPendingSyncAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
