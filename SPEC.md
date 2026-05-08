# Product Specification: Vanalyst Playout & Telestration Client

## 1. System Overview
A custom, local desktop application built to serve as a unified media manager, video playout engine, and telestrator for a solo-operated live broadcast. The application interfaces with OBS Studio via WebSockets. It operates based on a "Workspace" concept, automatically tracking local media files and allowing the operator to cue highlights, trigger scene transitions, and draw over video playback from a single pane of glass without cluttering the OBS source list.

## 2. Technology Stack
* **Framework:** Flutter (Targeting Desktop OS: Windows/Linux)
* **Video Decoding:** `fvp` (Hardware-accelerated wrapper for `video_player` via FFmpeg)
* **OBS Integration:** `obs_websocket` (Standard JSON RPC payloads)
* **Database:** `sqflite`
* **Drawing Engine:** Flutter `CustomPaint`
* **File System:** `watcher` (Dart package for monitoring directory changes)

## 3. OBS Studio Configuration Requirements
The application requires a specific OBS scene architecture to function as intended.
* **WebSocket Server:** OBS WebSocket plugin enabled (Port 4455, authenticated).
* **Scene 1: "Face Scene"** Contains the primary camera capture and microphone inputs.
* **Scene 2: "Video Scene"** Contains a Window Capture source targeting the Flutter application window, scaled to fit the 1920x1080 canvas.

## 4. Workspace Management
* **Definition:** A Workspace is a root directory on the local file system containing all media assets for a specific project or match.
* **Database Location:** The application database (storing tags, clips, and metadata) is stored at the top level of this Workspace directory.
* **Background Ingestion:** A background file watcher monitors the Workspace root and all subdirectories. Dropping a new video file into any folder automatically creates a new, untagged master file entry in the database.

## 5. Application UI States
The application operates in two mutually exclusive UI states to prevent broadcast errors.

### State 1: Dashboard (Management Mode)
* **Purpose:** Media ingestion, tagging, and preparation. Not broadcasted.
* **Layout Structure:**
    * **Workspace Explorer (Left):** Displays the active workspace directory and auto-ingested master files.
    * **Tag Filtering (Top):** Quick-filter buttons based on assigned tags (e.g., "Stage 4", "John Doe"). Must include a dedicated "Untagged" filter to quickly process newly ingested files.
    * **Preview Window (Top Right):** Standard video player for reviewing master clips.
    * **Tagging Interface (Bottom Right):** UI to log `startTime` and `endTime` markers, assign a descriptive title, and apply multiple string-based tags.

### State 2: Playout (Broadcast Mode)
* **Purpose:** Live execution.
* **Trigger:** User clicks a saved "Clip" from the Dashboard.
* **Execution Sequence:**
    1. UI strips all dashboard elements.
    2. `fvp` widget expands to borderless fullscreen.
    3. App loads the master video file and executes `setRange(from, to)`.
    4. App sends WebSocket command to OBS: `SetCurrentProgramScene` -> "Video Scene".
    5. App begins playback.
* **Overlay:** A transparent `CustomPaint` layer becomes active, accepting mouse/touch drag inputs to draw telestration paths.
* **End of Clip Behavior:** Reaching the `endTime` marker pauses the video on the final frame, keeping the visual on screen to allow the operator to continue telestrating or providing commentary.
* **Reversion Sequence:**
    1. Triggered manually by the operator pressing the `Escape` key (or a designated hardware hotkey).
    2. App sends WebSocket command to OBS: `SetCurrentProgramScene` -> "Face Scene".
    3. App clears the `CustomPaint` canvas.
    4. App reverts to State 1 (Dashboard).

## 6. Core Data Model
The local database will manage the metadata independently of the physical file system. Each Clip Object contains the following properties:
* **clipId:** Unique identifier string.
* **masterFilePath:** Absolute or relative path to the source video within the Workspace.
* **clipTitle:** Operator-defined string for the highlight.
* **tags:** A list of strings (e.g., "Stage 1", "Shooter X", "B-Roll") for sorting and filtering.
* **startTimeMs:** Integer defining the start of the usable segment.
* **endTimeMs:** Integer defining the end of the usable segment.

