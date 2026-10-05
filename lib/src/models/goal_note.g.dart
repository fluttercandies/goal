// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_note.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GoalNoteAdapter extends TypeAdapter<GoalNote> {
  @override
  final typeId = 4;

  @override
  GoalNote read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GoalNote(
      at: fields[0] as DateTime,
      text: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, GoalNote obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.at)
      ..writeByte(1)
      ..write(obj.text);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoalNoteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
