// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_meta.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GoalMetaAdapter extends TypeAdapter<GoalMeta> {
  @override
  final typeId = 5;

  @override
  GoalMeta read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GoalMeta(
      nextId: (fields[0] as num).toInt(),
      schemaVersion: (fields[2] as num).toInt(),
      currentRound: fields[1] == null ? '' : fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, GoalMeta obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.nextId)
      ..writeByte(1)
      ..write(obj.currentRound)
      ..writeByte(2)
      ..write(obj.schemaVersion);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoalMetaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
