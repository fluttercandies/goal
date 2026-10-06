import 'dart:convert';
import 'dart:io';

import '../models/goal_entry.dart';
import '../models/goal_note.dart';
import '../models/goal_priority.dart';
import '../models/goal_status.dart';
import '../store/goal_store.dart';
import 'format.dart';

const statusWords = 'todo wip done blocked failed parked';

const _flagHint =
    'flags: -p0..-p3 -m <text|-> --deps <a,b> --round <R> --agent <id> '
    '--id <id> -o <file> --json --dry-run';

/// Parses argv into positionals, valued options, bool flags and `-pN`.
class ParsedArgs {
  ParsedArgs(this.positional, this.options, this.bools, this.priority);

  final List<String> positional;
  final Map<String, String> options;
  final Set<String> bools;
  final GoalPriority? priority;

  bool flag(String name) => bools.contains(name);
}

ParsedArgs parseArgs(List<String> args) {
  final pos = <String>[];
  final opts = <String, String>{};
  final bools = <String>{};
  GoalPriority? priority;
  const valued = {'m', 'o', 'agent', 'deps', 'round', 'id'};

  var i = 0;
  var flagsDone = false;
  while (i < args.length) {
    final a = args[i];
    if (flagsDone || !a.startsWith('-') || a == '-') {
      pos.add(a);
    } else if (a == '--') {
      flagsDone = true;
    } else if (a.startsWith('--')) {
      final body = a.substring(2);
      final eq = body.indexOf('=');
      final name = eq == -1 ? body : body.substring(0, eq);
      if (name == 'json' || name == 'dry-run') {
        if (eq != -1) {
          throw GoalError('flag --$name does not take a value. $_flagHint');
        }
        bools.add(name);
      } else if (valued.contains(name)) {
        if (eq != -1) {
          opts[name] = body.substring(eq + 1);
        } else if (i + 1 < args.length) {
          opts[name] = args[++i];
        } else {
          throw GoalError('flag --$name needs a value. $_flagHint');
        }
      } else {
        throw GoalError("unknown flag '$a'. $_flagHint");
      }
    } else if (a.startsWith('-p') && a.length == 3) {
      final p = GoalPriority.tryParse(a);
      if (p == null) {
        throw GoalError("unknown priority '${a.substring(2)}'. use -p0..-p3");
      }
      priority = p;
    } else if (a == '-m' || a == '-o') {
      if (i + 1 < args.length) {
        opts[a.substring(1)] = args[++i];
      } else {
        throw GoalError('flag $a needs a value. $_flagHint');
      }
    } else {
      throw GoalError("unknown flag '$a'. $_flagHint");
    }
    i++;
  }
  return ParsedArgs(pos, opts, bools, priority);
}

List<String> splitIds(String raw) => raw
    .split(',')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toSet() // first occurrence wins; '2,2' must not show dep 2 twice
    .toList();

Future<String> _noteText(
    ParsedArgs p, Future<String> Function() readStdin) async {
  final v = p.options['m'];
  if (v == null) return '';
  if (v == '-') {
    final s = (await readStdin()).trim();
    if (s.isEmpty) {
      throw GoalError('-m - read nothing from stdin. pipe the note in, '
          'e.g. echo "text" | goal set <id> -m -');
    }
    return s;
  }
  if (v.trim().isEmpty) {
    throw GoalError('-m note text is empty. pass text, or - to read stdin');
  }
  return v;
}

/// Runs the CLI and returns the process exit code.
/// [writeln], [clock] and [stdinReader] are injection points for tests.
Future<int> runGoalCli(
  List<String> args, {
  String? home,
  void Function(String line)? writeln,
  void Function(String line)? errln,
  DateTime Function()? clock,
  Future<String> Function()? stdinReader,
}) async {
  final out = writeln ?? print;
  final err = errln ?? stderr.writeln;
  final now = clock ?? DateTime.now;
  final readStdin = stdinReader ?? () => stdin.transform(utf8.decoder).join();
  final ledger = home ?? Platform.environment['GOAL_HOME'] ?? '.goal';
  try {
    return await _dispatch(args, ledger, out, now(), readStdin);
  } on GoalError catch (e) {
    err('goal: ${e.message}');
    return e.code == GoalErrorCode.conflict ? 4 : 2;
  } catch (e) {
    // Unexpected failures (io, decoding) must still honor the 0/2/4 contract.
    err('goal: $e');
    return 2;
  }
}

