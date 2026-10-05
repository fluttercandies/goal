// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_priority.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GoalPriorityAdapter extends TypeAdapter<GoalPriority> {
  @override
  final typeId = 3;

  @override
  GoalPriority read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return GoalPriority.p0;
      case 1:
        return GoalPriority.p1;
      case 2:
        return GoalPriority.p2;
      case 3:
        return GoalPriority.p3;
      default:
        return GoalPriority.p0;
    }
  }

  @override
  void write(BinaryWriter writer, GoalPriority obj) {
    switch (obj) {
      case GoalPriority.p0:
        writer.writeByte(0);
      case GoalPriority.p1:
        writer.writeByte(1);
      case GoalPriority.p2:
        writer.writeByte(2);
      case GoalPriority.p3:
        writer.writeByte(3);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoalPriorityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
