import 'dart:io';

import 'package:goal/goal.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String home;
  final now = DateTime(2026, 10, 6, 12);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('goal_store_');
    home = '${tmp.path}/.goal';
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // hive lock cleanup can race the delete; OS temp dirs are self-cleaning
    }
  });

  Future<GoalStore> create() async {
    final s = await GoalStore.open(home, create: true);
    addTearDown(s.close);
    return s;
  }

  group('ledger lifecycle', () {
    test('init twice fails', () async {
      final s = await create();
      await s.close();
      await expectLater(create(), throwsA(isA<GoalError>()));
    });

    test('open without ledger fails with tutorial message', () async {
      try {
        await GoalStore.open('${tmp.path}/nowhere');
        fail('should throw');
      } on GoalError catch (e) {
        expect(e.code, GoalErrorCode.notFound);
        expect(e.message, contains('goal init'));
      }
    });

    test('existsAt detects ledger by box files', () async {
      expect(GoalStore.existsAt(home), isFalse);
      final s = await create();
      await s.close();
      expect(GoalStore.existsAt(home), isTrue);
    });

    test('torn init (meta record missing) fails with a repair hint', () async {
      final s = await create();
      await s.close();
      File('$home/meta.hive').deleteSync();
      try {
        await GoalStore.open(home);
        fail('should throw');
      } on GoalError catch (e) {
        expect(e.code, GoalErrorCode.usage);
        expect(e.message, contains('goal init'));
      }
    });
  });

  group('id allocation', () {
    test('auto ids increment monotonically', () async {
      final s = await create();
      expect((await s.add(title: 'a', now: now)).id, '1');
      expect((await s.add(title: 'b', now: now)).id, '2');
      expect(s.meta.nextId, 3);
      await s.close();
    });

    test('ids are never reused across archives', () async {
      final s = await create();
      final e = await s.add(title: 'first', now: now);
      await s.put(e.copyWith(status: GoalStatus.done));
      await s.archiveDone();
      expect((await s.add(title: 'next', now: now)).id, '2');
      await s.close();
    });

    test('blank titles are rejected at the store level', () async {
      final s = await create();
      try {
        await s.add(title: '   ', now: now);
        fail('should throw');
      } on GoalError catch (e) {
        expect(e.code, GoalErrorCode.usage);
        expect(e.message, contains('title cannot be empty'));
      }
      expect((await s.add(title: '\nline one\nline two\n', now: now)).title,
          '\nline one\nline two\n');
      await s.close();
    });
  });

  group('resolve', () {
    test('exact ids resolve, misses list recent ids', () async {
      final s = await create();
      await s.add(title: 'a', now: now);
      await s.add(title: 'b', now: now);

      expect(s.resolve('1').title, 'a');
      expect(s.resolve('2').title, 'b');
      try {
        s.resolve('999');
        fail('should throw');
      } on GoalError catch (e) {
        expect(e.code, GoalErrorCode.notFound);
        expect(e.message, contains('recent ids'));
        expect(e.message, contains('1 2'));
      }
      await s.close();
    });

    test('not found lists recent ids', () async {
      final s = await create();
      await s.add(title: 'a', now: now);
      await s.add(title: 'b', now: now);
      try {
        s.resolve('9999');
        fail('should throw');
      } on GoalError catch (e) {
        expect(e.code, GoalErrorCode.notFound);
        expect(e.message, contains('1 2'));
      }
      await s.close();
    });

    test('archived ids are read-only', () async {
      final s = await create();
      final e = await s.add(title: 'done thing', now: now);
      await s.put(e.copyWith(status: GoalStatus.done));
      await s.archiveDone();
      try {
        s.resolve(e.id);
        fail('should throw');
      } on GoalError catch (e) {
        expect(e.message, contains('archived'));
      }
      expect(s.isArchived(e.id), isTrue);
      await s.close();
    });
  });

  group('ready set', () {
    test('gated by unfinished deps, sorted by priority then age', () async {
      final s = await create();
      final blocker = await s.add(title: 'blocker', now: now);
      await s.add(title: 'none', now: now);
      await s.add(title: 'p3', priority: GoalPriority.p3, now: now);
      await s.add(title: 'p1', priority: GoalPriority.p1, now: now);
      await s.add(title: 'waiting', deps: [blocker.id], now: now);

      expect(
        s.ready().map((e) => e.title).toList(),
        ['p1', 'p3', 'blocker', 'none'],
      );

      await s.put(blocker.copyWith(status: GoalStatus.done));
      // blocker itself is done now: none, p1, p3 and waiting are ready
      expect(s.ready().length, 4);
      await s.close();
    });

    test('same priority sorts oldest first', () async {
      final s = await create();
      final older = await s.add(
        title: 'older',
        now: now.subtract(const Duration(hours: 2)),
      );
      final newer = await s.add(title: 'newer', now: now);
      expect(s.ready().first.id, older.id);
      expect(s.ready().last.id, newer.id);
      await s.close();
    });

    test('unknown deps are tolerated and reported', () async {
      final s = await create();
      await s.add(title: 'ghost', deps: ['missing-1'], now: now);
      final missing = <String>{};
      expect(s.ready(missingDeps: missing).single.title, 'ghost');
      expect(missing, {'missing-1'});
      await s.close();
    });

    test('archived dep counts as satisfied', () async {
      final s = await create();
      final dep = await s.add(title: 'dep', now: now);
      await s.add(title: 'child', deps: [dep.id], now: now);
      await s.put(dep.copyWith(status: GoalStatus.done));
      await s.archiveDone();
      expect(s.ready().map((e) => e.title), ['child']);
      await s.close();
    });
  });

  group('dependency cycles', () {
    test('two node cycle reports the path', () async {
      final s = await create();
      final a = await s.add(title: 'a', now: now);
      final b = await s.add(title: 'b', deps: [a.id], now: now);
      try {
        await s.put(a.copyWith(deps: [b.id]));
        fail('should throw');
      } on GoalError catch (e) {
        expect(e.code, GoalErrorCode.conflict);
        expect(e.message, contains('1'));
        expect(e.message, contains('2'));
      }
      await s.close();
    });

    test('self dependency is a cycle', () async {
      final s = await create();
      final a = await s.add(title: 'a', now: now);
      await expectLater(
        s.put(a.copyWith(deps: ['1'])),
        throwsA(isA<GoalError>()),
      );
      await s.close();
    });

    test('three node cycle detects at the closing edge', () async {
      final s = await create();
      await s.add(title: 'a', now: now);
      await s.add(title: 'b', deps: ['1'], now: now);
      final c = await s.add(title: 'c', deps: ['2'], now: now);
      await expectLater(
        s.put(s.get('1')!.copyWith(deps: [c.id])),
        throwsA(isA<GoalError>()),
      );
      await s.close();
    });
  });

  group('archive', () {
    test('moves only done, leaves wip/todo in place', () async {
      final s = await create();
      final done = await s.add(title: 'done', now: now);
      await s.put(done.copyWith(status: GoalStatus.done));
      await s.add(title: 'wip', now: now);
      await s.add(title: 'todo', now: now);

      final moved = await s.archiveDone();
      expect(moved.map((e) => e.id), [done.id]);
      expect(s.all.map((e) => e.title).toSet(), {'wip', 'todo'});
      expect(await s.archiveDone(), isEmpty);
      await s.close();
    });

    test('journal records archived ids', () async {
      final s = await create();
      final e = await s.add(title: 'd', now: now);
      await s.put(e.copyWith(status: GoalStatus.done));
      await s.archiveDone();
      await s.close();
      final last = File('$home/events.jsonl')
          .readAsLinesSync()
          .where((l) => l.isNotEmpty)
          .last;
      expect(last, contains('"op":"archive"'));
      expect(last, contains(e.id));
    });
  });

  group('meta', () {
    test('currentRound propagates to subsequent adds', () async {
      final s = await create();
      await s.add(title: 'a', round: 'R799', now: now);
      final b = await s.add(title: 'b', now: now);
      expect(b.round, 'R799');
      expect(s.meta.currentRound, 'R799');
      // explicit --round overrides
      final c = await s.add(title: 'c', round: 'R800', now: now);
      expect(c.round, 'R800');
      expect(s.meta.currentRound, 'R800');
      await s.close();
    });

    test('statusCounts tallies the active ledger', () async {
      final s = await create();
      await s.add(title: 'a', now: now);
      final b = await s.add(title: 'b', now: now);
      await s.put(b.copyWith(status: GoalStatus.parked));
      final counts = s.statusCounts();
      expect(counts[GoalStatus.todo], 1);
      expect(counts[GoalStatus.parked], 1);
      expect(counts[GoalStatus.done], 0);
      await s.close();
    });
  });

  group('persistence', () {
    test('full field round-trip through reopen', () async {
      final s = await create();
      await s.add(
        title: 'persist 中文标题 ✅',
        detail: 'line1\nline2',
        round: 'R798',
        deps: const ['2'],
        priority: GoalPriority.p2,
        now: now,
      );
      final e = await s.add(title: 'notes', now: now);
      await s.put(
        e.copyWith(
          status: GoalStatus.wip,
          agent: 'agent_9f3c',
          notes: [
            GoalNote(at: now, text: '第一条'),
            GoalNote(at: now, text: 'second note'),
          ],
        ),
      );
      await s.close();

      final s2 = await GoalStore.open(home);
      addTearDown(s2.close);
      final all = s2.all;
      expect(all.length, 2);
      expect(all.first.title, 'persist 中文标题 ✅');
      expect(all.first.detail, 'line1\nline2');
      expect(all.first.priority, GoalPriority.p2);
      expect(all.first.deps, ['2']);
      final second = all.last;
      expect(second.status, GoalStatus.wip);
      expect(second.agent, 'agent_9f3c');
      expect(second.notes.map((n) => n.text), ['第一条', 'second note']);
      expect(s2.meta.nextId, 3);
      expect(s2.meta.currentRound, 'R798');
      await s2.close();
    });

    test('journal is append-only jsonl in op order', () async {
      final s = await create();
      final e = await s.add(title: 'j', now: now);
      await s.put(e.copyWith(status: GoalStatus.wip));
      await s.close();
      final ops = File('$home/events.jsonl')
          .readAsLinesSync()
          .where((l) => l.isNotEmpty)
          .map((l) => l.contains('"op":"init"')
              ? 'init'
              : l.contains('"op":"add"')
                  ? 'add'
                  : 'set')
          .toList();
      expect(ops, ['init', 'add', 'set']);
    });
  });
}
