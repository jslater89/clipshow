# Product Specification: Vanalyst Playout & Telestration Client

## 1. System Overview
A custom, local desktop application built to serve as a unified media manager, video playout engine, and telestrator for a solo-operated live broadcast. The application interfaces with **OBS Studio** via WebSockets. **Optional HTTP webhooks** can also be called on playout enter/exit (fixed `video` / `face` scene tokens) for external automation. It operates based on a "Workspace" concept, automatically tracking local media files and allowing the operator to cue highlights, trigger scene transitions, and draw over video playback from a single pane of glass without cluttering the OBS source list.

## 2. Technology Stack
* **Framework:** Flutter (targeting desktop OS: Windows/Linux)
* **Video decoding:** `fvp` (hardware-accelerated wrapper for `video_player` via FFmpeg); decoder profiles and verbosity are configurable per workspace
* **OBS integration:** `obs_websocket` (JSON-RPC–style requests such as `SetCurrentProgramScene`, `SetRecordDirectory`, `StartRecord`, `StopRecord`)
* **Database:** `sqflite` with **`sqflite_common_ffi`** on desktop (SQLite file per workspace)
* **Drawing engine:** Flutter `CustomPaint` with gesture-driven strokes (mouse/touch pan)
* **File system:** `watcher` for monitoring directory changes
* **Windowing:** `window_manager` for aspect ratio, optional fullscreen, title bar visibility, bounds restore

## 3. OBS Studio Configuration Requirements
The application expects a practical OBS scene layout; **Video** and **Face** scene names are configurable in workspace settings (defaults below).
* **WebSocket server:** OBS WebSocket plugin enabled (default port **4455**, password as configured in the app).
* **Scene: "Face Scene" (default name):** Primary camera and microphone inputs.
* **Scene: "Video Scene" (default name):** A source that shows the app (e.g. Window Capture on the Flutter window), scaled to fit the program canvas (e.g. 1920×1080).

## 4. Workspace Management
* **Definition:** A Workspace is a root directory on the local file system containing all media assets for a specific project or match.
* **Database location:** The SQLite database file is **`obs_clipshow.db`** at the top level of the workspace directory. It stores master files, clips, tags, saved tags, workspace settings (including OBS profiles, webhooks, capture paths, ignored folders, telestrator defaults, decoder options), and related metadata.
* **Background ingestion:** A file watcher plus scanning keeps the database in sync with the workspace tree. New video files under the workspace (respecting **ignored** paths such as the capture **recording** staging folder) get a **master** row; deletes and changes are reflected without a manual refresh.

## 5. Application UI States
The application operates in two mutually exclusive UI states to prevent broadcast errors.

### State 1: Dashboard (Management Mode)
* **Purpose:** Media ingestion, tagging, and preparation. Not broadcasted.
* **Layout structure:**
    * **Workspace header (top):** Current workspace path, open-folder and **Workspace settings** actions, and optional **OBS connection** status when an OBS profile is enabled.
    * **Main row:** A **left** column and a **right** column.
    * **Files (left card):** At the top of this card: **tag search** (with autocomplete to add filter chips), **filename or full-workspace path search** (toggleable), an **Untagged** filter chip, and **active tag filter** chips. Below that, the scrollable list of master files and saved clips (thumbnails, play actions, etc.).
    * **Right column (tabs):** **Preview** — video preview (top) and a resizable split to the **tagging** panel (bottom): mark in/out, optional display name, tags, and save-clip flow. **Capture** — **OBS Capture Mode** in place of Preview+tagging: start/stop recording via WebSocket, **recording folder** (under workspace, ignored during writes) and **output folder** (empty = workspace root); after stop, the finished file is **copied** to the output folder so ingestion sees it once; tags from the panel are applied to the new **master** at stop time.

