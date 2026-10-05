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

String trunc(String s, int n) => s.length <= n ? s : s.substring(0, n);

String cell(String s, int width) => trunc(s, width).padRight(width);

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
String listLine(GoalEntry e, DateTime now) {
  final pri = e.priority?.toString() ?? '-';
  final agent = e.agent == null ? '-' : trunc(e.agent!, 12);
  return '${cell(e.id, 12)}${cell(pri, 3)}${cell(e.status.name, statusColumnWidth)}'
      '${cell(age(e.updatedAt, now), 5)}${cell(agent, 13)}${trunc(e.title, 60)}';
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
