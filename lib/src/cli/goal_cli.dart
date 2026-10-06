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
    'flags: -p0..-p3 -m <text|-> --title <text> --detail <text|-> '
    '--deps <a,b> --round <R> --agent <id> --clear <fields> '
    '-o <file> --json --dry-run';

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
  const valued = {
    'm',
    'o',
    'agent',
    'deps',
    'round',
    'id',
    'title',
    'detail',
    'clear'
  };

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
    // ASCII, full-width and ideographic separators, plus whitespace — a
    // pasted `1，2` or `1 2` must parse, not warn as one unknown dep.
    .split(RegExp(r'[,，、;；\s]+'))
    .map(bareId)
    .where((s) => s.isNotEmpty)
    .toSet() // first occurrence wins; '2,2' must not show dep 2 twice
    .toList();

/// Reads a valued text option (-m/--title/--detail): absent = '', '-' reads
/// stdin, blank or control-only values fail loudly with the flag's name so
/// the caller can retry once with real content.
Future<String> _optionText(ParsedArgs p, String key, String label,
    Future<String> Function() readStdin) async {
  final v = p.options[key];
  if (v == null) return '';
  if (v == '-') {
    final s = (await readStdin()).trim();
    if (s.isEmpty) {
      throw GoalError('$label - read nothing from stdin. pipe the text in, '
          'e.g. echo "text" | goal set <id> $label -');
    }
    return s;
  }
  if (oneline(v).isEmpty) {
    throw GoalError('$label value is empty. pass text, or - to read stdin');
  }
  return v;
}

Future<String> _noteText(ParsedArgs p, Future<String> Function() readStdin) =>
    _optionText(p, 'm', '-m', readStdin);

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
  final void Function(String) err = errln ?? stderr.writeln;
  final now = clock ?? DateTime.now;
  final readStdin = stdinReader ?? () => stdin.transform(utf8.decoder).join();
  final ledger = home ?? Platform.environment['GOAL_HOME'] ?? '.goal';
  try {
    return await _dispatch(args, ledger, out, err, now(), readStdin);
  } on GoalError catch (e) {
    err('goal: ${e.message}');
    return e.code == GoalErrorCode.conflict ? 4 : 2;
  } on FormatException catch (e) {
    // Piped stdin must be UTF-8; without this branch a stray invalid byte
    // surfaces as an opaque decoder error instead of an actionable one.
    err('goal: piped input is not valid UTF-8 (${e.message.trim()}). '
        're-send the text encoded as UTF-8');
    return 2;
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
  'set': {'p', 'm', 'round', 'deps', 'agent', 'title', 'detail', 'clear'},
  'list': {'p', 'round', 'id'},
  'ready': {},
  'show': {},
  'render': {'o', 'json'},
  'archive': {'dry-run'},
  'rm': {},
};

String _flagName(String f) => switch (f) {
      'p' => '-p0..-p3',
      'm' => '-m <text|->',
      'o' => '-o <file>',
      'round' => '--round <R>',
      'deps' => '--deps <a,b>',
      'id' => '--id <id>',
      'agent' => '--agent <id>',
      'clear' => '--clear <agent|pri|round|deps>',
      'title' => '--title <text|->',
      'detail' => '--detail <text|->',
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
  void Function(String) err,
  DateTime now,
  Future<String> Function() readStdin,
) async {
  if (args.isEmpty ||
      args.first == 'help' ||
      args.first == '--help' ||
      args.first == '-h') {
    _help(out);
    return 0;
  }
  // help works anywhere: `goal set --help` must teach, not fail.
  if (args.skip(1).contains('--help') || args.skip(1).contains('-h')) {
    _help(out);
    return 0;
  }
  final cmd = args.first;
  final parsed = parseArgs(args.sublist(1));
  final allowed = _commandFlags[cmd];
  if (allowed != null) _checkFlags(cmd, parsed, allowed);
  // Junk positionals must fail loudly, never drop silently — `goal ready now`
  // succeeding would hide that "now" meant nothing.
  switch (cmd) {
    case 'init' || 'ready' || 'render' || 'archive':
      if (parsed.positional.isNotEmpty) {
        throw GoalError("unexpected '${parsed.positional.first}'. "
            'goal $cmd takes no arguments');
      }
    case 'show':
      if (parsed.positional.length > 1) {
        throw GoalError("unexpected '${parsed.positional[1]}'. "
            'goal show takes exactly one id');
      }
  }
  switch (cmd) {
    case 'init':
      return _init(home, out, err);
    case 'add':
      return _withStore(
          home, out, err, (s) => _add(s, parsed, out, now, readStdin));
    case 'set':
      return _withStore(
          home, out, err, (s) => _set(s, parsed, out, now, readStdin));
    case 'list':
      return _withStore(home, out, err, (s) => _list(s, parsed, out, now));
    case 'ready':
      return _withStore(home, out, err, (s) => _ready(s, out, now));
    case 'show':
      return _withStore(home, out, err, (s) => _show(s, parsed, out, now));
    case 'render':
      return _withStore(home, out, err, (s) => _render(s, parsed, out, now));
    case 'archive':
      return _withStore(home, out, err, (s) => _archive(s, parsed, out));
    case 'rm':
      return _withStore(home, out, err, (s) => _rm(s, parsed, out));
    default:
      out("unknown command '$cmd'");
      _help(out);
      return 2;
  }
}