### Workspace settings (capture)
* **OBS:** Configured **Video** / **Face** scenes (names), connection host/port/password, plus optional **Capture** scene (program scene switched before recording when set).
* **Capture paths:** **Recording folder** (relative, default `recordings`) is kept in **ignored folders** so partial files do not spam ingest; **output folder** (relative, empty = workspace root) receives the copy after recording stops and the staging file is removed. **Output** must not lie inside the **recording** directory tree (validated in app).
* **Playout record paths:** **Staging** (default `recordings/export`) and **output** (default `export`) for Record playout; both ignored when under the workspace. **Output** must not lie inside **staging**.

### Live OBS validation (capture mode)
* Configure recording/output folders; confirm the recording path (e.g. `recordings`) appears in **ignored folders** when applicable.
* Start recording from the Capture tab; verify OBS writes only under the staging folder.
* Stop recording; verify the file appears at the output path, a **master** row exists, tags are applied, and OBS’s **recording directory** is restored to its previous value.

### State 2: Playout (broadcast mode)
* **Purpose:** Live execution.
* **Trigger:** User runs a **saved clip** from the dashboard (e.g. play action on a clip row).
* **Execution sequence (actual order):**
    1. Dashboard is replaced by the playout surface (no dashboard chrome).
    2. The window is sized for **16:9**, **title bar hidden**, and **windowed** by default (**fullscreen** exists as an alternate code path, not the default). Prior window bounds are remembered for restore on exit.
    3. The player loads the master file, seeks to the clip **in** time, and applies range behavior by **seeking** and **progress/clamp logic** (pause/hold at the **out** point)—there is **no** separate `setRange` API; range is enforced in the player layer.
    4. The player loads and seeks; after the **first video frame** is scheduled to paint, **scene switching** runs: for each **enabled** profile, the app connects to OBS and sends **`SetCurrentProgramScene`** to the configured **Video** scene name, and/or invokes configured **webhook** URLs with a **`video`** token. If no profile is enabled, scene switching is skipped (logged only). **Record playout** starts OBS recording immediately after that scene switch (not before).
    5. Playback runs (autoplay); a telestrator layer may sit above the video when enabled.
* **Overlay:** When the telestrator is enabled, a transparent stack with **`CustomPaint`** receives pan gestures for strokes (when disabled, pointer events pass through to the video stack).
* **End of clip behavior:** At the configured **out** time (or end of file when no out point), playback **pauses** and the frame **holds** so the operator can keep drawing or talking over the image.
* **Reversion sequence:**
    1. Operator presses **`Escape`** (handled in playout).
    2. **Record playout only:** If a Record session is active, **`StopRecord`**, wait for the file on disk, copy to the configured **playout output** folder, restore OBS’s **recording directory**—**before** switching away from the Video scene.
    3. **Scene switching:** **`SetCurrentProgramScene`** to the configured **Face** scene name and/or webhooks with a **`face`** token (same rules as enter).
    4. Window state is restored (fullscreen off, title bar restored, aspect constraint cleared, bounds/maximize restored as applicable).
    5. Playout is torn down (telestrator strokes are discarded with the widget tree).
    6. Dashboard returns; **scroll position** is restored when possible.

### Record playout (OBS export)
* **Purpose:** Produce a shareable video file (OBS-encoded program output) from a clip or master playout session—OSGs, telestrator, and live voiceover via the OBS audio chain—without offline ffmpeg rendering.
* **Trigger:** **Record** on the dashboard preview action bar (same selection rules as **Playout**; requires an **enabled** OBS profile). Does **not** switch to the Capture scene; records while the **Video** scene is program.
* **Paths (workspace-relative, separate from Capture):** Default staging **`recordings/export`** (OBS writes in-progress files); default output **`export`** (finished file copied on exit). Paths are auto-added to **ignored folders** when saved unless already covered by an existing ignored prefix (e.g. **`recordings/`** covers **`recordings/export`**). Output must not lie inside the staging tree.
* **OBS sequence:** After first-frame-ready + **Video** scene: **`SetRecordDirectory`** (staging), **`StartRecord`**. On **`Escape`**: **`StopRecord`** → copy to output (staging file removed) → restore record directory → **Face** scene + window restore.
* **Post-export:** SnackBar with **Reveal** to open the file in the system file manager. No library ingest or tag application.
* **Conflicts:** Blocked when Capture recording is active, a playout record session is already active, or OBS reports record already active.

