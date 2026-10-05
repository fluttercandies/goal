import 'package:hive_ce/hive_ce.dart';

part 'goal_priority.g.dart';

/// Priority of a goal ticket. `null` means no priority was assigned.
@HiveType(typeId: 3)
enum GoalPriority {
  @HiveField(0)
  p0,

  @HiveField(1)
  p1,

  @HiveField(2)
  p2,

  @HiveField(3)
  p3;

  @override
  String toString() => name.toUpperCase();

  /// Parses `p0`..`p3` (case insensitive, optional leading `-`).
  static GoalPriority? tryParse(String raw) {
    final s = raw.trim().toLowerCase().replaceFirst('-', '');
    for (final v in values) {
      if (s == v.name) return v;
    }
    return null;
  }

  /// Sort rank: lower is more urgent; unassigned sorts last.
  int get rank => index;
}
