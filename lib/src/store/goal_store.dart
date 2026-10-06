import 'dart:io';

import 'package:hive_ce/hive_ce.dart';

import '../../hive_registrar.g.dart';
import '../models/goal_entry.dart';
import '../models/goal_meta.dart';
import '../models/goal_priority.dart';
import '../models/goal_status.dart';
import 'events.dart';

/// Error carrying a CLI-facing exit code.
class GoalError implements Exception {
  GoalError(this.message, {this.code = GoalErrorCode.usage});

  final String message;
  final GoalErrorCode code;
}

enum GoalErrorCode { usage, notFound, conflict, busy }

/// A ticket located anywhere in the ledger.
typedef ArchivedRef = ({GoalEntry entry, bool archived});

/// Hive-backed ledger: `goals` (active) + `archive` + `meta` boxes plus an
/// append-only JSONL journal in the same directory.
class GoalStore {
  GoalStore._(this.home, this.goals, this.archive, this.metaBox, this.journal);

  static const _goalsBox = 'goals';
  static const _archiveBox = 'archive';
  static const _metaBox = 'meta';
  static const _metaKey = 'meta';

  static bool _adaptersRegistered = false;

  final String home;
  final Box<GoalEntry> goals;
  final Box<GoalEntry> archive;
  final Box<GoalMeta> metaBox;
  final EventJournal journal;

  static bool existsAt(String home) =>
      File('$home/$_metaBox.hive').existsSync() ||
      File('$home/$_goalsBox.hive').existsSync();

  /// Opens the ledger at [home]. When [create] is false and no ledger exists
  /// there, throws [GoalError] — never silently forks a new empty ledger.
  /// [onJournalWarning] receives audit-journal write failures: the hive
  /// state is authoritative, so a journal gap must degrade to a warning,
  /// never fail an operation whose data write already succeeded.
  static Future<GoalStore> open(String home,
      {bool create = false,
      void Function(String warning)? onJournalWarning}) async {
    final dir = Directory(home);
    final exists = existsAt(home);
    if (!exists && !create) {
      throw GoalError('no ledger here ($home). run: goal init',
          code: GoalErrorCode.notFound);
    }
    if (exists && create) {
      throw GoalError('ledger already exists at $home',
          code: GoalErrorCode.usage);
    }
    if (!exists) {
      dir.createSync(recursive: true);
    }
    _registerAdapters();
    Box<GoalEntry>? goals;
    Box<GoalEntry>? archive;
    Box<GoalMeta>? metaBox;
    try {
      goals = await Hive.openBox<GoalEntry>(_goalsBox, path: home);
      archive = await Hive.openBox<GoalEntry>(_archiveBox, path: home);
      metaBox = await Hive.openBox<GoalMeta>(_metaBox, path: home);
      if (create) {
        await metaBox.put(
            _metaKey,
            const GoalMeta(
                nextId: 1, schemaVersion: GoalMeta.schemaVersionNow));
      }
    } catch (e) {
      // Never leak half-open boxes: a leaked box keeps the name registered
      // in this isolate and the next open of that name would silently hit
      // the stale backend.
      await goals?.close();
      await archive?.close();
      await metaBox?.close();
      throw GoalError(
          'cannot open ledger at $home ($e). '
          'If another goal process is running, wait and retry.',
          code: GoalErrorCode.busy);
    }
    if (metaBox.get(_metaKey) == null) {
      // Torn init: box files exist but the meta record was never written.
      await goals.close();
      await archive.close();
      await metaBox.close();
      throw GoalError(
          'ledger at $home is missing its meta record (interrupted init). '
          'delete $home and run: goal init',
          code: GoalErrorCode.usage);
    }
    final store = GoalStore._(
      home,
      goals,
      archive,
      metaBox,
      EventJournal(File('$home/events.jsonl'), onWarn: onJournalWarning),
    );
    if (create) await store.journal.append('init');
    return store;
  }

  static void _registerAdapters() {
    if (_adaptersRegistered) return;
    // hive_registrar.g.dart is the generator-maintained single source of
    // truth for the adapter list.
    Hive.registerAdapters();
    _adaptersRegistered = true;
  }

  GoalMeta get meta => metaBox.get(_metaKey)!;

  Future<void> _saveMeta(GoalMeta m) => metaBox.put(_metaKey, m);

