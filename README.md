<p align="center"><img src="doc/logo.png" width="160" alt="goal logo"></p>

# goal

Track goals and tasks from the command line. Built for AI agents, and for
the people who work with them.

[简体中文](README.zh-CN.md) | English

<p align="center">
<a href="https://pub.dev/packages/goal"><img src="https://img.shields.io/pub/v/goal.svg" alt="pub version"></a>
<a href="https://pub.dev/packages/goal/score"><img src="https://img.shields.io/pub/points/goal.svg" alt="pub points"></a>
<a href="https://github.com/fluttercandies/goal/actions"><img src="https://img.shields.io/github/actions/workflow/status/fluttercandies/goal/ci.yml?branch=main" alt="ci"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
</p>

## Install

```bash
dart pub global activate goal
```

Requires Dart 3.4 or later.

## Quick start

```bash
$ goal init
ok ledger at .goal

$ goal add "Fix login crash on iOS" -p1 --round R12
ok #1 created (todo) round=R12 Fix login crash on iOS

$ goal set 1 wip --agent agent_a
ok 1 todo -> wip

$ goal set 1 done "fixed login.dart; flutter test green"
ok 1 wip -> done +note

$ goal add "Add offline mode" -p2
ok #2 created (todo) Add offline mode

$ goal ready
2  P2  todo  5m  -  Add offline mode
-- 1 ready
```

## Commands

| command | what it does |
| --- | --- |
| `goal init` | create a ledger in `./.goal` (once per project) |
| `goal add <title>` | add a ticket; flags: `-p0..-p3` `--deps a,b` `--round R` `-m <text>` |
| `goal set <id> [status] [note...]` | update a ticket — change status, add a note, set `--agent`, `--deps`, `--round`, `-pN`. No arguments = heartbeat. |
| `goal list [filters]` | list tickets. Filter by bare words: status, round, priority, `#id`, or title text — combined freely (`goal list wip R12`). The same filters accept flags: `-pN` `--round <R>` `--id <id>` |
| `goal ready` | todo tickets whose dependencies are all done, highest priority first |
| `goal show <id>` | everything about one ticket |
| `goal render [-o file] [--json]` | export a readable markdown view, or JSON |
| `goal archive [--dry-run]` | move done tickets out of the active ledger; `--dry-run` previews what would move |

Statuses: `todo` `wip` `done` `blocked` `failed` `parked`.

Notes are timestamped and append-only — use them for settlement details:
files changed, verification commands, evidence links.

```bash
$ goal set 3 done "files: a.dart, b.dart; verify: dart test; evidence: docs/3.png"
```

Long notes can be piped in to avoid quoting trouble: `goal set 3 done -m -`
reads the note from stdin.

## Dependencies

A ticket with `--deps` waits until every dependency is `done` (or archived)
before it shows up in `goal ready`. Cycles are rejected outright.

```bash
$ goal add "Re-review fix" --deps 3
$ goal ready          # empty until ticket 3 is done
```

## Where is my data?

Everything lives in `./.goal/` next to your project. Add `.goal/` to your
`.gitignore`. Point `GOAL_HOME` elsewhere if you want it out of the repo.

Done tickets are moved to the archive by `goal archive`; the active ledger
stays small. `goal render` gives you a markdown or JSON snapshot at any time.

## License

MIT
