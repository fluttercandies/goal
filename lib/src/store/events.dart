import 'dart:convert';
import 'dart:io';

/// Append-only JSONL audit journal. One line per mutation; the hive boxes
/// hold current state, this file holds the history and doubles as a
/// human-readable recovery log.
///
/// Writes are best-effort: hive is the source of truth, so a journal failure
/// (disk full, permissions) must never fail an operation whose data write
/// already succeeded — that would make the caller retry and duplicate the
/// ticket. Failures are reported through [onWarn] instead.
class EventJournal {
  EventJournal(this.file, {this.onWarn});

  final File file;
  final void Function(String warning)? onWarn;

  Future<void> append(String op,
      {String? id, Map<String, Object?>? changes}) async {
    try {
      final sink = file.openWrite(mode: FileMode.append);
      try {
        sink.writeln(
          jsonEncode({
            'at': DateTime.now().toIso8601String(),
            'op': op,
            if (id != null) 'id': id,
            if (changes != null && changes.isNotEmpty) 'changes': changes,
          }),
        );
      } finally {
        // close() flushes pending writes and releases the descriptor even
        // when the write failed.
        await sink.close();
      }
    } catch (e) {
      onWarn?.call('audit journal write failed ($e) — ledger state is '
          'correct, the audit trail has a gap');
    }
  }
}