/// Flags each command actually consumes; anything else is rejected loudly
/// instead of silently dropped (a dropped `--round` would still print "ok").
const _commandFlags = <String, Set<String>>{
  'init': {},
  'add': {'p', 'm', 'round', 'deps'},
  'set': {'p', 'm', 'round', 'deps', 'agent'},
  'list': {'p', 'round', 'id'},
  'ready': {},
  'show': {},
  'render': {'o', 'json'},
  'archive': {'dry-run'},
};

String _flagName(String f) => switch (f) {
      'p' => '-p0..-p3',
      'm' => '-m <text|->',
      'o' => '-o <file>',
      'round' => '--round <R>',
      'deps' => '--deps <a,b>',
      'id' => '--id <id>',
      'agent' => '--agent <id>',
      _ => '--$f',
    };

void _checkFlags(String cmd, ParsedArgs p, Set<String> allowed) {
  final used = <String>{
    if (p.priority != null) 'p',
    ...p.bools,
    ...p.options.keys,
  };
  for (final f in used) {
    if (!allowed.contains(f)) {
      final valid = allowed.map(_flagName).join(' ');
      throw GoalError("flag '${_flagName(f)}' is not valid for goal $cmd. "
          '${valid.isEmpty ? 'it takes no flags' : 'valid: $valid'}');
    }
  }
}

Future<int> _dispatch(
  List<String> args,
  String home,
  void Function(String) out,
  DateTime now,
  Future<String> Function() readStdin,
) async {
  if (args.isEmpty || args.first == 'help' || args.first == '--help') {
    _help(out);
    return 0;
  }
  final cmd = args.first;
  final parsed = parseArgs(args.sublist(1));
  final allowed = _commandFlags[cmd];
  if (allowed != null) _checkFlags(cmd, parsed, allowed);
  switch (cmd) {
    case 'init':
      return _init(home, out);
    case 'add':
      return _withStore(home, out, (s) => _add(s, parsed, out, now, readStdin));
    case 'set':
      return _withStore(home, out, (s) => _set(s, parsed, out, now, readStdin));
    case 'list':
      return _withStore(home, out, (s) => _list(s, parsed, out, now));
    case 'ready':
      return _withStore(home, out, (s) => _ready(s, out, now));
    case 'show':
      return _withStore(home, out, (s) => _show(s, parsed, out, now));
    case 'render':
      return _withStore(home, out, (s) => _render(s, parsed, out, now));
    case 'archive':
      return _withStore(home, out, (s) => _archive(s, parsed, out));
    default:
      out("unknown command '$cmd'");
      _help(out);
      return 2;
  }
}

Future<int> _withStore(
  String home,
  void Function(String) out,
  Future<int> Function(GoalStore) body,
) async {
  final store = await GoalStore.open(home);
  try {
    return await body(store);
  } finally {
    await store.close();
  }
}

Future<int> _init(String home, void Function(String) out) async {
  final store = await GoalStore.open(home, create: true);
  await store.close();
  out('ok ledger at $home');
  return 0;
}

Future<int> _add(
  GoalStore store,
  ParsedArgs p,
  void Function(String) out,
  DateTime now,
  Future<String> Function() readStdin,
) async {
  // Bare words join into one title: an unquoted `goal add two words` must
  // succeed in one shot, not bounce back with a quoting lesson.
  final title = p.positional.join(' ').trim();
  if (oneline(title).isEmpty) {
    throw GoalError(
        'title cannot be empty. goal add <title> [-pN] [--deps a,b] '
        '[--round R] [-m text]');
  }
  final round = p.options['round'];
  if (round != null && round.trim().isEmpty) {
    throw GoalError('--round value is empty. pass e.g. --round R12');
  }
  final entry = await store.add(
    title: title,
    detail: await _noteText(p, readStdin),
    round: round ?? '',
    deps: p.options['deps'] == null ? const [] : splitIds(p.options['deps']!),
    priority: p.priority,
    now: now,
  );
  out('ok #${entry.id} created (todo)'
      '${entry.round.isEmpty ? '' : ' round=${oneline(entry.round)}'} '
      '${oneline(entry.title)}');
  return 0;
}