## 7. Key Functional Requirements
* **Hardware Acceleration:** Video playback must utilize native hardware decoding (NVENC/QuickSync) to prevent the Flutter app from starving OBS of CPU resources.
* **Aspect Ratio Locking:** The application window must maintain or force a 16:9 aspect ratio during Playout State to prevent window capture stretching in OBS.
* **Audio Routing:** The application's audio output must be captured by OBS. (Requires virtual audio cables or OBS Application Audio Capture depending on the OS).
* **Non-Destructive Editing:** The application will not render new video files. All clips are virtual, defined strictly by the `setRange` timestamps on the master files.
* **Live File Watching:** The application must instantly reflect file additions or deletions within the Workspace without requiring a manual refresh.

## 8. Phased Implementation Plan
* **Phase 1: Workspace & Ingestion.** Implement the Workspace directory concept, the local database, and the background file watcher to auto-populate the UI with raw media.
* **Phase 2: Playout & OBS Control.** Build the basic `fvp` player, establish the OBS WebSocket connection, and successfully trigger scene transitions upon playout execution and `Escape` key reversion.
* **Phase 3: Tagging & Organization.** Build the UI to set timestamps, apply string tags, and filter the dashboard view.
* **Phase 4: Telestration.** Layer the `CustomPaint` widget over the fullscreen video player, implement stroke paths, and map a hotkey to clear the canvas.
* **Phase 5: Configuration.** Add an application configuration UI for selecting and validating the target OBS scenes in an existing OBS project (e.g., pick Program Video Scene and Face Scene from current scene list, store preferences, and fail safely if scenes are missing/renamed).

## 9. Progress (Current)
### Completed
* **Phase 1 Core Delivered:** Workspace selection and restore, SQLite database creation at workspace root, recursive ingestion scan, and live watcher updates for add/remove/modify.
* **Ingestion Logging:** Added structured logging around workspace restore, ingestion startup, file event handling, and dashboard media updates.
* **Thumbnail Pipeline:** Video thumbnails are generated using `ffprobe` + `ffmpeg`, stored as `<video>.thumb.jpg`, removed on file delete, and displayed in the left file list.
* **Dashboard Restructure (Phase 3 Foundation):** Dashboard uses a three-panel layout: file list (left), preview panel (top right), and tag panel (bottom right), with file selection and playout actions.
* **Tagging and Organization Delivered:** Clips persist to SQLite with title, start/end range, and tags; saved clips list from the current workspace is rendered and updated; saved tags can be re-applied through the clipping flow.
* **Filters, Search, and Autocomplete:** Tag filters include `All` and `Untagged`; search and tag autocomplete support faster clip discovery and consistent tagging.
* **Preview/Playout Player Refactor:** Shared clip player and hotkey handling were refactored for reuse across dashboard preview and playout with cleaner separation of concerns.
* **Phase 2 Core Implemented:** OBS websocket service and playout scene-switch flow are integrated (start -> `"Video Scene"`, `Escape` exit -> `"Face Scene"`), with playout help/hotkeys surfaced in the UI.
* **Playout Window Behavior:** Playout defaults to windowed 16:9 with hidden title bar (fullscreen retained as a configurable code path), and window bounds restore on exit.
* **Telestrator Overlay Delivered:** Playout includes a draw layer with clear/visibility hotkeys, HUD visibility behavior, and lifecycle handling so overlay state resets correctly on exit.
* **Seek and Clamp Behavior Updated:** Seek mappings now include Alt micro-seek in addition to short/standard/long jumps, and clip-range seeking clamps correctly at segment bounds.

### Implemented Interaction Details
* **Keyboard Controls:** `Space` play/pause, `Left/Right` standard seek, `Shift+Left/Right` short seek, `Ctrl+Left/Right` long seek, and `Alt+Left/Right` micro-seek.
* **Mouse Controls:** Clicking video toggles play/pause.
* **Playout UX:** Temporary help/hotkey hint appears at playout start and auto-hides; HUD behavior aligns with telestrator interaction state.
* **Dashboard UX:** Scroll position is preserved and restored after returning from playout.

### Partially Complete / Next
* **Deeper Validation:** Full end-to-end live OBS verification and stress testing are still required.
* **Focused Test Coverage:** Additional automated tests are still needed for tag/save/search flows, seek/clamp boundaries, and telestrator hotkey/HUD behavior.
* **Phase 2 Validation Checklist (Live OBS):**
  * Confirm OBS websocket authentication/connectivity using configured host/port/password.
  * Enter playout from dashboard and verify scene switches to configured Video Scene.
  * Press `Escape` in playout and verify scene switches back to configured Face Scene.
  * Verify no stuck state after repeated enter/exit cycles (scene changes, window state, and app input all recover correctly).
  * Validate behavior when OBS is unavailable or scenes are missing (user-visible warning, no app crash, and clean return path).
