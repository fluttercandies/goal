# Changelog

All notable changes to this package are documented in this file.

## 1.1.0 - 2026-10-06

- `render` redesigned: a status dashboard table up top, `` `P1` ``/`` `R798` ``
  badges, deps and detail in the active groups, and a compact aligned index
  table for the parked group (pipes in content are escaped so the table
  survives any input).
- Note timestamps now carry the year and seconds (`[2026-10-06 13:48:44]`)
  in both `render` and `show`.
- Within a group, tickets of equal priority are ordered oldest-stuck first.
- New `rm` command deletes a ticket (journaled; ids are never reused) for
  genuine mis-files like duplicates or accidental adds.
- `set --title` and `set --detail` correct a ticket's title/body after the
  fact (`-` reads from stdin like `-m`); receipts report the new value.
- Archived tickets are no longer invisible: `show <id>` resolves them with an
  `[archived]` tag, and `render --json` includes an `archive` section, so a
  history audit never needs a hive dump.
- `--help`/`-h` now works in any argument position (`goal set --help`).
- Unknown `--deps` ids warn immediately at `add`/`set` time — not only in
  the next `ready` footer.
- An audit-journal write failure degrades to a warning on stderr: the hive
  ledger is authoritative, so a journal gap never fails (and never fakes a
  failure for) an operation whose data write already succeeded.

## 1.0.1 - 2026-10-06

- Regenerated `doc/logo.png` with a transparent background: the previous
  rasterizer flattened the rounded corners to opaque white.

## 1.0.0 - 2026-10-06

Initial stable release.

- Commands: `init`, `add`, `set`, `list`, `ready`, `show`, `render`, `archive`.
- Tickets with status (`todo`/`wip`/`done`/`blocked`/`failed`/`parked`),
  priority (P0–P3), rounds, dependencies, lane owners and timestamped notes.
- Ready-set computation, dependency cycle detection, archive lifecycle.
- `render` produces a human-readable markdown view or a JSON backup.
- Library API (`package:goal/goal.dart`) alongside the `goal` executable.
- One-shot friendly input: bare words join into one title, and receipts state
  the new values (`+agent=…`, `+deps=…`, `+note="…"`) so no follow-up command
  is needed to verify a change.
- Multiline and control-character content is stored verbatim while receipts,
  list rows and the markdown render stay single-line and structurally valid;
  empty input (blank title, empty note, empty round) fails with a tutorial
  message instead of being silently dropped.