Future<int> _set(
  GoalStore store,
  ParsedArgs p,
  void Function(String) out,
  DateTime now,
  Future<String> Function() readStdin,
) async {
  if (p.positional.isEmpty) {
    throw GoalError('goal set <id> [status] [note...]  ($_flagHint)');
  }
  final entry = store.resolve(p.positional.first);
  var rest = p.positional.skip(1).toList();

  // Strict status slot: when words follow the id, the first word IS the
  // status. A typo must fail loudly instead of silently becoming a note.
  GoalStatus? status;
  if (rest.isNotEmpty) {
    status = GoalStatus.tryParse(rest.first);
    if (status == null) {
      throw GoalError("'${rest.first}' is not a status. use: $statusWords — "
          'note-only updates: -m "text"');
    }
    rest = rest.skip(1).toList();
  }
  final note = [
    rest.join(' ').trim(),
    await _noteText(p, readStdin),
  ].where((s) => s.isNotEmpty).join(' ');

  final round = p.options['round'];
  if (round != null && round.trim().isEmpty) {
    throw GoalError('--round value is empty. pass e.g. --round R12');
  }
  final changes = <String, Object?>{};
  var next = entry;
  if (status != null && status != entry.status) {
    next = next.copyWith(
      status: status,
      clearAgent: status != GoalStatus.wip,
      updatedAt: now,
    );
    changes['status'] = [entry.status.name, status.name];
  }
  if (note.isNotEmpty) {
    next = next.copyWith(
      notes: [...next.notes, GoalNote(at: now, text: note)],
      updatedAt: now,
    );
    changes['note'] = note;
  }
  final agent = p.options['agent'];
  if (agent != null) {
    next = next.copyWith(agent: agent, updatedAt: now);
    changes['agent'] = agent;
  }
  final deps = p.options['deps'];
  var depIds = const <String>[];
  if (deps != null) {
    depIds = splitIds(deps);
    next = next.copyWith(deps: depIds, updatedAt: now);
    changes['deps'] = depIds;
  }
  if (round != null) {
    next = next.copyWith(round: round, updatedAt: now);
    changes['round'] = round;
  }
  if (p.priority != null) {
    next = next.copyWith(priority: p.priority, updatedAt: now);
    changes['priority'] = p.priority.toString();
  }

  if (identical(next, entry)) {
    await store.put(entry.copyWith(updatedAt: now), changes: {'ping': true});
    // explicit repeat of the current status is an idempotent no-op, not a
    // heartbeat; both are exit 0 so retries never look like failures
    out('ok ${entry.id} ${status == null ? 'ping' : 'already ${entry.status.name}'}');
    return 0;
  }
  await store.put(next, changes: changes);
  final head = changes.containsKey('status')
      ? '${entry.status.name} -> ${next.status.name}'
      : status != null
          ? 'already ${entry.status.name}'
          : 'updated';
  // The receipt states every changed field with its new value, so the caller
  // never needs a second command to verify what happened.
  final extras = <String>[
    if (note.isNotEmpty) 'note=${_shown(note)}',
    if (changes.containsKey('agent')) 'agent=${oneline(agent!)}',
    if (changes.containsKey('deps')) 'deps=${depIds.join(',')}',
    if (changes.containsKey('round')) 'round=${oneline(round!)}',
    if (changes.containsKey('priority')) 'pri=${p.priority}',
  ];
  out('ok ${entry.id} $head'
      "${extras.isEmpty ? '' : ' +${extras.join(' +')}'}");
  return 0;
}

/// Receipt-safe rendering of free text: one line, quoted, capped hard so a
/// paragraph-sized note cannot bloat the receipt.
String _shown(String s) => '"${trunc(oneline(s), 40)}"';