## 6. Core Data Model
Metadata lives in SQLite; masters and clips are normalized.

* **Master media (`master_media_files`):** Workspace-relative **`file_path`**, **`file_name`**, optional **`display_name_override`**, file stats, optional **`duration_ms`**, optional readability/issue fields.
* **Clip (`clips`):**
    * **`id`:** Integer primary key (application “clip id”).
    * **`master_media_id`:** Foreign key to the source master row (not a redundant path string on the clip).
    * **`display_name_override`:** Optional operator label for the clip in lists (separate from filename).
    * **`in_ms` / `out_ms`:** Integers; **in** is required; **out** nullable (open-ended segment).
    * **`created_at_ms`:** Creation time.
* **Tags:** Normalized **`tags`** table and **`media_tags`** linking **masters** or **clips** to tag names for filtering and organization.

Logical “clip” fields map as: **master path** via join to master row; **title** from **`display_name_override`** or derived display rules; **tags** via **`media_tags`**; range from **`in_ms` / `out_ms`**.

## 7. Key Functional Requirements
* **Hardware acceleration:** Playback uses **`fvp`** with configurable decoder profiles (exact codecs depend on OS/GPU; workspace settings expose ordering and diagnostics).
* **Aspect ratio locking:** In playout, the window is constrained to **16:9** (plus optional fullscreen path) so OBS window capture stays predictable.
* **Audio routing:** Application audio should be capturable by OBS (virtual audio or **Application Audio Capture**, OS-dependent—the app does not install drivers).
* **Non-destructive editing:** No rendered output files for clips. Highlight segments are **virtual**, defined by **in/out millisecond bounds** on existing masters.
* **Live file watching:** Workspace changes propagate without requiring a manual refresh (subject to ignored paths and ingest pause options during preview/playout).

## 8. Phased Implementation Plan
* **Phase 1: Workspace & ingestion.** Workspace directory, local DB at workspace root, watcher-driven ingest.
* **Phase 2: Playout & OBS control.** `fvp`-based player, WebSocket connection, scene transitions on enter/exit, Escape to return.
* **Phase 3: Tagging & organization.** Timestamps, string tags, filters, search, saved clips list.
* **Phase 4: Telestration.** Draw layer over the playout video, gestures + hotkeys (clear, undo, colors, brush, visibility).
* **Phase 5: Configuration.** Workspace settings for OBS (and webhooks), capture paths, ignored folders, telestrator defaults, decoders, export, display names, etc.

## 9. Progress (Current)

**Implementation status:** The capabilities described in this document—including phased milestones through configuration-heavy workspace settings, **OBS and webhook** scene switching, capture mode, export, **display-name** overrides, thumbnails, and related polish—are **implemented**. Remaining effort is validation, automated tests, live OBS stress checks, and product polish—not missing core features.

