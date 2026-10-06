import 'package:goal/goal.dart';
import 'package:goal/src/cli/format.dart' show cell, trunc, oneline, textLines;
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 10, 6, 12);

  group('age boundaries', () {
    DateTime at(int secondsAgo) => now.subtract(Duration(seconds: secondsAgo));

    test('seconds below one minute', () {
      expect(age(at(0), now), '0s');
      expect(age(at(1), now), '1s');
      expect(age(at(59), now), '59s');
    });

    test('minutes below one hour', () {
      expect(age(at(60), now), '1m');
      expect(age(at(3599), now), '59m');
    });

    test('hours below one day', () {
      expect(age(at(3600), now), '1h');
      expect(age(at(86399), now), '23h');
    });

    test('days', () {
      expect(age(at(86400), now), '1d');
      expect(age(at(30 * 86400), now), '30d');
    });

    test('future timestamps clamp to zero', () {
      expect(age(now.add(const Duration(minutes: 5)), now), '0s');
    });
  });

  group('trunc and cell', () {
    test('short strings pass through', () {
      expect(trunc('abc', 5), 'abc');
      expect(trunc('abcde', 5), 'abcde');
    });

    test('long strings are hard cut', () {
      expect(trunc('abcdef', 5), 'abcde');
    });

    test('cell pads to fixed width', () {
      expect(cell('ab', 4), 'ab  ');
      expect(cell('abcdef', 4), 'abcd');
    });

    test('truncation never splits a surrogate pair', () {
      // 60 runes, 61 code units: a code-unit cut would break the emoji
      final t = 'a' * 59 + '😀';
      expect(trunc(t, 60), t);
      expect(trunc('😀😀😀', 2), '😀😀');
    });

    test('truncation never splits a grapheme cluster', () {
      const family = '👨‍👩‍👧‍👦'; // 7 runes, 1 grapheme
      expect(trunc('${'a' * 39}$family tail', 40), '${'a' * 39}$family');
      // base + combining mark: rune cuts could orphan the harakat
      const pair = '\u0628\u064E';
      expect(trunc('X' * 38 + pair * 10, 40), 'X' * 38 + pair * 2);
      // flag emoji = 2 runes, 1 grapheme
      const flag = '🇸🇦';
      expect(trunc(flag * 5, 3), '$flag$flag$flag');
    });
  });

  group('oneline', () {
    test('newlines, tabs and CR collapse to single spaces', () {
      expect(oneline('a\nb'), 'a b');
      expect(oneline('a\r\nb'), 'a b');
      expect(oneline('a\rb'), 'a b');
      expect(oneline('a\t\tb'), 'a b');
      expect(oneline('a \n b'), 'a b');
    });

    test('ANSI escape sequences are removed', () {
      expect(oneline('\x1B[31mred\x1B[0m'), 'red');
      expect(oneline('a\x1B[2Kb'), 'a b');
    });

    test('other control characters become spaces', () {
      expect(oneline('a\x00b'), 'a b');
      expect(oneline('a\x07b'), 'a b');
      expect(oneline('a\x7Fb'), 'a b');
    });

    test('Unicode line separators collapse to spaces', () {
      expect(oneline('a\u2028b'), 'a b');
      expect(oneline('a\u2029b'), 'a b');
      expect(oneline('a\u0085b'), 'a b');
    });

    test('clean text passes through unchanged', () {
      expect(oneline('Fix Scroll Overflow'), 'Fix Scroll Overflow');
      expect(oneline('修复滚动溢出'), '修复滚动溢出');
      // RTL text and zero-width joiners are content, not structure
      expect(oneline('إصلاح الدخول'), 'إصلاح الدخول');
      expect(oneline('نیم\u200Cفاصله'), 'نیم\u200Cفاصله');
    });
  });

  group('textLines', () {
    test('splits on LF, CRLF and lone CR', () {
      expect(textLines('a\nb'), ['a', 'b']);
      expect(textLines('a\r\nb'), ['a', 'b']);
      expect(textLines('a\rb'), ['a', 'b']);
      expect(textLines('single'), ['single']);
      expect(textLines(''), ['']);
    });

    test('splits on Unicode line and paragraph separators', () {
      expect(textLines('a\u2028b'), ['a', 'b']);
      expect(textLines('a\u2029b'), ['a', 'b']);
      expect(textLines('a\u0085b'), ['a', 'b']);
    });
  });

  group('stamps', () {
    test('stamp is MM-DD HH:mm zero padded', () {
      expect(stamp(DateTime(2026, 1, 2, 3, 4)), '01-02 03:04');
    });

    test('fullStamp includes seconds', () {
      expect(fullStamp(DateTime(2026, 1, 2, 3, 4, 5)), '2026-01-02 03:04:05');
    });
  });

  group('GoalStatus parsing', () {
    test('canonical names case insensitive', () {
      expect(GoalStatus.tryParse('todo'), GoalStatus.todo);
      expect(GoalStatus.tryParse('WIP'), GoalStatus.wip);
      expect(GoalStatus.tryParse(' Done '), GoalStatus.done);
    });

    test('emoji aliases from the legacy ledger', () {
      expect(GoalStatus.tryParse('⬜'), GoalStatus.todo);
      expect(GoalStatus.tryParse('🚧'), GoalStatus.wip);
      expect(GoalStatus.tryParse('✅'), GoalStatus.done);
      expect(GoalStatus.tryParse('⛔'), GoalStatus.blocked);
      expect(GoalStatus.tryParse('❌'), GoalStatus.failed);
      expect(GoalStatus.tryParse('📦'), GoalStatus.parked);
    });

    test('word aliases', () {
      expect(GoalStatus.tryParse('open'), GoalStatus.todo);
      expect(GoalStatus.tryParse('complete'), GoalStatus.done);
      expect(GoalStatus.tryParse('completed'), GoalStatus.done);
      expect(GoalStatus.tryParse('fail'), GoalStatus.failed);
      expect(GoalStatus.tryParse('park'), GoalStatus.parked);
      expect(GoalStatus.tryParse('block'), GoalStatus.blocked);
    });

    test('garbage is null, never a silent guess', () {
      for (final bad in ['donex', 'd', 'to', '', 'don']) {
        expect(GoalStatus.tryParse(bad), isNull, reason: bad);
      }
    });

    test('emoji mapping for render', () {
      expect(GoalStatus.todo.emoji, '⬜');
      expect(GoalStatus.wip.emoji, '🚧');
      expect(GoalStatus.done.emoji, '✅');
      expect(GoalStatus.blocked.emoji, '⛔');
      expect(GoalStatus.failed.emoji, '❌');
      expect(GoalStatus.parked.emoji, '📦');
    });
  });

  group('GoalPriority parsing', () {
    test('accepts p0..p3 with dash and case', () {
      expect(GoalPriority.tryParse('p0'), GoalPriority.p0);
      expect(GoalPriority.tryParse('-p2'), GoalPriority.p2);
      expect(GoalPriority.tryParse('P3'), GoalPriority.p3);
    });

    test('rejects everything else', () {
      for (final bad in ['p4', 'p', '', '2', 'pri']) {
        expect(GoalPriority.tryParse(bad), isNull, reason: bad);
      }
    });

    test('display and rank', () {
      expect(GoalPriority.p2.toString(), 'P2');
      expect(GoalPriority.p0.rank < GoalPriority.p3.rank, isTrue);
    });
  });

  group('GoalEntry copyWith', () {
    final base = GoalEntry(
      id: '1',
      status: GoalStatus.wip,
      title: 't',
      agent: 'agent_x',
      priority: GoalPriority.p1,
      createdAt: now,
      updatedAt: now,
    );

    test('agent clears only via flag', () {
      expect(base.copyWith(status: GoalStatus.done).agent, 'agent_x');
      expect(
        base.copyWith(status: GoalStatus.done, clearAgent: true).agent,
        isNull,
      );
      // re-setting agent after clear works
      expect(base.copyWith(clearAgent: true, agent: 'y').agent, 'y');
    });

    test('priority clears only via flag', () {
      expect(base.copyWith(title: 'x').priority, GoalPriority.p1);
      expect(base.copyWith(clearPriority: true).priority, isNull);
    });

    test('equality by id', () {
      expect(base == base.copyWith(title: 'other'), isTrue);
      expect(
        base ==
            GoalEntry(
                id: '2',
                status: GoalStatus.todo,
                title: 't',
                createdAt: now,
                updatedAt: now),
        isFalse,
      );
    });
  });

  group('GoalNote', () {
    test('copyWith', () {
      final n = GoalNote(at: now, text: 'a');
      expect(n.copyWith(text: 'b').text, 'b');
      expect(n.copyWith().at, now);
    });
  });

  group('footerCounts', () {
    test('skips zero groups and keeps canonical order', () {
      final counts = {
        GoalStatus.todo: 3,
        GoalStatus.wip: 2,
        GoalStatus.done: 0,
        GoalStatus.blocked: 0,
        GoalStatus.failed: 0,
        GoalStatus.parked: 145,
      };
      expect(
        footerCounts(counts),
        '-- 2 wip | 3 todo | 145 parked',
      );
    });

    test('empty ledger', () {
      expect(
        footerCounts({for (final s in GoalStatus.values) s: 0}),
        '-- 0 tickets',
      );
    });
  });

  group('listLine', () {
    test('fixed columns and title truncation', () {
      final long = 'X' * 80;
      final line = listLine(
        GoalEntry(
          id: 'station213',
          status: GoalStatus.wip,
          title: long,
          agent: 'agent_9f3c',
          createdAt: now,
          updatedAt: now,
        ),
        now,
      );
      expect(line.startsWith('station213  '), isTrue);
      expect(line.contains(' wip    '), isTrue);
      expect(line.contains('agent_9f3c'), isTrue);
      expect(line.endsWith('X' * 60), isTrue);
    });

    test('multiline and control characters cannot break the row', () {
      final line = listLine(
        GoalEntry(
          id: '1',
          status: GoalStatus.todo,
          title: 'first\nsecond\tthird\x1B[31m',
          agent: 'lane\none',
          createdAt: now,
          updatedAt: now,
        ),
        now,
      );
      expect(line.contains('\n'), isFalse);
      expect(line.contains('\t'), isFalse);
      expect(line.contains('\x1B'), isFalse);
      expect(line, contains('first second third'));
      expect(line, contains('lane one'));
    });

    test('a long emoji title truncates on a rune boundary', () {
      final line = listLine(
        GoalEntry(
          id: '1',
          status: GoalStatus.todo,
          title: 'x' * 59 + '😀',
          createdAt: now,
          updatedAt: now,
        ),
        now,
      );
      expect(line.endsWith('😀'), isTrue);
    });
  });
}