Future<int> _list(
  GoalStore store,
  ParsedArgs p,
  void Function(String) out,
  DateTime now,
) async {
  GoalStatus? status;
  // Flag forms of the filters (-pN/--round/--id) are honored, not dropped.
  GoalPriority? priority = p.priority;
  String? round = p.options['round']?.toLowerCase();
  final ids = splitIds(p.options['id'] ?? '').toSet();
  final titleSubs = <String>[];
  final rounds = store.all.map((e) => e.round.toLowerCase()).toSet();
  for (final token in p.positional) {
    final s = GoalStatus.tryParse(token);
    if (s != null) {
      if (status != null) throw GoalError('only one status filter allowed');
      status = s;
      continue;
    }
    final pr = GoalPriority.tryParse(token);
    if (pr != null) {
      if (priority != null) throw GoalError('only one priority filter allowed');
      priority = pr;
      continue;
    }
    final t = token.startsWith('#') ? token.substring(1) : token;
    if (t != token || RegExp(r'^\d+$').hasMatch(t)) {
      ids.add(t);
      continue;
    }
    final lower = token.toLowerCase();
    if (RegExp(r'^r\d+$').hasMatch(lower) || rounds.contains(lower)) {
      if (round != null) throw GoalError('only one round filter allowed');
      round = lower;
      continue;
    }
    titleSubs.add(lower);
  }

  final entries = store.all.where((e) {
    if (status != null && e.status != status) return false;
    if (priority != null && e.priority != priority) return false;
    if (round != null && e.round.toLowerCase() != round) return false;
    if (ids.isNotEmpty && !ids.contains(e.id)) return false;
    // Search both the raw title and its one-line projection, so `list two`
    // still finds a title stored as `two\nwords`.
    final title = e.title.toLowerCase();
    final flat = oneline(e.title).toLowerCase();
    return titleSubs.every((s) => title.contains(s) || flat.contains(s));
  }).toList()
    ..sort((a, b) {
      final s = statusViewRank(a.status).compareTo(statusViewRank(b.status));
      if (s != 0) return s;
      final p = (a.priority?.rank ?? 9).compareTo(b.priority?.rank ?? 9);
      return p != 0 ? p : a.updatedAt.compareTo(b.updatedAt);
    });

  final filtered = status != null ||
      priority != null ||
      round != null ||
      ids.isNotEmpty ||
      titleSubs.isNotEmpty;
  if (entries.isEmpty && filtered) out('no matches.');
  for (final e in entries) {
    out(listLine(e, now));
  }
  out(footerCounts(store.statusCounts()));
  return 0;
}

Future<int> _ready(
  GoalStore store,
  void Function(String) out,
  DateTime now,
) async {
  final missing = <String>{};
  final list = store.ready(missingDeps: missing);
  for (final e in list) {
    out(listLine(e, now));
  }
  if (missing.isNotEmpty) {
    out('! unknown deps (treated as satisfied): '
        '${missing.map(oneline).join(' ')}');
  }
  out('-- ${list.length} ready');
  return 0;
}

Future<int> _show(
  GoalStore store,
  ParsedArgs p,
  void Function(String) out,
  DateTime now,
) async {
  if (p.positional.isEmpty) throw GoalError('goal show <id>');
  final e = store.resolve(p.positional.first);
  final tags = [
    e.status.name,
    if (e.priority != null) e.priority.toString(),
    if (e.round.isNotEmpty) oneline(e.round),
  ];
  out('#${e.id} [${tags.join('] [')}]');
  // Verbatim view: a multiline title keeps its lines, each indented.
  for (final line in textLines(e.title)) {
    out('  $line');
  }
  out('  agent: ${e.agent == null ? '-' : oneline(e.agent!)}');
  final deps = e.deps.map((d) {
    final t = store.get(d);
    final state = t == null
        ? (store.isArchived(d) ? 'archived' : 'missing')
        : t.status.name;
    return '${oneline(d)} ($state)';
  });
  out('  deps: ${e.deps.isEmpty ? '-' : deps.join(', ')}');
  out('  created: ${fullStamp(e.createdAt)}  '
      'updated: ${fullStamp(e.updatedAt)} (${age(e.updatedAt, now)} ago)');
  if (e.detail.isEmpty) {
    out('  detail: -');
  } else {
    out('  detail:');
    for (final line in textLines(e.detail)) {
      out('    $line');
    }
  }
  out('  notes:');
  // Continuation lines align under the text, after '    [MM-DD HH:mm] '.
  for (final n in e.notes) {
    final lines = textLines(n.text);
    out('    [${stamp(n.at)}] ${lines.first}');
    final pad = ' ' * ('    ['.length + stamp(n.at).length + '] '.length);
    for (final line in lines.skip(1)) {
      out('$pad$line');
    }
  }
  return 0;
}

