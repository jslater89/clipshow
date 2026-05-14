---
name: obs-websocket-integration
description: >-
  Reminders for OBS WebSocket usage: ordering, idempotency, and real-instance
  validation. Use when changing obs_websocket calls, scene switching, sources,
  or app.dart playout exit paths that talk to OBS.
---

# OBS WebSocket Integration

## Design

- [ ] **Order matters**: e.g. ensure scene or collection state is valid before assuming a source exists; match patterns already used in the codebase for connect / reconnect / errors.
- [ ] **Failures**: network drops and OBS restarts happen; avoid leaving local UI state inconsistent with OBS (clear flags, surface errors, retry where the app already does).

## Validation

- [ ] Agents cannot fully simulate OBS; note in PR or summary what should be **checked manually** against a running OBS instance (scene name, hotkey flow, playout enter/exit).

## Related code

- Search for `obs_websocket`, `ObsWebSocket`, or workspace/playout services that wrap RPC calls before adding parallel call sites.
