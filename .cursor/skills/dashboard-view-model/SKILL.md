---
name: dashboard-view-model
description: >-
  Patterns for dashboard_view_model.dart: state flags, ingestion, playout
  coordination, and avoiding duplicate sources of truth. Use when adding or
  refactoring dashboard state, media selection, preview gates, or repository wiring.
---

# Dashboard View Model

`lib/src/features/dashboard/dashboard_view_model.dart` is large and central. Prefer extending existing patterns over new parallel flag sets.

## Before adding state

- [ ] Search for an existing field or `Notifier` / listener pattern that already covers the concern (e.g. playout active, selection, preview init timing).
- [ ] Keep **OBS / scene** transitions decoupled from heavy **video** work where the codebase already does so.

## Data flow

- [ ] Prefer **`MediaRepository`** (and related data classes) for persistence and scanning; avoid embedding SQL or paths in the view model beyond orchestration.
- [ ] If behavior touches **playout** or **preview**, read `video-playout-lifecycle` rule and `playout-clip-player-hotkeys` skill.

## Verification

- [ ] `dart analyze` on the view model and any widgets that consume new API.
- [ ] Smoke: dashboard list updates, playout enter/exit, preview selection still coherent.
