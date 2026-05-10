# Clipshow

![main screen](docs/readme/Selection_252.png)

**Clipshow** is a desktop Flutter app for managing, tagging, and playing video clip libraries for live streams and broadcasts. Everything lives in a **workspace** folder on disk: media files plus a local SQLite database (`obs_clipshow.db`) for tags, non-destructive clip ranges, and settings.

Use the dashboard to search, filter, create **clips** (in/out marks on a master file), and prepare material. **Manage** mode is for library work; **Capture** drives OBS recording into the workspace when you want new takes ingested automatically. **Playout** is a dedicated 16∶9 broadcast-style player for sending a master or clip to air—optionally switching OBS **program** scenes over WebSocket and firing **HTTP webhooks** on enter and exit. An on-screen **telestrator** draws over the picture during playout for commentary.

## Features

- Workspace-scoped library with background ingestion (common container formats under configurable ignored paths).
- File list with tag and text search, clip editing and bulk tagging.
- Playout with keyboard-driven seek help, end-of-file pause, and telestrator (colors, brush, undo).
- Optional OBS WebSocket integration: scene switches during playout and capture, recording path staging with copy-to-output ingest workflow.
- Optional webhooks with fixed **`video`** / **`face`** tokens for companion automation.
- Workspace settings (decoder tuning on Linux, JSON export of metadata).

## Requirements

- **Flutter** (see `pubspec.yaml` for the SDK constraint).
- **Desktop:** Linux and Windows are the current targets for this repository; building for other platforms may require extra validation.
- **FFmpeg:** `ffmpeg` and `ffprobe` on your `PATH` for thumbnails and duration probing—install via your OS package manager or [winget](https://winget.run/pkg/Gyan/FFmpeg) on Windows (`Gyan.FFmpeg`). Details are in [MANUAL.md](MANUAL.md) §2.2.
- **OBS Studio** only if you enable OBS capture or scene switching (WebSocket, typically port 4455).

## Run from source

From a checkout of this repository:

```bash
flutter pub get
flutter run -d linux    # or -d windows
```

Release builds follow the usual Flutter workflow for your target OS (`flutter build linux`, `flutter build windows`, etc.).

## Documentation

| Doc | Purpose |
| --- | --- |
| [MANUAL.md](MANUAL.md) | End-user manual (workspaces, dashboard, capture, playout, settings, export, troubleshooting). |
| [SPEC.md](SPEC.md) | Product specification and architecture notes for contributors. |

## Contributing

Use `dart analyze` (and your usual Flutter tests) before opening a pull request. Bugfixes should have tests where feasible. UI changes should update MANUAL.md.
