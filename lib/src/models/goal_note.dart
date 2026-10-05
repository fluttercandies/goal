import 'package:hive_ce/hive_ce.dart';

part 'goal_note.g.dart';

/// A timestamped remark appended to a ticket. Notes are append-only; they are
/// the free-text settlement channel (files changed, verification commands,
/// evidence paths, revisit conditions, redispatch reasons).
@HiveType(typeId: 4)
class GoalNote {
  const GoalNote({required this.at, required this.text});

  @HiveField(0)
  final DateTime at;

  @HiveField(1)
  final String text;

  GoalNote copyWith({DateTime? at, String? text}) =>
      GoalNote(at: at ?? this.at, text: text ?? this.text);

  @override
  String toString() => '${at.toIso8601String()} $text';
}