Future<int> _withStore(
  String home,
  void Function(String) out,
  void Function(String) err,
  Future<int> Function(GoalStore) body,
) async {
  final store = await GoalStore.open(home,
      onJournalWarning: (String w) => err('goal: $w'));
  try {
    return await body(store);
  } finally {
    await store.close();
  }
}

Future<int> _init(
    String home, void Function(String) out, void Function(String) err) async {
  final store = await GoalStore.open(home,
      create: true, onJournalWarning: (String w) => err('goal: $w'));
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
  final depIds = p.options['deps'] == null
      ? const <String>[]
      : splitIds(p.options['deps']!);
  _warnUnknownDeps(store, depIds, out);
  final entry = await store.add(
    title: title,
    detail: await _noteText(p, readStdin),
    round: round ?? '',
    deps: depIds,
    priority: p.priority,
    now: now,
  );
  out('ok #${entry.id} created (todo)'
      '${entry.round.isEmpty ? '' : ' round=${oneline(entry.round)}'}'
      '${depIds.isEmpty ? '' : ' +deps=${depIds.join(',')}'} '
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
    throw GoalError(
        '--round value is empty. pass e.g. --round R12, or --clear round');
  }

  // Clearing is an explicit, dedicated mechanism: an empty --agent/--deps
  // value is far more likely a variable-expansion bug than intent, so it
  // fails with a tutorial pointing here instead of silently mutating.
  const clearable = {'agent', 'pri', 'round', 'deps'};
  final clearFields = <String>{};
  final clearRaw = p.options['clear'];
  if (clearRaw != null) {
    clearFields.addAll(splitIds(clearRaw));
    if (clearFields.isEmpty) {
      throw GoalError('--clear value is empty. clearable fields: '
          '${clearable.join(' ')}');
    }
    for (final f in clearFields) {
      if (!clearable.contains(f)) {
        throw GoalError("cannot clear '$f'. clearable fields: "
            '${clearable.join(' ')}');
      }
    }
    // set and clear on the same field in one command is a contradiction;
    // silent precedence would hide the mistake
    if (clearFields.contains('agent') && p.options['agent'] != null) {
      throw GoalError('cannot set and clear agent in one command');
    }
    if (clearFields.contains('pri') && p.priority != null) {
      throw GoalError('cannot set and clear pri in one command');
    }
    if (clearFields.contains('round') && round != null) {
      throw GoalError('cannot set and clear round in one command');
    }
    if (clearFields.contains('deps') && p.options['deps'] != null) {
      throw GoalError('cannot set and clear deps in one command');
    }
  }

  final newTitle = await _optionText(p, 'title', '--title', readStdin);
  final newDetail = await _optionText(p, 'detail', '--detail', readStdin);
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
    if (oneline(agent).isEmpty) {
      throw GoalError('--agent value is empty. pass an agent id, or release '
          'the lane with: goal set <id> --clear agent');
    }
    if (agent.trim() == '-') {
      throw GoalError("--agent takes an agent id, not '-'. to release the "
          'lane: goal set <id> --clear agent');
    }
    next = next.copyWith(agent: agent, updatedAt: now);
    changes['agent'] = agent;
  }
  final deps = p.options['deps'];
  var depIds = const <String>[];
  if (deps != null) {
    depIds = splitIds(deps);
    if (depIds.isEmpty) {
      throw GoalError('--deps value is empty. pass ids like --deps 1,2, or '
          'drop dependencies with: goal set <id> --clear deps');
    }
    _warnUnknownDeps(store, depIds, out);
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
  // Fields already empty record no change, so an idempotent `--clear` falls
  // through to the ping path instead of reporting a no-op as an update.
  final cleared = <String>[];
  if (clearFields.contains('agent') && next.agent != null) {
    next = next.copyWith(clearAgent: true, updatedAt: now);
    cleared.add('agent');
  }
  if (clearFields.contains('pri') && next.priority != null) {
    next = next.copyWith(clearPriority: true, updatedAt: now);
    cleared.add('pri');
  }
  if (clearFields.contains('round') && next.round.isNotEmpty) {
    next = next.copyWith(round: '', updatedAt: now);
    cleared.add('round');
  }
  if (clearFields.contains('deps') && next.deps.isNotEmpty) {
    next = next.copyWith(deps: const [], updatedAt: now);
    cleared.add('deps');
  }
  if (cleared.isNotEmpty) changes['cleared'] = cleared.join(',');
  if (newTitle.isNotEmpty) {
    next = next.copyWith(title: newTitle, updatedAt: now);
    changes['title'] = newTitle;
  }
  if (newDetail.isNotEmpty) {
    next = next.copyWith(detail: newDetail, updatedAt: now);
    changes['detail'] = newDetail;
  }

  if (identical(next, entry)) {
    await store.put(entry.copyWith(updatedAt: now), changes: {'ping': true});
    // explicit repeat of the current status is an idempotent no-op, not a
    // heartbeat; both are exit 0 so retries never look like failures
    out('ok #${entry.id} '
        '${status == null ? 'ping' : 'already ${entry.status.name}'}');
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
    if (changes.containsKey('title')) 'title=${_shown(newTitle)}',
    if (changes.containsKey('detail')) 'detail=${_shown(newDetail)}',
    if (note.isNotEmpty) 'note=${_shown(note)}',
    if (changes.containsKey('agent')) 'agent=${oneline(agent!)}',
    if (changes.containsKey('deps')) 'deps=${depIds.join(',')}',
    if (changes.containsKey('round')) 'round=${oneline(round!)}',
    if (changes.containsKey('priority')) 'pri=${p.priority}',
    if (cleared.isNotEmpty) 'cleared=${cleared.join(',')}',
  ];
  out('ok #${entry.id} $head'
      "${extras.isEmpty ? '' : ' +${extras.join(' +')}'}");
  return 0;
}

