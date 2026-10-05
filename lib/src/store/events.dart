import 'dart:convert';
import 'dart:io';

/// Append-only JSONL audit journal. One line per mutation; the hive boxes
/// hold current state, this file holds the history and doubles as a
/// human-readable recovery log.
class EventJournal {
  EventJournal(this.file);

  final File file;

  Future<void> append(String op,
      {String? id, Map<String, Object?>? changes}) async {
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
  }
}
