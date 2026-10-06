/// Terminal formatting helpers. Everything is plain ASCII so columns never
/// break on double-width glyphs.
library;

import '../models/goal_entry.dart';
import '../models/goal_status.dart';

String age(DateTime at, DateTime now) {
  var d = now.difference(at);
  if (d.isNegative) d = Duration.zero;
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  if (s < 3600) return '${d.inMinutes}m';
  if (s < 86400) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// Truncates by runes so a cut never splits a surrogate pair (an emoji cut
/// in half renders as garbage everywhere).
String trunc(String s, int n) {
  if (s.runes.length <= n) return s;
  return String.fromCharCodes(s.runes.take(n));
}

String cell(String s, int width) => trunc(s, width).padRight(width);

final _ansiRe = RegExp('\x1B\\[[0-9;:?]*[ -/]*[@-~]');
final _ctrlRe = RegExp('[\x00-\x1F\x7F\x80-\x9F]');

/// Single-line projection of arbitrary user text for receipts, table rows
/// and filters: ANSI escapes are removed, every other control character
/// (newlines, tabs, CR) becomes one space, runs of spaces squeeze together.
/// Storage keeps the original verbatim; only the display goes through this.
String oneline(String s) => s
    .replaceAll(_ansiRe, ' ')
    .replaceAll(_ctrlRe, ' ')
    .replaceAll(RegExp(r'  +'), ' ')
    .trim();

/// Splits verbatim text into display lines, tolerating CRLF and lone CR.
List<String> textLines(String s) => s.split(RegExp(r'\r\n|\r|\n'));

String stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

String fullStamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// 8 = len('blocked') + 1 separator so the widest status never jams into
/// the age column.
const statusColumnWidth = 8;

/// One-line table row: id, priority, status, age, agent, truncated title.
/// Title and agent pass through [oneline] so a newline inside them can never
/// break the row structure.
String listLine(GoalEntry e, DateTime now) {
  final pri = e.priority?.toString() ?? '-';
  final agent = e.agent == null ? '-' : trunc(oneline(e.agent!), 12);
  return '${cell(e.id, 12)}${cell(pri, 3)}${cell(e.status.name, statusColumnWidth)}'
      '${cell(age(e.updatedAt, now), 5)}${cell(agent, 13)}${trunc(oneline(e.title), 60)}';
}

const statusViewOrder = [
  GoalStatus.wip,
  GoalStatus.todo,
  GoalStatus.blocked,
  GoalStatus.failed,
  GoalStatus.parked,
  GoalStatus.done,
];

int statusViewRank(GoalStatus s) => statusViewOrder.indexOf(s);

String footerCounts(Map<GoalStatus, int> counts) {
  final parts = statusViewOrder
      .where((s) => counts[s] != null && counts[s]! > 0)
      .map((s) => '${counts[s]} ${s.name}');
  return parts.isEmpty ? '-- 0 tickets' : '-- ${parts.join(' | ')}';
}
