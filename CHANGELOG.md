# Changelog

All notable changes to this package are documented in this file.

## 1.0.0 - 2026-10-06

Initial stable release.

- Commands: `init`, `add`, `set`, `list`, `ready`, `show`, `render`, `archive`.
- Tickets with status (`todo`/`wip`/`done`/`blocked`/`failed`/`parked`),
  priority (P0–P3), rounds, dependencies, lane owners and timestamped notes.
- Ready-set computation, dependency cycle detection, archive lifecycle.
- `render` produces a human-readable markdown view or a JSON backup.
- Library API (`package:goal/goal.dart`) alongside the `goal` executable.
