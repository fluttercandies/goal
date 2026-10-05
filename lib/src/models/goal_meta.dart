import 'package:hive_ce/hive_ce.dart';

part 'goal_meta.g.dart';

/// Ledger-wide metadata, stored as the single `meta` record of the meta box.
@HiveType(typeId: 5)
class GoalMeta {
  const GoalMeta({
    required this.nextId,
    required this.schemaVersion,
    this.currentRound = '',
  });

  /// Next auto-increment id. Monotonic across archives: never reset.
  @HiveField(0)
  final int nextId;

  /// Round label applied to new tickets when `--round` is omitted.
  @HiveField(1)
  final String currentRound;

  /// Storage schema version for future migrations.
  @HiveField(2)
  final int schemaVersion;

  GoalMeta copyWith({int? nextId, String? currentRound, int? schemaVersion}) =>
      GoalMeta(
        nextId: nextId ?? this.nextId,
        currentRound: currentRound ?? this.currentRound,
        schemaVersion: schemaVersion ?? this.schemaVersion,
      );

  static const schemaVersionNow = 1;
}
