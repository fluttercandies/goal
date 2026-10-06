# Changelog

All notable changes to this package are documented in this file.

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
