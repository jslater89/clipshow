---
name: playout-clip-player-hotkeys
description: >-
  Checklist for ClipPlayerView lifecycle, hotkeys, seek/play races, and
  dashboard preview vs playout. Use when editing clip_player_view.dart,
  playout_screen, playout hotkeys, or preview video after playout exit.
---

# Playout, ClipPlayerView, and Hotkeys

## Lifecycle

- [ ] After any `await`, check **`mounted`** before `setState` or using `VideoPlayerController`.
- [ ] Do not require **synchronous** full dispose before leaving playout if that would delay OBS scene switch; prefer staggering preview init or similar if two decoders would overlap.
- [ ] Playout and dashboard preview may use different **`ClipPlayerView`** options; avoid coupling preview-only gates to playout unless required.

## Playback edge cases

- [ ] **Linux / EOS**: completed playback can leave the engine ignoring seeks until `play` then seek; see comments in `clip_player_view.dart` for `_reachedEnd` / natural-end pause behavior.
- [ ] **Hotkeys** that call `seekBy` without awaiting: ensure play/pause paths drain pending seeks (`_seekTail` pattern) before starting playback.

## Verification

- [ ] `dart analyze` on `lib/src/features/playout/` and any dashboard preview files touched.
- [ ] Quick manual: exit playout → dashboard preview shows selected clip without freeze; hotkey seek/play during clip.