### Completed
* **Phase 1 core:** Workspace selection and restore, **`obs_clipshow.db`** at workspace root, recursive ingest, watcher-driven updates for add/remove/modify.
* **Ingestion logging:** Structured logging for workspace restore, ingest lifecycle, file events, and dashboard updates.
* **Thumbnail pipeline:** `ffprobe` + `ffmpeg`, sidecar **`<video>.thumb.jpg`**, cleanup on delete, thumbs in the file list.
* **Dashboard layout:** Header plus **left** file list and **right** Preview/Capture column; preview vs tagging split; capture tab.
* **OBS capture mode:** Preview vs Capture tab; **`SetRecordDirectory`**, optional capture scene, **`StartRecord`** / **`StopRecord`**, copy from staging to output (staging file removed), tags on new master; restore OBS record directory after stop.
* **Record playout export:** Preview **Record** button; OBS record during Video-scene playout; copy to playout output on exit; ignored folders; reveal-in-folder SnackBar.
* **Tagging and organization:** Clips in SQLite with **in/out**, tags, optional display names; saved clips and saved-tag workflows.
* **Filters, search, and autocomplete:** **Untagged** filter and tag filter chips; with **no** filters applied, all matching items are shown (there is no separate **All** chip). Filename/path search and tag search autocomplete.
* **Preview/playout player:** Shared **`ClipPlayerView`** and hotkey layers for dashboard preview and playout.
* **Phase 2 core:** OBS service and **optional webhook** scene switching on enter (**video**) / exit (**face**); defaults **Video Scene** / **Face Scene** overridable in settings; playout help and hotkeys in UI.
* **Phase 4 (telestrator):** Delivered in playout with lifecycle-safe reset on exit.
* **Playout window:** Default **windowed 16:9**, hidden title bar; **fullscreen** optional in code; bounds/maximize restore on exit.
* **Telestrator overlay:** Draw layer, HUD, clear/undo/colors/brush hotkeys, visibility toggle.
* **Seek and clamp:** Arrow seeks (with modifiers), Alt micro-seek, and clamping at segment bounds.
* **Workspace settings & export:** Telestrator defaults, decoder preferences, MDK/fvp logging options, OBS + webhook profiles, capture paths, ignored folders, JSON export.
* **Display names & clip UX:** Overrides for masters and clips, search considers display names, range nudging in preview.
* **Playout canvas size:** Top-level **Workspace Settings** control for logical width/height (default **1920×1080**). Windowed playout sets the OS window to **that exact size in logical pixels** (same aspect ratio constraint); the video stack fills the client area **without** an outer scale-down. Video uses uniform `BoxFit.contain` inside the frame (letterboxing if source aspect differs).
* **On-screen graphics (OSG):** Up to **three** presets stored in workspace settings (template image path under `osg/`, normalized **0..1** frame and text slots). Slots use **fixed** text or text resolved from **tag semantic types** on the current playout media row. **Semantic types** are defined in the OSG editor and stored in SQLite (`tag_semantic_types`); each **`media_tags`** row may carry an optional **`semantic_type_id`** (per attachment). Playout hotkeys **`8` / `9` / `0`** toggle presets **1 / 2 / 3** (above video, below telestrator). Workspace JSON export includes `playoutOutput`, `osgPresets`, `tagSemanticTypes`, and per-item **`tagRows`**.
* **Tag chip context menu:** Secondary click on a tag chip (file list or tag panel): **Edit tag value** (rename on that media item while keeping semantic type), assign or **clear semantic type**, or **bulk** assign a semantic type to all attachments sharing that canonical tag.

### Implemented interaction details
* **Keyboard (preview and playout hotkey layers):** **`Space`** play/pause. **`Left` / `Right`** seek **±1 s**. **`Shift` + arrows** seek **±15 s**. **`Ctrl` + arrows** seek **±5 s**. **`Alt` + arrows** seek **±100 ms**. **`Home` / `End`** seek to clip start/end where implemented. In **playout**, **`8` / `9` / `0`** toggle OSG presets **1–3**.
* **Mouse:** In **dashboard preview**, clicking the video toggles play/pause. In **playout**, click-to-toggle is **off** by default (telestrator layer and defaults); use **Space** or on-screen affordances for playback control.
* **Playout UX:** Short hint at start (e.g. Escape to return), optional help overlay; HUD reflects telestrator state.
* **Dashboard UX:** File list **scroll offset** is saved before playout and **restored** after exit.

### Partially complete / next (post–initial implementation)
* **Deeper validation:** End-to-end live OBS verification and stress testing.
* **Focused test coverage:** Expand automated tests for tag/save/search, seek/clamp, workspace settings/export, playout and telestrator regressions.