  /// Active entries ordered by creation time.
  List<GoalEntry> get all {
    final list = goals.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  GoalEntry? get(String id) => goals.get(id);

  bool isArchived(String id) => archive.containsKey(id);

  /// Resolves a ticket by its exact id. Misses are hard errors that list
  /// recent ids so the caller can self-correct.
  GoalEntry resolve(String input) {
    final exact = goals.get(input);
    if (exact != null) return exact;
    if (archive.containsKey(input)) {
      throw GoalError(
        "'$input' is archived. archived tickets are read-only",
        code: GoalErrorCode.notFound,
      );
    }
    final nearest = all..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    throw GoalError(
      "no ticket '$input'. recent ids: "
      '${nearest.take(5).map((e) => e.id).join(' ')}',
      code: GoalErrorCode.notFound,
    );
  }

  /// Resolves a ticket anywhere in the ledger (active or archived) for
  /// read-only views; archived entries carry [ArchivedRef.archived] so the
  /// caller can label them.
  ArchivedRef resolveAny(String input) {
    final active = goals.get(input);
    if (active != null) return (entry: active, archived: false);
    final archived = archive.get(input);
    if (archived != null) return (entry: archived, archived: true);
    final nearest = all..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    throw GoalError(
        "no ticket '$input'. recent ids: "
        '${nearest.take(5).map((e) => e.id).join(' ')}',
        code: GoalErrorCode.notFound);
  }

  /// Archived entries ordered by creation time — the read-only history.
  List<GoalEntry> get archivedAll {
    final list = archive.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// Deletes an active ticket. Removal is journaled; archived tickets are
  /// read-only and ids of removed tickets are never reused.
  Future<GoalEntry> remove(String id) async {
    final entry = resolve(id);
    await goals.delete(entry.id);
    await journal.append('rm', id: entry.id);
    return entry;
  }

  /// Creates a ticket with the next auto-increment id.
  Future<GoalEntry> add({
    required String title,
    String detail = '',
    String round = '',
    List<String> deps = const [],
    GoalPriority? priority,
    required DateTime now,
  }) async {
    if (title.trim().isEmpty) {
      throw GoalError('title cannot be empty. pass the title as one argument');
    }
    var meta = this.meta;
    // Defensive: skip ids already claimed (only possible after an
    // interrupted init) so allocation never overwrites an existing ticket.
    var next = meta.nextId;
    while (goals.containsKey('$next') || archive.containsKey('$next')) {
      next++;
    }
    final ticketId = '$next';
    meta = meta.copyWith(nextId: next + 1);
    final entry = GoalEntry(
      id: ticketId,
      status: GoalStatus.todo,
      priority: priority,
      title: title,
      detail: detail,
      // inherit the current round unless the caller sets one explicitly
      round: round.isNotEmpty ? round : meta.currentRound,
      deps: List.of(deps),
      createdAt: now,
      updatedAt: now,
    );
    _assertNoCycle(entry);
    await goals.put(ticketId, entry);
    if (round.isNotEmpty) {
      meta = meta.copyWith(currentRound: round);
    }
    await _saveMeta(meta);
    await journal.append('add', id: ticketId);
    return entry;
  }

  /// Writes an updated entry and journals the diff.
  Future<void> put(GoalEntry entry, {Map<String, Object?>? changes}) async {
    _assertNoCycle(entry);
    await goals.put(entry.id, entry);
    await journal.append('set', id: entry.id, changes: changes);
  }

  /// Moves every active `done` ticket into the archive box.
  Future<List<GoalEntry>> archiveDone() async {
    final done =
        goals.values.where((e) => e.status == GoalStatus.done).toList();
    for (final e in done) {
      await archive.put(e.id, e);
      await goals.delete(e.id);
    }
    if (done.isNotEmpty) {
      await journal
          .append('archive', changes: {'ids': done.map((e) => e.id).toList()});
    }
    return done;
  }

  /// Tickets whose deps are all satisfied. Deps pointing at archived tickets
  /// count as satisfied; deps pointing at unknown ids are reported in
  /// [missingDeps] and treated as satisfied (a nonexistent ticket must not
  /// block forever).
  List<GoalEntry> ready({Set<String>? missingDeps}) {
    final byId = {for (final e in all) e.id: e};
    return all.where((e) {
      if (e.status != GoalStatus.todo) return false;
      for (final dep in e.deps) {
        final target = byId[dep];
        if (target != null) {
          if (target.status != GoalStatus.done) return false;
        } else if (!archive.containsKey(dep)) {
          missingDeps?.add(dep);
        }
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final p = (a.priority?.rank ?? 9).compareTo(b.priority?.rank ?? 9);
        return p != 0 ? p : a.updatedAt.compareTo(b.updatedAt);
      });
  }

  /// Throws [GoalError] (conflict) when [entry]'s dependency graph contains a
  /// cycle; the message carries the cycle path.
  void _assertNoCycle(GoalEntry entry) {
    final byId = {for (final e in all) e.id: e};
    byId[entry.id] = entry;
    final visiting = <String>[];
    final visited = <String>{};

    List<String>? walk(String id) {
      if (visited.contains(id)) return null;
      if (visiting.contains(id)) {
        return [...visiting.sublist(visiting.indexOf(id)), id];
      }
      final node = byId[id];
      if (node == null) return null;
      visiting.add(id);
      for (final dep in node.deps) {
        final cycle = walk(dep);
        if (cycle != null) return cycle;
      }
      visiting.removeLast();
      visited.add(id);
      return null;
    }

    final cycle = walk(entry.id);
    if (cycle != null) {
      throw GoalError('dependency cycle: ${cycle.join(' -> ')}',
          code: GoalErrorCode.conflict);
    }
  }

  Map<GoalStatus, int> statusCounts() {
    final counts = {for (final s in GoalStatus.values) s: 0};
    for (final e in all) {
      counts[e.status] = counts[e.status]! + 1;
    }
    return counts;
  }

  /// Idempotent: closing twice is safe, so callers can always register this
  /// as a teardown even after explicit closes.
  Future<void> close() async {
    if (goals.isOpen) await goals.close();
    if (archive.isOpen) await archive.close();
    if (metaBox.isOpen) await metaBox.close();
  }
}