/// Receipt-safe warning for deps pointing at ids that do not exist: the
/// store treats them as satisfied, but a typo surfaces here, immediately,
/// not at the next `ready`.
void _warnUnknownDeps(
    GoalStore store, List<String> ids, void Function(String) out) {
  final unknown = ids
      .where((d) => store.get(d) == null && !store.isArchived(d))
      .map(oneline)
      .toList();
  if (unknown.isNotEmpty) {
    out('! unknown deps (check ids, treated as satisfied): ${unknown.join(' ')}');
  }
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
  // show reads the whole ledger: archived tickets stay inspectable forever,
  // they are only read-only.
  final ref = store.resolveAny(p.positional.first);
  final e = ref.entry;
  final tags = [
    if (ref.archived) 'archived',
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
  // Continuation lines align under the text, after '    [YYYY-MM-DD HH:mm:ss] '.
  for (final n in e.notes) {
    final lines = textLines(n.text);
    out('    [${fullStamp(n.at)}] ${lines.first}');
    final pad = ' ' * ('    ['.length + fullStamp(n.at).length + '] '.length);
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
          // a backup that silently dropped archived tickets would not be a
          // backup — the archive is always part of the export
          'archive': [for (final e in store.archivedAll) _entryJson(e)],
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

/// Escapes content for a markdown table cell (pipes would end the cell).
String _mdCell(String s) => s.replaceAll('|', '\\|');

int _byPriorityThenAge(GoalEntry a, GoalEntry b) {
  final p = (a.priority?.rank ?? 9).compareTo(b.priority?.rank ?? 9);
  return p != 0 ? p : a.updatedAt.compareTo(b.updatedAt);
}

String _markdown(GoalStore store, DateTime now) {
  final counts = store.statusCounts();
  final buf = StringBuffer('# goal ledger — ${fullStamp(now)}');
  buf.writeln();
  buf.writeln();
  buf.writeln('| wip | todo | blocked | failed | parked | done |');
  buf.writeln('| --: | --: | --: | --: | --: | --: |');
  buf.writeln('| ${counts[GoalStatus.wip]} | ${counts[GoalStatus.todo]}'
      ' | ${counts[GoalStatus.blocked]} | ${counts[GoalStatus.failed]}'
      ' | ${counts[GoalStatus.parked]} | ${counts[GoalStatus.done]} |');

  // Active groups: rich bullets — badges, lane owner, age, deps, detail and
  // timestamped notes all belong to the ticket they describe.
  for (final s in [
    GoalStatus.wip,
    GoalStatus.todo,
    GoalStatus.blocked,
    GoalStatus.failed
  ]) {
    final group = store.all.where((e) => e.status == s).toList()
      ..sort(_byPriorityThenAge);
    if (group.isEmpty) continue;
    buf.writeln('\n## ${s.emoji} ${s.name} (${group.length})');
    for (final e in group) {
      final badges = [
        if (e.priority != null) '${e.priority}',
        if (e.round.isNotEmpty) oneline(e.round),
      ].map((b) => '`$b`').join(' ');
      final lead = badges.isEmpty ? '' : '$badges ';
      final tail = e.agent == null
          ? ' · ${age(e.updatedAt, now)}'
          : ' — ${trunc(oneline(e.agent!), 12)} · ${age(e.updatedAt, now)}';
      final deps =
          e.deps.isEmpty ? '' : ' · deps ${e.deps.map(oneline).join(',')}';
      // Continuation lines are indented into the bullet, so a multiline
      // title can never forge a new top-level item or heading.
      final title = textLines(e.title).join('\n  ');
      buf.writeln('- **#${e.id}** $lead$title$tail$deps');
      if (e.detail.isNotEmpty) {
        for (final line in textLines(e.detail)) {
          buf.writeln('  > $line');
        }
      }
      for (final n in e.notes) {
        buf.writeln(
            '  - [${fullStamp(n.at)}] ${textLines(n.text).join('\n    ')}');
      }
    }
  }

  // Parked and not-yet-archived done are index piles, not activity: aligned
  // tables keep them scannable; the last note (revisit condition, settlement)
  // is summarized. Done tickets otherwise existed only as a dashboard number.
  for (final s in [GoalStatus.parked, GoalStatus.done]) {
    final list = store.all.where((e) => e.status == s).toList()
      ..sort(_byPriorityThenAge);
    if (list.isEmpty) continue;
    buf.writeln('\n## ${s.emoji} ${s.name} (${list.length})');
    buf.writeln();
    buf.writeln('| id | pri | round | title | age | last note |');
    buf.writeln('| --: | :-: | :-: | -- | --: | -- |');
    for (final e in list) {
      final last = e.notes.isEmpty ? '' : trunc(oneline(e.notes.last.text), 60);
      buf.writeln('| #${_mdCell(oneline(e.id))} | ${e.priority ?? '-'}'
          ' | ${_mdCell(oneline(e.round))} | ${_mdCell(oneline(e.title))}'
          ' | ${age(e.updatedAt, now)} | ${_mdCell(last)} |');
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

Future<int> _rm(
  GoalStore store,
  ParsedArgs p,
  void Function(String) out,
) async {
  if (p.positional.isEmpty) {
    throw GoalError('goal rm <id>. removes an active ticket; the audit '
        'journal keeps the removal event');
  }
  if (p.positional.length > 1) {
    throw GoalError("unexpected '${p.positional[1]}'. remove one ticket at "
        'a time: goal rm <id>');
  }
  final entry = store.resolve(p.positional.first);
  // Deleting a dependency silently unblocks its dependents (unknown deps are
  // satisfied by design) — surface the consequence now, not at the next ready.
  final dependents = store.all
      .where((e) => e.id != entry.id && e.deps.contains(entry.id))
      .map((e) => '#${e.id}')
      .toList();
  if (dependents.isNotEmpty) {
    out('! removing #${entry.id}: still referenced by ${dependents.join(' ')} '
        '(their dep is now treated as satisfied)');
  }
  await store.remove(entry.id);
  out('ok rm #${entry.id} ${oneline(entry.title)}');
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
  out('                                   --clear agent|pri|round|deps');
  out('                                   no args after id = heartbeat ping');
  out('  goal list [filters]              filters: status/round/priority/id/title');
  out('                                   words, or ${flags('list')}');
  out('  goal ready                       tickets whose deps are all done');
  out('  goal show <id>                   full ticket (archived too, read-only)');
  out('  goal render [-o file] [--json]   markdown view / json backup');
  out('  goal archive [--dry-run]         move done tickets to archive');
  out('  goal rm <id>                     remove an active ticket');
  out('');
  out('exit codes: 0 ok | 2 not-found/usage/busy | 4 dependency cycle');
}
