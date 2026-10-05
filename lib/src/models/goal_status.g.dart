// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_status.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GoalStatusAdapter extends TypeAdapter<GoalStatus> {
  @override
  final typeId = 2;

  @override
  GoalStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return GoalStatus.todo;
      case 1:
        return GoalStatus.wip;
      case 2:
        return GoalStatus.done;
      case 3:
        return GoalStatus.blocked;
      case 4:
        return GoalStatus.failed;
      case 5:
        return GoalStatus.parked;
      default:
        return GoalStatus.todo;
    }
  }

  @override
  void write(BinaryWriter writer, GoalStatus obj) {
    switch (obj) {
      case GoalStatus.todo:
        writer.writeByte(0);
      case GoalStatus.wip:
        writer.writeByte(1);
      case GoalStatus.done:
        writer.writeByte(2);
      case GoalStatus.blocked:
        writer.writeByte(3);
      case GoalStatus.failed:
        writer.writeByte(4);
      case GoalStatus.parked:
        writer.writeByte(5);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoalStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
