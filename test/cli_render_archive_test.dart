import 'dart:convert';
import 'dart:io';

import 'package:goal/goal.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String home;
  final now = DateTime(2026, 10, 6, 12);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('goal_render_');
    home = '${tmp.path}/.goal';
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // hive lock cleanup can race the delete; OS temp dirs are self-cleaning
    }
  });

  final out = <String>[];
  final err = <String>[];

  Future<int> run(List<String> args) {
    out.clear();
    err.clear();
    return runGoalCli(
      args,
      home: home,
      writeln: out.add,
      errln: err.add,
      clock: () => now,
    );
  }

  Future<void> seed() async {
    await run(['init']);
    await run(['add', '修复 A', '-p1', '--round', 'R798', '-m', '背景说明']);
    await run(['add', '修复 B', '--round', 'R798']);
    await run(['set', '1', 'wip', '--agent', 'agent_k', '-m', '进行中']);
    await run(['add', '携带']);
    await run(['set', '3', 'parked', '回访条件：下次触面批']);
    out.clear();
    err.clear();
  }

  group('render', () {
    test('markdown groups with emoji headers and notes', () async {
      await seed();
      final code = await run(['render']);
      expect(code, 0);
      final text = out.join('\n');
      expect(text, startsWith('# goal ledger — 2026-10-06 12:00:00'));
      // status dashboard right under the header
      expect(
          text, contains('| wip | todo | blocked | failed | parked | done |'));
      expect(text, contains('| 1 | 1 | 0 | 0 | 1 | 0 |'));
      expect(text, contains('## 🚧 wip (1)'));
      expect(text, contains('## ⬜ todo (1)'));
      expect(text, contains('## 📦 parked (1)'));
      expect(
        text,
        contains('- **#1** `P1` `R798` 修复 A — agent_k · 0s'),
      );
      expect(text, contains('[${fullStamp(now)}] 进行中'));
      expect(text, contains('回访条件：下次触面批'));
    });

    test('parked renders as an aligned index table', () async {
      await seed();
      expect(await run(['render']), 0);
      final text = out.join('\n');
      expect(text, contains('| id | pri | round | title | age | last note |'));
      expect(
        text,
        contains('| #3 | - | R798 | 携带 | 0s | 回访条件：下次触面批 |'),
      );
    });

    test('empty ledger renders just the header', () async {
      await run(['init']);
      out.clear();
      expect(await run(['render']), 0);
      expect(out.join('\n'), startsWith('# goal ledger —'));
      expect(out.length, 1);
    });

    test('-o writes the file', () async {
      await seed();
      final target = '${tmp.path}/GOALS.md';
      expect(await run(['render', '-o', target]), 0);
      expect(out.single, 'ok wrote $target');
      final content = File(target).readAsStringSync();
      expect(content, contains('## 🚧 wip (1)'));
    });

    test('--json emits a machine backup', () async {
      await seed();
      expect(await run(['render', '--json']), 0);
      final data = jsonDecode(out.join('\n')) as Map<String, dynamic>;
      expect(data['meta']['nextId'], 4);
      expect(data['meta']['currentRound'], 'R798');
      final goals = data['goals'] as List;
      expect(goals.length, 3);
      final first = goals.first as Map<String, dynamic>;
      expect(first['id'], '1');
      expect(first['status'], 'wip');
      expect(first['agent'], 'agent_k');
      expect((first['notes'] as List).length, 1);
    });

    test('--json backup includes archived tickets', () async {
      await seed();
      await run(['set', '2', 'done']);
      await run(['archive']);
      out.clear();
      expect(await run(['render', '--json']), 0);
      final data = jsonDecode(out.join('\n')) as Map<String, dynamic>;
      expect((data['goals'] as List).length, 2);
      final archive = data['archive'] as List;
      expect(archive.length, 1);
      expect((archive.single as Map<String, dynamic>)['id'], '2');
      expect((archive.single as Map<String, dynamic>)['status'], 'done');
    });
  });

  group('archive', () {
    test('dry-run lists without moving', () async {
      await seed();
      await run(['set', '2', 'done']);
      out.clear();
      expect(await run(['archive', '--dry-run']), 0);
      expect(out.single, 'would archive 1: 2');
      // nothing moved
      await run(['show', '2']);
      expect(out.join('\n'), contains('[done]'));
    });

    test('apply moves done tickets and reports ids', () async {
      await seed();
      await run(['set', '2', 'done']);
      out.clear();
      expect(await run(['archive']), 0);
      expect(out.single, 'ok archived 1: 2');
      // archived tickets stay visible to read-only views, tagged as archived
      out.clear();
      expect(await run(['show', '2']), 0);
      expect(out.join('\n'), contains('[archived]'));
      // but remain immutable
      expect(await run(['set', '2', 'wip']), 2);
      expect(err.single, contains('archived'));
      expect(await run(['archive']), 0);
      expect(out.single, 'nothing to archive.');
    });

    test('footer and list exclude archived tickets', () async {
      await seed();
      await run(['set', '2', 'done']);
      await run(['archive']);
      out.clear();
      await run(['list']);
      final text = out.join('\n');
      expect(text, contains('1 wip | 1 parked'));
      expect(text, isNot(contains('2 wip')));
    });

    test('archived dep still satisfies ready', () async {
      await run(['init']);
      await run(['add', 'dep']);
      await run(['add', 'child', '--deps', '1']);
      await run(['set', '1', 'done']);
      await run(['archive']);
      expect(await run(['ready']), 0);
      expect(out.join('\n'), contains('child'));
      expect(out.join('\n'), contains('-- 1 ready'));
    });
  });

  group('exit codes and help', () {
    test('dependency cycle exits 4 with the cycle path', () async {
      await run(['init']);
      await run(['add', 'a']);
      await run(['add', 'b']);
      await run(['set', '2', '--deps', '1']);
      expect(await run(['set', '1', '--deps', '2']), 4);
      expect(err.single, contains('dependency cycle'));
      expect(err.single, contains('1 -> 2 -> 1'));
    });

    test('unknown command exits 2 and prints the cheatsheet', () async {
      await run(['init']);
      expect(await run(['frobnicate']), 2);
      expect(out.first, contains("unknown command 'frobnicate'"));
      expect(out.join('\n'), contains('goal set <id> [status]'));
    });

    test('no args and help print the cheatsheet with exit 0', () async {
      expect(await run([]), 0);
      expect(out.join('\n'), contains('exit codes: 0 ok'));
      out.clear();
      expect(await run(['help']), 0);
      expect(out.join('\n'), contains('goal ready'));
    });
  });

  group('complex scenarios', () {
    test('redispatch loop: fail -> note -> requeue -> done', () async {
      await run(['init']);
      await run(['add', 'hard bug']);
      await run(['set', '1', 'wip', '--agent', 'agent_dead']);
      // lane dies: redispatch requeues with a reason note
      await run(['set', '1', 'todo', 'lane dead, redispatch']);
      await run(['set', '1', 'wip', '--agent', 'agent_new']);
      await run(['set', '1', 'failed', 'root cause X unresolved']);
      await run(['set', '1', 'todo']);
      await run(['set', '1', 'done', 'fixed in a.dart']);
      final code = await run(['show', '1']);
      expect(code, 0);
      final text = out.join('\n');
      expect(text, contains('#1 [done]'));
      expect(text, contains('agent: -')); // cleared after leaving wip
      // every note survived in order
      expect(text.indexOf('lane dead'), lessThan(text.indexOf('root cause')));
      expect(text.indexOf('root cause'), lessThan(text.indexOf('fixed in')));
    });

    test('full lane lifecycle through list views', () async {
      await run(['init']);
      await run(['add', 'station 审计']);
      await run(['add', '修复转票']);
      await run(['set', '2', 'wip', '--agent', 'agent_rev']);
      await run(['list', 'wip']);
      expect(out.join('\n'), contains('agent_rev'));
      out.clear();
      await run(['ready']);
      expect(out.join('\n'), isNot(contains('修复转票')));
      expect(out.join('\n'), contains('station 审计'));
    });

    test('long titles are truncated, not wrapped, in list', () async {
      await run(['init']);
      final long = 'L' * 120;
      await run(['add', long]);
      await run(['list']);
      final row = out.first;
      expect(row.length, lessThan(120));
      expect(row.endsWith('L'), isTrue);
    });

    test('two sequential processes see each others writes', () async {
      await run(['init']);
      await run(['add', 'first process']);
      // separate invocation simulates another CLI process
      expect(await run(['list']), 0);
      expect(out.first, startsWith('#1 '));
    });

    test('markdown render keeps multiline content inside its bullet', () async {
      await run(['init']);
      await run(['add', 'title line1\n- forged item']);
      await run(['set', '1', 'wip', '-m', 'note line1\nnote line2']);
      expect(await run(['render']), 0);
      final lines = out.join('\n').split('\n');
      expect(lines, contains('- **#1** title line1'));
      // a title line that looks like a bullet is indented into the item,
      // never promoted to a top-level bullet of its own (the age tail rides
      // on the last title line)
      expect(lines, contains('  - forged item · 0s'));
      final noteLine = lines.firstWhere((l) => l.contains('note line1'));
      expect(noteLine.startsWith('  - ['), isTrue);
      expect(lines, contains('    note line2'));
    });

    test('deps and detail render in the active groups', () async {
      await run(['init']);
      await run(['add', 'a']);
      await run(['add', 'b', '--deps', '1', '-m', 'body line']);
      expect(await run(['render']), 0);
      final text = out.join('\n');
      expect(text, contains('· deps 1'));
      expect(text, contains('  > body line'));
    });

    test('pipes in parked content are escaped inside the table', () async {
      await run(['init']);
      await run(['add', 'a|b']);
      await run(['set', '1', 'parked', '-m', 'x|y']);
      expect(await run(['render']), 0);
      final text = out.join('\n');
      expect(text, contains(r'| #1 | - |  | a\|b | 0s | x\|y |'));
    });

    test('json render preserves multiline fields verbatim', () async {
      await run(['init']);
      await run(['add', 'two\nlines', '-m', 'd1\nd2']);
      await run(['set', '1', '-m', 'n1\nn2']);
      expect(await run(['render', '--json']), 0);
      final data = jsonDecode(out.join('\n')) as Map<String, dynamic>;
      final g = (data['goals'] as List).single as Map<String, dynamic>;
      expect(g['title'], 'two\nlines');
      expect(g['detail'], 'd1\nd2');
      expect((g['notes'] as List).single['text'] as String, 'n1\nn2');
    });
  });
}