Future<int> _render(
  GoalStore store,
  ParsedArgs p,
  void Function(String) out,
  DateTime now,
) async {
  final json = p.flag('json');
  final target = p.options['o'];
  final content = json
      ? const JsonEncoder.withIndent('  ').convert({
          'meta': {
            'nextId': store.meta.nextId,
            'currentRound': store.meta.currentRound,
            'schemaVersion': store.meta.schemaVersion,
          },
          'goals': [for (final e in store.all) _entryJson(e)],
        })
      : _markdown(store, now);
  if (target == null) {
    out(content);
  } else {
    await File(target).writeAsString('$content\n');
    out('ok wrote $target');
  }
  return 0;
}

Map<String, Object?> _entryJson(GoalEntry e) => {
      'id': e.id,
      'status': e.status.name,
      'priority': e.priority?.name,
      'title': e.title,
      'detail': e.detail,
      'round': e.round,
      'deps': e.deps,
      'agent': e.agent,
      'notes': [
        for (final n in e.notes) {'at': n.at.toIso8601String(), 'text': n.text},
      ],
      'createdAt': e.createdAt.toIso8601String(),
      'updatedAt': e.updatedAt.toIso8601String(),
    };

String _markdown(GoalStore store, DateTime now) {
  final buf = StringBuffer('# Goals — rendered ${fullStamp(now)}');
  for (final s in [
    GoalStatus.wip,
    GoalStatus.todo,
    GoalStatus.blocked,
    GoalStatus.failed,
    GoalStatus.parked
  ]) {
    final group = store.all.where((e) => e.status == s).toList()
      ..sort(
          (a, b) => (a.priority?.rank ?? 9).compareTo(b.priority?.rank ?? 9));
    if (group.isEmpty) continue;
    buf.writeln('\n## ${s.emoji} ${s.name} (${group.length})');
    for (final e in group) {
      final pri = e.priority == null ? '' : ' [${e.priority}]';
      final agent = e.agent == null
          ? ''
          : ' — ${oneline(e.agent!)}, ${age(e.updatedAt, now)}';
      // Continuation lines are indented into the bullet, so a multiline
      // title can never forge a new top-level item or heading.
      final title = textLines(e.title).join('\n  ');
      buf.writeln('- **#${e.id}**$pri $title$agent');
      for (final n in e.notes) {
        buf.writeln('  - [${stamp(n.at)}] ${textLines(n.text).join('\n    ')}');
      }
    }
  }
  return buf.toString();
}

Future<int> _archive(
  GoalStore store,
  ParsedArgs p,
  void Function(String) out,
) async {
  if (p.flag('dry-run')) {
    final done = store.all
        .where((e) => e.status == GoalStatus.done)
        .map((e) => e.id)
        .toList();
    out(done.isEmpty
        ? 'nothing to archive.'
        : 'would archive ${done.length}: ${done.join(' ')}');
    return 0;
  }
  final moved = await store.archiveDone();
  out(moved.isEmpty
      ? 'nothing to archive.'
      : 'ok archived ${moved.length}: ${moved.map((e) => e.id).join(' ')}');
  return 0;
}

void _help(void Function(String) out) {
  String flags(String cmd) => _commandFlags[cmd]!.map(_flagName).join(' ');
  out('goal — AI-first goal ledger');
  out('');
  out('  goal init                        create ledger in ./.goal');
  out('  goal add <title> ${flags('add')}');
  out('  goal set <id> [status] [note...] status: $statusWords');
  out('                                   ${flags('set')}');
  out('                                   no args after id = heartbeat ping');
  out('  goal list [filters]              filters: status/round/priority/id/title');
  out('                                   words, or ${flags('list')}');
  out('  goal ready                       tickets whose deps are all done');
  out('  goal show <id>                   full ticket');
  out('  goal render [-o file] [--json]   markdown view / json backup');
  out('  goal archive [--dry-run]         move done tickets to archive');
  out('');
  out('exit codes: 0 ok | 2 not-found/usage/busy | 4 dependency cycle');
}
