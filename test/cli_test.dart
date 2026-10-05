import 'dart:io';

import 'package:goal/goal.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String home;
  final now = DateTime(2026, 10, 6, 12);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('goal_cli_');
    home = '${tmp.path}/.goal';
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // hive lock cleanup can race the delete; OS temp dirs are self-cleaning
    }
  });

  final List<String> out = [];
  final List<String> err = [];

  Future<int> run(List<String> args, {Future<String> Function()? stdin}) {
    out.clear();
    err.clear();
    return runGoalCli(
      args,
      home: home,
      writeln: out.add,
      errln: err.add,
      clock: () => now,
      stdinReader: stdin,
    );
  }

  Future<int> seed(Iterable<List<String>> steps) async {
    var code = 0;
    for (final step in steps) {
      out.clear();
      err.clear();
      code = await run(step);
      if (code != 0) return code;
    }
    return code;
  }

  group('ledger lifecycle', () {
    test('init prints ledger path', () async {
      final code = await run(['init']);
      expect(code, 0);
      expect(out.single, 'ok ledger at $home');
    });

    test('init twice fails with tutorial message', () async {
      expect(await run(['init']), 0);
      expect(await run(['init']), 2);
      expect(err.single, contains('already exists'));
    });

    test('any command before init fails, never forks a ledger', () async {
      expect(await run(['add', 'x']), 2);
      expect(err.single, contains('no ledger here'));
      expect(err.single, contains('goal init'));
      expect(Directory(home).existsSync(), isFalse);
    });
  });

  group('add', () {
    test('basic receipt carries id, status, round and title', () async {
      await run(['init']);
      await run(['add', '修复滚动溢出', '--round', 'R798']);
      final code = await run(['add', '第二个任务']);
      expect(code, 0);
      expect(out.single, startsWith('ok #2 created (todo)'));
      expect(out.single, contains('第二个任务'));
    });

    test('round is inherited from the previous add', () async {
      await run(['init']);
      await run(['add', 'a', '--round', 'R799']);
      await run(['add', 'b']);
      final code = await run(['show', '2']);
      expect(code, 0);
      expect(out.join('\n'), contains('[R799]'));
    });

    test('missing title is a usage error', () async {
      await run(['init']);
      expect(await run(['add']), 2);
      expect(err.single, contains('goal add <title>'));
    });

    test('extra positional teaches quoting', () async {
      await run(['init']);
      expect(await run(['add', 'two', 'words']), 2);
      expect(err.single, contains('quote the title'));
    });

    test('unknown flag lists valid flags', () async {
      await run(['init']);
      expect(await run(['add', 'x', '--nope']), 2);
      expect(err.single, contains('unknown flag'));
      expect(err.single, contains('--deps'));
    });

    test('"--" lets a title start with a dash', () async {
      await run(['init']);
      expect(await run(['add', '--', '-p2 title']), 0);
      expect(out.single, contains('-p2 title'));
    });

    test('--deps accepts inline = form and spaces', () async {
      await seed([
        ['init'],
        ['add', 'a'],
        ['add', 'b'],
        ['add', 'c', '--deps=1, 2'],
        ['set', '1', 'done'],
      ]);
      final code = await run(['show', '3']);
      expect(code, 0);
      expect(out.join('\n'), contains('deps: 1 (done), 2 (todo)'));
    });
  });

  group('set', () {
    test('status transitions, notes and receipts', () async {
      await run(['init']);
      await run(['add', 'task']);
      expect(await run(['set', '1', 'wip', '--agent', 'agent_9f3c']), 0);
      expect(out.single, 'ok 1 todo -> wip +agent');
      expect(await run(['set', '1', 'done', '改了 a.dart; 测试通过']), 0);
      expect(out.single, 'ok 1 wip -> done +note');
    });

    test('idempotent: repeating a status is not an error', () async {
      await run(['init']);
      await run(['add', 't']);
      await run(['set', '1', 'wip']);
      expect(await run(['set', '1', 'wip']), 0);
      expect(out.single, contains('already wip'));
    });

    test('no arguments is a heartbeat ping', () async {
      await run(['init']);
      await run(['add', 't']);
      expect(await run(['set', '1']), 0);
      expect(out.single, 'ok 1 ping');
    });

    test('typo status fails loudly with the legal values', () async {
      await run(['init']);
      await run(['add', 't']);
      expect(await run(['set', '1', 'donex']), 2);
      expect(err.single, contains('not a status'));
      expect(err.single, contains('todo wip done blocked failed parked'));
    });

    test('note-only update must go through -m, strict slot teaches it',
        () async {
      await run(['init']);
      await run(['add', 't']);
      expect(await run(['set', '1', '只是备注']), 2);
      expect(err.single, contains('-m'));
    });

    test('emoji and word aliases accepted', () async {
      await run(['init']);
      await run(['add', 't']);
      expect(await run(['set', '1', '✅']), 0);
      expect(out.single, 'ok 1 todo -> done');
      expect(await run(['set', '1', 'wip']), 0);
      expect(await run(['set', '1', 'complete']), 0);
      expect(out.single, 'ok 1 wip -> done');
    });

    test('agent is auto-cleared when leaving wip', () async {
      await run(['init']);
      await run(['add', 't']);
      await run(['set', '1', 'wip', '--agent', 'agent_a']);
      await run(['set', '1', 'parked']);
      await run(['show', '1']);
      expect(out.join('\n'), contains('agent: -'));
    });

    test('note appended via -m and trailing words combine', () async {
      await run(['init']);
      await run(['add', 't']);
      await run(['set', '1', 'wip', 'positional note', '-m', 'flag note']);
      await run(['show', '1']);
      final text = out.join('\n');
      expect(text, contains('positional note flag note'));
    });

    test('-m - reads the note from stdin', () async {
      await run(['init']);
      await run(['add', 't']);
      expect(
        await run(['set', '1', 'wip', '-m', '-'],
            stdin: () async => 'piped note\n'),
        0,
      );
      expect(out.single, 'ok 1 todo -> wip +note');
      await run(['show', '1']);
      expect(out.join('\n'), contains('piped note'));
    });

    test('--round relabels the ticket without touching the ledger round',
        () async {
      await run(['init']);
      await run(['add', 'a', '--round', 'R798']);
      await run(['add', 'b']);
      expect(await run(['set', '1', '--round', 'R800']), 0);
      expect(out.single, 'ok 1 updated +round');
      await run(['show', '1']);
      expect(out.join('\n'), contains('[R800]'));
      // ticket 2 still inherits the ledger-wide round
      await run(['show', '2']);
      expect(out.join('\n'), contains('[R798]'));
    });

    test('priority flag updates priority', () async {
      await run(['init']);
      await run(['add', 't']);
      expect(await run(['set', '1', '-p3']), 0);
      await run(['show', '1']);
      expect(out.join('\n'), contains('[P3]'));
    });

    test('flag missing value is a usage error', () async {
      await run(['init']);
      await run(['add', 't']);
      expect(await run(['set', '1', '-m']), 2);
      expect(err.single, contains('needs a value'));
    });

    test('invalid attached priority fails with the range', () async {
      await run(['init']);
      await run(['add', 't']);
      expect(await run(['set', '1', '-p9']), 2);
      expect(err.single, contains('-p0..-p3'));
    });
  });

  group('list', () {
    test('empty ledger footer', () async {
      await run(['init']);
      expect(await run(['list']), 0);
      expect(out.single, '-- 0 tickets');
    });

    test('bareword filters combine with AND', () async {
      await seed([
        ['init'],
        ['add', '修复 A', '--round', 'R798', '-p1'],
        ['add', '修复 B', '--round', 'R798'],
        ['add', '修复 C', '--round', 'R799', '-p1'],
      ]);
      expect(await run(['list', 'todo', 'R798', 'p1']), 0);
      expect(out.where((l) => l.startsWith('2')), isEmpty);
      expect(out.first, startsWith('1 '));
      expect(out.last, startsWith('--'));
    });

    test('wip rows carry agent and age', () async {
      await seed([
        ['init'],
        ['add', 'lane work'],
        ['set', '1', 'wip', '--agent', 'agent_zz'],
      ]);
      await run(['list', 'wip']);
      expect(out.first, contains('agent_zz'));
      expect(out.first, contains('wip'));
    });

    test('numeric and hash id filters', () async {
      await seed([
        ['init'],
        ['add', 'a'],
        ['add', 'b'],
      ]);
      expect(await run(['list', '2']), 0);
      expect(out.first, startsWith('2 '));
      await run(['list', '#1']);
      expect(out.first, startsWith('1 '));
    });

    test('title substring is case-insensitive', () async {
      await seed([
        ['init'],
        ['add', 'Fix Scroll Overflow'],
      ]);
      expect(await run(['list', 'scroll']), 0);
      expect(out.first, contains('Fix Scroll Overflow'));
    });

    test('no matches says so', () async {
      await seed([
        ['init'],
        ['add', 'a'],
      ]);
      expect(await run(['list', 'parked']), 0);
      expect(out.first, 'no matches.');
    });

    test('two status filters are rejected', () async {
      await seed([
        ['init'],
      ]);
      expect(await run(['list', 'todo', 'wip']), 2);
      expect(err.single, contains('only one status filter'));
    });

    test('flag filter forms -pN/--round/--id are honored', () async {
      await seed([
        ['init'],
        ['add', 'a', '--round', 'R798', '-p1'],
        ['add', 'b', '--round', 'R799'],
      ]);
      expect(await run(['list', '-p1']), 0);
      expect(out.first, startsWith('1 '));
      await run(['list', '--round', 'R799']);
      expect(out.first, startsWith('2 '));
      await run(['list', '--id', '2']);
      expect(out.first, startsWith('2 '));
      expect(await run(['list', '--id', '9']), 0);
      expect(out.first, 'no matches.');
    });
  });

  group('flag validation', () {
    test('flags a command does not take are rejected with the valid set',
        () async {
      await run(['init']);
      await run(['add', 't']);
      expect(await run(['set', '1', '--id', '7']), 2);
      expect(err.single, contains('not valid for goal set'));
      expect(err.single, contains('--agent <id>'));
      expect(await run(['ready', '-p0']), 2);
      expect(err.single, contains('it takes no flags'));
      expect(await run(['list', '-m', 'x']), 2);
      expect(err.single, contains('not valid for goal list'));
    });

    test('bool flags reject attached values', () async {
      await run(['init']);
      expect(await run(['render', '--json=false']), 2);
      expect(err.single, contains('does not take a value'));
    });
  });

  group('ready', () {
    test('deps gating, priority order and warning for ghost deps', () async {
      await seed([
        ['init'],
        ['add', 'blocker'],
        ['add', 'later', '-p0'],
        ['add', 'urgent', '-p1'],
        ['add', 'waiting', '--deps', '1'],
      ]);
      expect(await run(['ready']), 0);
      final body = out.takeWhile((l) => !l.startsWith('--')).toList();
      expect(body.length, 3);
      expect(body[0], contains('later')); // p0 outranks p1
      expect(body[1], contains('urgent'));
      expect(body[2], contains('blocker')); // unproritized oldest last
      expect(out.join('\n'), contains('-- 3 ready'));
      expect(out.join('\n'), isNot(contains('waiting')));

      // ghost dep: tolerated with a warning line
      await run(['add', 'ghost', '--deps', 'missing-9']);
      await run(['ready']);
      expect(out.join('\n'), contains('! unknown deps'));
      expect(out.join('\n'), contains('missing-9'));
    });
  });

  group('show', () {
    test('full ticket block with dep states, detail and notes', () async {
      await seed([
        ['init'],
        ['add', 'a', '-m', 'line1\nline2'],
        ['add', 'b'],
        ['add', 'c', '--deps', '1,2,ghost-1', '-p2', '--round', 'R800'],
        ['set', '1', 'done'],
        ['set', '3', 'wip', '--agent', 'agent_ab', '-m', '进行中'],
      ]);
      final code = await run(['show', '3']);
      expect(code, 0);
      final text = out.join('\n');
      expect(text, contains('#3 [wip] [P2] [R800]'));
      expect(text, contains('agent: agent_ab'));
      expect(text, contains('deps: 1 (done), 2 (todo), ghost-1 (missing)'));
      expect(text, contains('] 进行中'));
      // detail lives on ticket 1
      await run(['show', '1']);
      final detailText = out.join('\n');
      expect(detailText, contains('    line1'));
      expect(detailText, contains('    line2'));
    });

    test('show unknown id fails with recent ids', () async {
      await seed([
        ['init'],
        ['add', 'only'],
      ]);
      expect(await run(['show', '42']), 2);
      expect(err.single, contains("no ticket '42'"));
      expect(err.single, contains('1'));
    });
  });
}
