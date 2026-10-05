// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GoalEntryAdapter extends TypeAdapter<GoalEntry> {
  @override
  final typeId = 1;

  @override
  GoalEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GoalEntry(
      id: fields[0] as String,
      status: fields[1] as GoalStatus,
      title: fields[3] as String,
      createdAt: fields[9] as DateTime,
      updatedAt: fields[10] as DateTime,
      priority: fields[2] as GoalPriority?,
      detail: fields[4] == null ? '' : fields[4] as String,
      round: fields[5] == null ? '' : fields[5] as String,
      deps: fields[6] == null ? const [] : (fields[6] as List).cast<String>(),
      agent: fields[7] as String?,
      notes:
          fields[8] == null ? const [] : (fields[8] as List).cast<GoalNote>(),
    );
  }

  @override
  void write(BinaryWriter writer, GoalEntry obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.status)
      ..writeByte(2)
      ..write(obj.priority)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.detail)
      ..writeByte(5)
      ..write(obj.round)
      ..writeByte(6)
      ..write(obj.deps)
      ..writeByte(7)
      ..write(obj.agent)
      ..writeByte(8)
      ..write(obj.notes)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoalEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
