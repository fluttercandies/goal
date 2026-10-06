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

    test('bare words join into one title', () async {
      await run(['init']);
      // unquoted multi-word input must succeed in one shot
      expect(await run(['add', 'two', 'words']), 0);
      expect(out.single, 'ok #1 created (todo) two words');
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
      expect(out.single, 'ok #1 todo -> wip +agent=agent_9f3c');
      expect(await run(['set', '1', 'done', '改了 a.dart; 测试通过']), 0);
      expect(out.single, 'ok #1 wip -> done +note="改了 a.dart; 测试通过"');
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
      expect(out.single, 'ok #1 ping');
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
      expect(out.single, 'ok #1 todo -> done');
      expect(await run(['set', '1', 'wip']), 0);
      expect(await run(['set', '1', 'complete']), 0);
      expect(out.single, 'ok #1 wip -> done');
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
      expect(out.single, 'ok #1 todo -> wip +note="piped note"');
      await run(['show', '1']);
      expect(out.join('\n'), contains('piped note'));
    });

    test('--round relabels the ticket without touching the ledger round',
        () async {
      await run(['init']);
      await run(['add', 'a', '--round', 'R798']);
      await run(['add', 'b']);
      expect(await run(['set', '1', '--round', 'R800']), 0);
      expect(out.single, 'ok #1 updated +round=R800');
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
      expect(out.first, startsWith('#1 '));
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
      expect(out.first, startsWith('#2 '));
      await run(['list', '#1']);
      expect(out.first, startsWith('#1 '));
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
      expect(out.first, startsWith('#1 '));
      await run(['list', '--round', 'R799']);
      expect(out.first, startsWith('#2 '));
      await run(['list', '--id', '2']);
      expect(out.first, startsWith('#2 '));
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

  group('multiline and complex content', () {
    test('multiline title: receipt and list stay one line, show is verbatim',
        () async {
      await run(['init']);
      expect(await run(['add', 'first line\nsecond line']), 0);
      expect(out.single, 'ok #1 created (todo) first line second line');
      await run(['list']);
      expect(out.first, contains('first line second line'));
      expect(out.first.contains('\n'), isFalse);
      await run(['show', '1']);
      final text = out.join('\n');
      expect(text, contains('  first line'));
      expect(text, contains('  second line'));
    });

    test('control characters and ANSI render as plain single-line text',
        () async {
      await run(['init']);
      await run(['add', 'a\x1B[31m\tb\x00c']);
      await run(['list']);
      expect(out.first.contains('\x1B'), isFalse);
      expect(out.first, contains('a b c'));
    });

    test('blank titles are rejected with guidance', () async {
      await run(['init']);
      expect(await run(['add', '   ']), 2);
      expect(err.single, contains('title cannot be empty'));
      expect(await run(['add', '']), 2);
      expect(await run(['add', '\x1B[31m']), 2); // control-only is blank too
    });

    test('empty note and round flags fail loudly, never silently', () async {
      await run(['init']);
      await run(['add', 't']);
      expect(await run(['set', '1', '-m', '   ']), 2);
      expect(err.single, contains('-m value is empty'));
      expect(await run(['set', '1', '-m', '-'], stdin: () async => '  \n'), 2);
      expect(err.single, contains('read nothing from stdin'));
      expect(await run(['set', '1', '--round', ' ']), 2);
      expect(err.single, contains('--round value is empty'));
      expect(await run(['add', 'u', '--round', ' ']), 2);
      // the failed calls above wrote nothing
      await run(['show', '1']);
      expect(out.last, '  notes:');
      expect(out.join('\n'), contains('#1 [todo]'));
    });

    test('receipts state every new value, no follow-up show needed', () async {
      await run(['init']);
      await run(['add', 'a']);
      await run(['add', 'b']);
      expect(
        await run([
          'set',
          '1',
          'wip',
          '--agent',
          'agent_x',
          '-p2',
          '--round',
          'R900',
          '--deps',
          '2',
          '-m',
          'note text',
        ]),
        0,
      );
      expect(
        out.single,
        'ok #1 todo -> wip +note="note text" +agent=agent_x +deps=2 '
        '+round=R900 +pri=P2',
      );
    });

    test('long multiline note receipts are capped and single-line', () async {
      await run(['init']);
      await run(['add', 't']);
      final long = 'x' * 100;
      expect(await run(['set', '1', '-m', 'first\n$long']), 0);
      expect(out.single, 'ok #1 updated +note="first ${'x' * 34}"');
      expect(out.single.contains('\n'), isFalse);
      // the stored note itself is untouched
      await run(['show', '1']);
      expect(out.join('\n'), contains('first'));
      expect(out.join('\n'), contains('x' * 100));
    });

    test('round with control characters still prints a one-line receipt',
        () async {
      await run(['init']);
      expect(await run(['add', 't', '--round', 'R\n9']), 0);
      expect(out.single, contains('round=R 9'));
      expect(out.single.contains('\n'), isFalse);
    });

    test('deps dedupe and blank segments are dropped', () async {
      await seed([
        ['init'],
        ['add', 'a'],
        ['add', 'b', '--deps', ' 1 , 1 , , '],
      ]);
      await run(['show', '2']);
      expect(out.join('\n'), contains('deps: 1 (todo)'));
    });

    test('ghost dep ids are flattened in the ready warning', () async {
      await run(['init']);
      await run(['add', 't', '--deps', 'gh\nost']);
      expect(await run(['ready']), 0);
      expect(out.join('\n'),
          contains('! unknown deps (treated as satisfied): gh ost'));
    });

    test('multiline note stores verbatim and shows aligned continuation',
        () async {
      await run(['init']);
      await run(['add', 't']);
      await run(['set', '1', 'wip', '-m', 'step one\nstep two']);
      await run(['show', '1']);
      final i = out.indexWhere((l) => l.contains('step one'));
      expect(out[i], '    [2026-10-06 12:00:00] step one');
      // continuation aligns under the first character of the note text
      final pad = ' ' * out[i].indexOf('step one');
      expect(out[i + 1], '${pad}step two');
    });

    test('title search matches across line breaks', () async {
      await run(['init']);
      await run(['add', 'two\nwords']);
      expect(await run(['list', 'two words']), 0);
      expect(out.first, startsWith('#1 '));
    });
  });

  group('rm, corrections and archive visibility', () {
    test('rm removes an active ticket and reports its title', () async {
      await run(['init']);
      await run(['add', 'obsolete']);
      expect(await run(['rm', '1']), 0);
      expect(out.single, 'ok rm #1 obsolete');
      expect(await run(['show', '1']), 2);
      expect(err.single, contains("no ticket '1'"));
      await run(['list']);
      expect(out.single, '-- 0 tickets');
    });

    test('rm rejects extra args and archived tickets', () async {
      await run(['init']);
      await run(['add', 'a']);
      expect(await run(['rm', '1', '2']), 2);
      expect(err.single, contains('one ticket at a time'));
      await run(['set', '1', 'done']);
      await run(['archive']);
      expect(await run(['rm', '1']), 2);
      expect(err.single, contains('read-only'));
    });

    test('ids of removed tickets are never reused', () async {
      await run(['init']);
      await run(['add', 'a']);
      await run(['rm', '1']);
      expect(await run(['add', 'b']), 0);
      expect(out.single, startsWith('ok #2 created'));
    });

    test('--title and --detail correct a ticket with receipt values', () async {
      await run(['init']);
      await run(['add', 'wrong title', '-m', 'wrong body']);
      expect(
          await run(['set', '1', '--title', 'right title', '--detail', 'body']),
          0);
      expect(out.single, 'ok #1 updated +title="right title" +detail="body"');
      await run(['show', '1']);
      final text = out.join('\n');
      expect(text, contains('  right title'));
      expect(text, contains('    body'));
      expect(text, isNot(contains('wrong')));
    });

    test('blank --title and empty stdin fail loudly', () async {
      await run(['init']);
      await run(['add', 't']);
      expect(await run(['set', '1', '--title', ' ']), 2);
      expect(err.single, contains('--title value is empty'));
      expect(
        await run(['set', '1', '--title', '-'], stdin: () async => '\n'),
        2,
      );
      expect(err.single, contains('read nothing from stdin'));
    });

    test('show reads archived tickets, labeled read-only', () async {
      await run(['init']);
      await run(['add', 'finished work', '-p1', '--round', 'R798']);
      await run(['set', '1', 'done']);
      await run(['archive']);
      expect(await run(['show', '1']), 0);
      final text = out.join('\n');
      expect(text, contains('#1 [archived] [done] [P1] [R798]'));
      // archived stays read-only for writes
      expect(await run(['set', '1', 'wip']), 2);
      expect(err.single, contains('read-only'));
    });

    test('unknown deps warn at add and set time', () async {
      await run(['init']);
      await run(['add', 't', '--deps', '99']);
      expect(out.first, startsWith('! unknown deps'));
      expect(out.first, contains('99'));
      expect(out.last, startsWith('ok #1 created'));
      await run(['set', '1', '--deps', '88']);
      expect(out.first, contains('88'));
      expect(out.last, 'ok #1 updated +deps=88');
    });

    test('help works in flag position', () async {
      expect(await run(['set', '--help']), 0);
      expect(out.join('\n'), contains('goal set <id> [status]'));
    });

    test('audit journal failure degrades to a warning, never a false failure',
        () async {
      await run(['init']);
      // block the journal by replacing its file with a directory
      File('$home/events.jsonl').deleteSync();
      Directory('$home/events.jsonl').createSync();
      expect(await run(['add', 't']), 0);
      expect(out.single, startsWith('ok #1 created'));
      expect(err.single, contains('audit journal'));
      // the data write itself succeeded
      await run(['show', '1']);
      expect(out.join('\n'), contains('  t'));
    });
  });

  group('round-2 hardening', () {
    test('-h works as the first argument, like --help', () async {
      expect(await run(['-h']), 0);
      expect(out.join('\n'), contains('goal set <id> [status]'));
    });

    test('#id form works everywhere renders display it', () async {
      await run(['init']);
      await run(['add', 'alpha']);
      expect(await run(['set', '#1', 'wip']), 0);
      expect(out.single, 'ok #1 todo -> wip');
      expect(await run(['show', '#1']), 0);
      expect(out.first, '#1 [wip]');
      await run(['add', 'child', '--deps', '#1']);
      expect(out.first, startsWith('ok #2 created'));
      // no unknown-deps warning: the # was normalized away
      expect(out, isNot(contains(contains('unknown deps'))));
      await run(['set', '#1', 'done']);
      expect(await run(['rm', '#2']), 0);
      expect(out.single, 'ok rm #2 child');
    });

    test('junk positionals fail loudly instead of dropping silently', () async {
      await run(['init']);
      await run(['add', 'a']);
      expect(await run(['ready', 'now']), 2);
      expect(err.single, contains('goal ready takes no arguments'));
      expect(await run(['show', '1', 'extra']), 2);
      expect(err.single, contains('exactly one id'));
      expect(await run(['render', 'junk']), 2);
      expect(err.single, contains('goal render takes no arguments'));
      expect(await run(['archive', 'junk']), 2);
      expect(err.single, contains('goal archive takes no arguments'));
      expect(await run(['init', 'again']), 2);
      expect(err.single, contains('goal init takes no arguments'));
    });

    test('rm warns when other tickets still depend on the id', () async {
      await run(['init']);
      await run(['add', 'dep target']);
      await run(['add', 'child', '--deps', '1']);
      expect(await run(['rm', '1']), 0);
      expect(
          out.first,
          '! removing #1: still referenced by #2 (their dep is now treated '
          'as satisfied)');
      expect(out.last, 'ok rm #1 dep target');
      // the dependent is ready now, with the standard missing-deps note
      await run(['ready']);
      expect(out.join('\n'), contains('unknown deps'));
    });

    test('render lists not-yet-archived done tickets in an index table',
        () async {
      await run(['init']);
      await run(['add', 'finished', '-p2']);
      await run(['set', '1', 'done', '-m', 'verify: dart test']);
      expect(await run(['render']), 0);
      final text = out.join('\n');
      expect(text, contains('## ✅ done (1)'));
      // empty round renders as an empty table cell
      expect(
          text, contains('| #1 | P2 |  | finished | 0s | verify: dart test |'));
      // once archived, the done section empties again
      await run(['archive']);
      expect(await run(['render']), 0);
      expect(out.join('\n'), isNot(contains('## ✅ done')));
    });
  });

  group('unicode, RTL and grapheme edges', () {
    test('Arabic, Hebrew and Persian content round-trips verbatim', () async {
      await run(['init']);
      const arabic = 'إصلاح تسجيل الدخول على iOS';
      expect(await run(['add', arabic, '-p1']), 0);
      expect(out.single, 'ok #1 created (todo) $arabic');
      await run(['show', '1']);
      expect(out.join('\n'), contains('  $arabic'));
      // substring filter matches the raw stored title
      await run(['list', 'تسجيل']);
      expect(out.first, contains(arabic));
      await run(['render']);
      expect(out.join('\n'), contains('**#1** `P1` $arabic'));

      await run(['set', '1', 'wip', '-m', 'בדיקה: הכל עובד']);
      expect(out.single, contains('בדיקה: הכל עובד'));
      await run(['show', '1']);
      expect(out.join('\n'),
          contains('    [2026-10-06 12:00:00] בדיקה: הכל עובד'));

      // Persian zero-width non-joiner stays in storage untouched
      const persian = 'نیم\u200Cفاصله';
      await run(['add', persian]);
      await run(['show', '2']);
      expect(out.join('\n'), contains('  $persian'));
    });

    test('U+2028/U+2029 count as line breaks in views, spaces in rows',
        () async {
      await run(['init']);
      await run(['add', 'one\u2028two\u2029three']);
      await run(['show', '1']);
      expect(out, contains('  one'));
      expect(out, contains('  two'));
      expect(out, contains('  three'));
      // receipts and list rows stay structurally single-line
      await run(['list']);
      expect(out.first, contains('one two three'));
      expect(out.first, isNot(contains('\u2028')));
      // render indents every line into the bullet
      await run(['render']);
      final text = out.join('\n');
      expect(text, contains('one\n  two\n  three'));
    });

    test('truncation never splits a grapheme cluster', () async {
      await run(['init']);
      const family = '👨‍👩‍👧‍👦'; // 7 runes, 1 grapheme
      final longNote = '${'a' * 39}$family tail';
      await run(['add', 't']);
      await run(['set', '1', '-m', longNote]);
      expect(out.single, contains('note="'));
      expect(out.single, contains(family));
      expect(out.single, isNot(contains('tail')));

      // base letter + harakat pairs: the cut lands on whole pairs only
      const pair = '\u0628\u064E'; // beh + fatha = 1 grapheme, 2 runes
      final arabicTitle = 'X' * 38 + pair * 10;
      await run(['set', '1', '--title', arabicTitle]);
      // 38 X + 2 pairs = 40 graphemes = 42 runes: rune-cut would split here
      expect(out.single, contains('"${'X' * 38}$pair$pair"'));

      // listLine caps at 60 graphemes, clusters intact
      await run(['set', '1', '--title', family * 100]);
      await run(['list']);
      expect(out.first.endsWith(family * 60), isTrue);
    });

    test('full-width and ideographic separators parse in deps and id lists',
        () async {
      await run(['init']);
      await run(['add', 'a']);
      await run(['add', 'b']);
      expect(await run(['add', 'multi', '--deps', '1，2、']), 0);
      expect(out.single, 'ok #3 created (todo) +deps=1,2 multi');
      expect(out, isNot(contains(contains('unknown deps'))));
      await run(['list', '--id', '1　3']); // ideographic space too
      expect(out.length, 3); // rows for #1 and #3 + footer
      await run(['show', '3']);
      expect(out.join('\n'), contains('deps: 1 (todo), 2 (todo)'));
    });

    test('malformed piped stdin fails with a UTF-8 tutorial', () async {
      await run(['init']);
      await run(['add', 't']);
      expect(
        await run(
          ['set', '1', '-m', '-'],
          stdin: () async =>
              throw const FormatException('Missing extension byte'),
        ),
        2,
      );
      expect(err.single, contains('not valid UTF-8'));
      expect(err.single, contains('re-send'));
    });

    test('--clear is the dedicated mechanism; empty values get tutorials',
        () async {
      await run(['init']);
      await run(['add', 't']);
      await run(
          ['set', '1', 'wip', '--agent', 'agent_x', '-p1', '--round', 'R9']);

      // release the lane explicitly, with receipt
      expect(await run(['set', '1', '--clear', 'agent']), 0);
      expect(out.single, 'ok #1 updated +cleared=agent');
      await run(['show', '1']);
      expect(out.join('\n'), contains('  agent: -'));

      // combined clears report every field
      await run(['set', '1', '--clear', 'pri,round']);
      expect(out.single, 'ok #1 updated +cleared=pri,round');
      await run(['show', '1']);
      expect(out.first, '#1 [wip]');

      // idempotent clear on an already-empty field is a ping, not an update
      expect(await run(['set', '1', '--clear', 'agent']), 0);
      expect(out.single, 'ok #1 ping');

      // empty or blank flag values fail with tutorials, never silently clear
      expect(await run(['set', '1', '--agent', '']), 2);
      expect(err.single, contains('--clear agent'));
      expect(await run(['set', '1', '--agent', '-']), 2);
      expect(err.single, contains("--agent takes an agent id, not '-'"));
      expect(await run(['set', '1', '--deps', '']), 2);
      expect(err.single, contains('--clear deps'));
      expect(await run(['set', '1', '--clear', '']), 2);
      expect(err.single, contains('clearable fields'));

      // unknown field names list the valid ones
      expect(await run(['set', '1', '--clear', 'title']), 2);
      expect(err.single, contains("cannot clear 'title'"));
      expect(err.single, contains('agent pri round deps'));

      // set and clear on one field in one command is a contradiction
      expect(await run(['set', '1', '--agent', 'b', '--clear', 'agent']), 2);
      expect(err.single, contains('cannot set and clear agent'));
      expect(await run(['set', '1', '-p2', '--clear', 'pri']), 2);
      expect(err.single, contains('cannot set and clear pri'));
    });

    test('--clear deps unblocks the ticket and clears the round label',
        () async {
      await run(['init']);
      await run(['add', 'dep', '--round', 'R1']);
      await run(['add', 'child', '--deps', '1', '--round', 'R1']);
      await run(['ready']);
      expect(out.join('\n'), isNot(contains('child')));
      expect(await run(['set', '2', '--clear', 'deps']), 0);
      expect(out.single, 'ok #2 updated +cleared=deps');
      await run(['ready']);
      expect(out.join('\n'), contains('child'));
      await run(['show', '2']);
      expect(out.join('\n'), contains('  deps: -'));
      expect(out.join('\n'), contains('R1]'));
      expect(await run(['set', '2', '--clear', 'round']), 0);
      await run(['show', '2']);
      expect(out.first, '#2 [todo]');
    });

    test('equals-form valued flags parse', () async {
      await run(['init']);
      await run(['add', 't']);
      await run(['add', 'u']);
      expect(await run(['set', '1', '--title=fixed']), 0);
      expect(out.single, 'ok #1 updated +title="fixed"');
      expect(await run(['set', '1', '--deps=2']), 0);
      expect(out.single, 'ok #1 updated +deps=2');
    });

    test('dash-leading titles survive via --', () async {
      await run(['init']);
      expect(await run(['add', '--', '-p1 not a flag']), 0);
      // everything after -- is positional, joined into one verbatim title
      expect(out.single, 'ok #1 created (todo) -p1 not a flag');
      await run(['show', '1']);
      expect(out.join('\n'), contains('  -p1 not a flag'));
    });

    test('empty ledger renders a zeroed dashboard only', () async {
      await run(['init']);
      expect(await run(['render']), 0);
      final text = out.join('\n');
      expect(text, contains('| 0 | 0 | 0 | 0 | 0 | 0 |'));
      expect(text, isNot(contains('## ')));
    });

    test('very long CJK title: capped in list, full in show and json',
        () async {
      await run(['init']);
      final long = '很长' * 200; // 400 graphemes
      await run(['add', long]);
      await run(['list']);
      expect(out.first, isNot(contains(long)));
      await run(['show', '1']);
      expect(out.join('\n'), contains(long));
      await run(['render', '--json']);
      expect(out.join('\n'), contains(long));
    });
  });
}
