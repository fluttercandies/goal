import 'package:hive_ce/hive_ce.dart';

import 'goal_note.dart';
import 'goal_priority.dart';
import 'goal_status.dart';

part 'goal_entry.g.dart';

/// A single goal ticket. Immutable: every mutation produces a new instance
/// via [copyWith] and is written back with an explicit `put`.
@HiveType(typeId: 1)
class GoalEntry {
  const GoalEntry({
    required this.id,
    required this.status,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.priority,
    this.detail = '',
    this.round = '',
    this.deps = const [],
    this.agent,
    this.notes = const [],
  });

  /// Unique ticket id: auto-increment decimal string ("4196").
  @HiveField(0)
  final String id;

  @HiveField(1)
  final GoalStatus status;

  @HiveField(2)
  final GoalPriority? priority;

  @HiveField(3)
  final String title;

  /// Long-form body: goal, acceptance criteria, background.
  @HiveField(4)
  final String detail;

  /// Round label, e.g. "R798". Grouping only, never parsed.
  @HiveField(5)
  final String round;

  /// Ids of tickets that must reach `done` before this one is ready.
  @HiveField(6)
  final List<String> deps;

  /// Lane owner (agent id) while the ticket is `wip`.
  @HiveField(7)
  final String? agent;

  /// Append-only timestamped remarks.
  @HiveField(8)
  final List<GoalNote> notes;

  @HiveField(9)
  final DateTime createdAt;

  @HiveField(10)
  final DateTime updatedAt;

  GoalEntry copyWith({
    GoalStatus? status,
    GoalPriority? priority,
    bool clearPriority = false,
    String? title,
    String? detail,
    String? round,
    List<String>? deps,
    String? agent,
    bool clearAgent = false,
    List<GoalNote>? notes,
    DateTime? updatedAt,
  }) =>
      GoalEntry(
        id: id,
        status: status ?? this.status,
        priority: priority ?? (clearPriority ? null : this.priority),
        title: title ?? this.title,
        detail: detail ?? this.detail,
        round: round ?? this.round,
        deps: deps ?? this.deps,
        agent: agent ?? (clearAgent ? null : this.agent),
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) => other is GoalEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '#$id [$status] $title';
}
