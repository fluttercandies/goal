import 'package:hive_ce/hive_ce.dart';

part 'goal_status.g.dart';

/// Lifecycle state of a goal ticket.
///
/// Canonical words are used on the command line and in storage; emoji are a
/// presentation concern of `goal render` only.
@HiveType(typeId: 2)
enum GoalStatus {
  @HiveField(0)
  todo,

  @HiveField(1)
  wip,

  @HiveField(2)
  done,

  @HiveField(3)
  blocked,

  @HiveField(4)
  failed,

  @HiveField(5)
  parked;

  /// Emoji rendering used by `goal render` output only.
  String get emoji => switch (this) {
        todo => '⬜',
        wip => '🚧',
        done => '✅',
        blocked => '⛔',
        failed => '❌',
        parked => '📦',
      };

  @override
  String toString() => name;

  /// Parses a status from user input. Accepts canonical names (case
  /// insensitive) and the emoji aliases used by the legacy markdown ledger.
  static GoalStatus? tryParse(String raw) {
    final s = raw.trim().toLowerCase();
    for (final v in values) {
      if (s == v.name) return v;
    }
    return switch (s) {
      '⬜' => todo,
      '🚧' => wip,
      '✅' => done,
      '⛔' => blocked,
      '❌' => failed,
      '📦' => parked,
      'open' => todo,
      'complete' || 'completed' => done,
      'fail' => failed,
      'park' => parked,
      'block' => blocked,
      _ => null,
    };
  }
}
