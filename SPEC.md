# Product Specification: Vanalyst Playout & Telestration Client

## 1. System Overview
A custom, local desktop application built to serve as a unified media manager, video playout engine, and telestrator for a solo-operated live broadcast. The application interfaces with **OBS Studio** via WebSockets. **Optional HTTP webhooks** can also be called on playout and OSG Mode transitions (fixed `video` / `face` / `osg_on` / `osg_off` tokens) for external automation. It operates based on a "Workspace" concept, automatically tracking local media files and allowing the operator to cue highlights, trigger scene transitions, and draw over video playback from a single pane of glass without cluttering the OBS source list.

## 2. Technology Stack
* **Framework:** Flutter (targeting desktop OS: Windows/Linux)
* **Video decoding:** `fvp` (hardware-accelerated wrapper for `video_player` via FFmpeg); decoder profiles and verbosity are configurable per workspace
* **FFmpeg (CLI):** `ffmpeg` / `ffprobe` for thumbnails, duration and frame-rate probing, and bake one-pass seek + raw-RGBA overlay encode
* **OBS integration:** `obs_websocket` (JSON-RPC–style requests such as `SetCurrentProgramScene`, `GetCurrentProgramScene`, `GetSceneItemId`, `SetSceneItemEnabled`, `SetRecordDirectory`, `StartRecord`, `StopRecord`)
* **Database:** `sqflite` with **`sqflite_common_ffi`** on desktop (SQLite file per workspace)
* **Drawing engine:** Flutter `CustomPaint` with gesture-driven strokes (mouse/touch pan)
* **File system:** `watcher` for monitoring directory changes
* **Windowing:** `window_manager` for aspect ratio, optional fullscreen, title bar visibility, bounds restore

## 3. OBS Studio Configuration Requirements
The application expects a practical OBS scene layout; **Video** and **Face** program scene names are configurable in workspace settings (defaults below). OSG Mode optionally enables a **named source** on whatever scene is currently program.
* **WebSocket server:** OBS WebSocket plugin enabled (default port **4455**, password as configured in the app).
* **Scene: "Face Scene" (default name):** Primary camera and microphone inputs (return target after clip playout).
* **Scene: "Video Scene" (default name):** A source that shows the app (e.g. Window Capture on the Flutter window), scaled to fit the program canvas (e.g. 1920×1080). Used during clip playout.
* **OSG overlay source (optional):** A scene item (typically Window Capture of the Clipshow window, or a nested scene containing that capture) with a configured **source name**. The operator places that same-named item on every program scene used when entering OSG Mode. Clipshow enables the item on the **current** program scene on enter and disables that same item on exit; program scene is not changed. Enter fails with an error if the source is missing from the current scene.

## 4. Workspace Management
* **Definition:** A Workspace is a root directory on the local file system containing all media assets for a specific project or match.
* **Database location:** The SQLite database file is **`obs_clipshow.db`** at the top level of the workspace directory. It stores master files, clips, tags, tag sets, saved tags, workspace settings (including OBS profiles, webhooks, capture paths, ignored folders, telestrator defaults, decoder options, default clip volume, OSG config, and bake recipes JSON), and related metadata.
* **Background ingestion:** A file watcher plus scanning keeps the database in sync with the workspace tree. New video files under the workspace (respecting **ignored** paths such as the capture **recording** staging folder) get a **master** row; deletes and changes are reflected without a manual refresh. **MODIFY** watch events are **debounced** (~2s quiet) so large in-progress copies do not spam upsert/ffprobe/UI reloads.

## 5. Application UI States
The application operates in mutually exclusive UI states to prevent broadcast errors.

### State 1: Dashboard (Management Mode)
* **Purpose:** Media ingestion, tagging, tag-set preparation, and OSG priming. Not broadcasted.
* **Layout structure:**
    * **Workspace header (top):** Current workspace path, open-folder and **Reveal On Filesystem** (opens the workspace directory in the system file manager), **Workspace settings**, and optional **OBS connection** status when an OBS profile is enabled.
    * **Main row:** A **left** column and a **right** column.
    * **Files (left card):** At the top of this card: **tag search** (with autocomplete to add filter chips), **filename or full-workspace path search** (toggleable), an **Untagged** filter chip, and **active tag filter** chips. Below that, the scrollable list of master files and saved clips (thumbnails, play actions, etc.).
    * **Right column (tabs):** **Manage** — video preview (top) and a resizable split to the **tagging** panel (bottom): mark in/out, optional display name, tags, save-clip flow, and preview actions (**Trash File** moves the master to system/workspace trash then deletes the DB row; if the file is already missing, a follow-up confirm offers DB-only removal of the master and cascaded clips; also **Playout**, **Record**, **Bake** and **Export OSG Graphics** when recipes exist). **Capture** — **OBS Capture Mode** in place of Preview+tagging: start/stop recording via WebSocket, **recording folder** (under workspace, ignored during writes) and **output folder** (empty = workspace root); after stop, the finished file is **copied** to the output folder so ingestion sees it once; tags from the panel are applied to the new **master** at stop time. **Bake Queue** (visible when the workspace has bake recipes) — start/pause the bake runner, view running/pending/finished tasks. **Tag Sets** — create and tag **bare tag sets** (no video), assign quick slots (keys 1–5 in OSG Mode), and **Enter OSG Mode**.

### Workspace settings (capture)
* **OBS:** Configured **Video** / **Face** scenes (names), optional **OSG overlay source** name, connection host/port/password, plus optional **Capture** scene (program scene switched before recording when set).
* **Capture paths:** **Recording folder** (relative, default `recordings`) is kept in **ignored folders** so partial files do not spam ingest; **output folder** (relative, empty = workspace root) receives the copy after recording stops and the staging file is removed. **Output** must not lie inside the **recording** directory tree (validated in app).
* **Playout record paths:** **Staging** (default `recordings/export`) and **output** (default `export`) for Record playout; both ignored when under the workspace. **Output** must not lie inside **staging**.
* **Ignored-path seeding:** A new workspace DB inserts default ignored folders **`recordings`** and **`export`**. Existing DBs pick up **`export`** once on schema upgrade to v14. Operators may remove those entries to ingest Capture staging exceptions or Record/Bake output; **workspace open does not re-add them**. **Save Paths** always ensures **capture recording** and **playout staging** (in-progress files). **Playout output** is auto-ignored only when that path **changes** to a new value—not on every save—so removing `export` (or a custom output ignore) sticks.

### Live OBS validation (capture mode)
* Configure recording/output folders; confirm the recording path (e.g. `recordings`) appears in **ignored folders** when applicable.
* Start recording from the Capture tab; verify OBS writes only under the staging folder.
* Stop recording; verify the file appears at the output path, a **master** row exists, tags are applied, and OBS’s **recording directory** is restored to its previous value.

### State 2: Playout (broadcast mode)
* **Purpose:** Live execution.
* **Trigger:** User runs a **saved clip** from the dashboard (e.g. play action on a clip row).
* **Execution sequence (actual order):**
    1. Dashboard is replaced by the playout surface (no dashboard chrome).
    2. The window is sized to **Playout canvas size** (`PlayoutOutputSize` from workspace settings): exact logical width×height in windowed mode, OS aspect-ratio lock from that canvas, **title bar hidden**. **Fullscreen** exists as an alternate code path, not the default. Prior window bounds are remembered for restore on exit.
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

### State 3: OSG Mode (graphics mode)
* **Purpose:** Graphics-only output driven by a **tag set** (semantic tags + workspace OSG presets). No video decoder. Transparent window background for OBS Window Capture as an overlay source.
* **Trigger:** **Enter OSG Mode** on the Dashboard **Tag Sets** tab (requires **OSG Mode enabled** in workspace settings and at least one tag set).
* **Execution sequence:**
    1. If an **OSG overlay source** is configured (OBS profile enabled + non-empty source name), resolve that source on the **current** OBS program scene (`GetCurrentProgramScene` + `GetSceneItemId`). If missing, abort enter with an operator-visible error (no OSG Mode UI).
    2. Dashboard is replaced by the OSG Mode surface (transparent background).
    3. Same window sizing rules as playout (**Playout canvas size**, hidden title bar).
    4. After the first frame paints, enable the resolved scene item (`SetSceneItemEnabled`) and/or invoke webhooks with an **`osg_on`** token. Program scene is unchanged. When overlay automation is not configured, only webhooks run (if any).
    5. Operator toggles OSG presets with **6–0** and switches tag sets with **1–5** (quick slots configured on the Tag Sets tab).
* **Reversion:** **`Escape`** → disable the **same** scene item that was enabled on enter (cached scene + item id), fire **`osg_off`** webhooks, then Dashboard restore (same window restore as playout exit). Does **not** switch OBS program to Face.

### Record playout (OBS export)
* **Purpose:** Produce a shareable video file (OBS-encoded program output) from a clip or master playout session—OSGs, telestrator, and live voiceover via the OBS audio chain—without offline ffmpeg rendering.
* **Trigger:** **Record** on the dashboard preview action bar (same selection rules as **Playout**; requires an **enabled** OBS profile). Does **not** switch to the Capture scene; records while the **Video** scene is program.
* **Paths (workspace-relative, separate from Capture):** Default staging **`recordings/export`** (OBS writes in-progress files); default output **`export`** (finished file copied on exit). Default **`export`** is ignored on new workspaces (and once on upgrade). Staging is kept ignored via **Save Paths**; output ignore is not forced on every open/save so operators can remove it to ingest baked/recorded files. Output must not lie inside the staging tree.
* **OBS sequence:** After first-frame-ready + **Video** scene: **`SetRecordDirectory`** (staging), **`StartRecord`**. On **`Escape`**: **`StopRecord`** → copy to output (staging file removed) → restore record directory → **Face** scene + window restore.
* **Post-export:** SnackBar with **Reveal** to open the file in the system file manager. No library ingest or tag application.
* **Conflicts:** Blocked when Capture recording is active, a playout record session is already active, or OBS reports record already active.

### Bake export (offline OSG composite)
* **Purpose:** Produce a shareable MP4 from a clip or master with **on-screen graphics** composited in per a **bake recipe**—offline `ffmpeg` rendering, not OBS program capture.
* **Trigger:** **Bake** on the dashboard preview action bar (requires at least one **bake recipe** in workspace settings). Operator picks **Queue** or **Now** per recipe.
* **Recipe:** Named workspace setting (`osg.bakeRecipes` JSON) listing **cues**: each cue binds an **OSG preset slot** to a visible window between **start** and **end** anchors (clip start/end, absolute ms from clip start, or offset ms from clip end).
* **Validation:** At enqueue time, each cue’s preset **required semantic tags** must be satisfied on the target media row; otherwise the job is rejected with an error (no partial queue).
* **Pipeline:** One-pass `ffmpeg`: seek/limit the master (`-ss`/`-t`), scale/letterbox to playout canvas, overlay OSG frames streamed as raw straight RGBA on stdin (`OsgFrameRenderer.renderFrameRawRgba`, dart:ui). Static hold/empty spans reuse the previous overlay buffer (visibility fingerprint) without re-rasterizing; enter/exit still render every frame. Encode once (H.264 + AAC) → copy to **playout output** folder (default `export`, same as Record playout) as `{displayName}_baked.mp4` with numeric dedup suffix. Temp work dir deleted afterward.
* **Queue:** Session-scoped pending/running/finished task lists; **Pause** stops dequeuing (in-flight bake continues); **Now** inserts at queue head and bypasses pause. Cancel cooperates at safe checkpoints during render/ffmpeg. Running (and **Now** dialog) show **frame-stream progress** (`framesDone`/`frameCount` from the stdin overlay loop).
* **Post-export:** SnackBar with **Reveal**; no library ingest.

### OSG graphic export (ZIP)
* **Purpose:** Hand off hold-state OSG pixels and timing metadata to an external NLE—no ffmpeg video composite.
* **Trigger:** **Export OSG Graphics** on the dashboard preview action bar (requires bake recipes; same semantic-tag validation as Bake). Operator picks a recipe, then a save path via file dialog.
* **Output:** ZIP containing `manifest.json` (`osgGraphicExportSchemaVersion` 2) and one transparent PNG per distinct cued slot (`osg6.png` … `osg0.png`) at **Playout canvas size**. PNGs are **hold state** (fully visible, no motion offset), rendered by `OsgFrameRenderer.renderSlotHoldStatePng`.
* **Manifest:** Per slot: `frameNorm`, `frameCanvasPx`, `layerOpacity`, `enter`/`exit` motion blocks (`slideDistanceNorm`, `slideDistanceCanvasPx`, `durationMs`, `fadeDurationMs`, easing), `cues` (raw `OsgBakeAnchor` JSON plus resolved ms and animation bounds), resolved text. Root includes recipe id/name, canvas size, and source clip `displayName`, `fileName`, `workspaceRelativePath`, `inMs`/`outMs`/`durationMs` (same duration probe as bake). Fade and slide both start together; when `fadeDurationMs` < `durationMs` and motion is not fade-only, opacity completes in the first fade window while slide continues for the full duration.
* **Post-export:** SnackBar with **Reveal**; no library ingest.

## 6. Core Data Model
Metadata lives in SQLite; masters and clips are normalized.

* **Master media (`master_media_files`):** Workspace-relative **`file_path`**, **`file_name`**, optional **`display_name_override`**, file stats, optional **`duration_ms`**, optional readability/issue fields.
* **Clip (`clips`):**
    * **`id`:** Integer primary key (application “clip id”).
    * **`master_media_id`:** Foreign key to the source master row (not a redundant path string on the clip).
    * **`display_name_override`:** Optional operator label for the clip in lists (separate from filename).
    * **`in_ms` / `out_ms`:** Integers; **in** is required; **out** nullable (open-ended segment).
    * **`created_at_ms`:** Creation time.
* **Tags:** Normalized **`tags`** table and **`media_tags`** linking **masters**, **clips**, or **tag sets** to tag names for filtering, organization, and OSG semantic resolution.
* **Tag set (`tag_sets`):** Named, video-less entity with optional **`annotations`** and tag attachments (same **`media_tags`** pattern as clips). Used to drive OSG Mode without a master file.
* **Bake recipe (`osg.bakeRecipes` workspace setting):** JSON array of named recipes with **`cues`** referencing **`OsgPresetSlot`** and **`OsgBakeAnchor`** time ranges. Not a SQLite table; stored in workspace settings KV.

Logical “clip” fields map as: **master path** via join to master row; **title** from **`display_name_override`** or derived display rules; **tags** via **`media_tags`**; range from **`in_ms` / `out_ms`**.

## 7. Key Functional Requirements
* **Hardware acceleration:** Playback uses **`fvp`** with configurable decoder profiles (exact codecs depend on OS/GPU; workspace settings expose ordering and diagnostics).
* **Playout canvas / window sizing:** In playout and OSG Mode, the OS window is sized and aspect-locked to workspace **Playout canvas size** (`PlayoutOutputSize`; default **1920×1080**). Any width×height is valid—not limited to 16:9. Decoded video uses **`BoxFit.contain`** (letterboxing/pillarboxing when source aspect differs). OSG and telestrator composite over the **full canvas** (normalized 0..1), including gutters—not only the fitted video rect.
* **Audio routing:** Application audio should be capturable by OBS (virtual audio or **Application Audio Capture**, OS-dependent—the app does not install drivers).
* **Non-destructive editing:** Clips in the library are **virtual** in/out bounds on masters. Optional **bake** and **Record playout** produce rendered files outside ingest paths; they do not alter master rows.
* **Session clip volume:** Shared 0.0–1.0 volume for preview and playout; workspace **default** persisted (`playback.defaultClipVolume`); per-session nudge/mute not persisted.
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
* **Dashboard layout:** Header plus **left** file list (**Reveal On Filesystem** on master rows via icon or context menu; **Go to Source Master** on clip rows clears the Show Clips filter when needed, scrolls the master into view, or SnackBars if other filters still hide it; workspace folder reveal in the header) and **right** tab column (Manage, Capture, Bake Queue when recipes exist, Tag Sets); preview vs tagging split; capture tab; bake queue panel.
* **OBS capture mode:** Preview vs Capture tab; **`SetRecordDirectory`**, optional capture scene, **`StartRecord`** / **`StopRecord`**, copy from staging to output (staging file removed), tags on new master; restore OBS record directory after stop.
* **Record playout export:** Preview **Record** button; OBS record during Video-scene playout; copy to playout output on exit; ignored folders; reveal-in-folder SnackBar.
* **Bake export:** Preview **Bake** button; offline one-pass ffmpeg with streamed OSG overlays; bake recipes and queue in dashboard; semantic-tag validation at enqueue; output to playout output folder.
* **OSG graphic export:** Preview **Export OSG Graphics** button; hold-state PNGs + manifest ZIP via `OsgGraphicExportService`; same semantic validation and clip duration probe as bake.
* **OSG Mode:** Tag Sets tab; transparent graphics surface; optional OBS **overlay source** enable on current program + **`osg_on`** webhook on enter; disable that item + **`osg_off`** webhook on exit; tag-set quick slots **1–5**, preset toggles **6–0**.
* **Tagging and organization:** Clips in SQLite with **in/out**, tags, optional display names; saved clips and saved-tag workflows.
* **Filters, search, and autocomplete:** **Untagged** filter and tag filter chips; with **no** filters applied, all matching items are shown (there is no separate **All** chip). Filename/path search and tag search autocomplete.
* **Preview/playout player:** Shared **`ClipPlayerView`** and hotkey layers for dashboard preview and playout.
* **Phase 2 core:** OBS service and **optional webhook** scene switching on enter (**video**) / exit (**face**); defaults **Video Scene** / **Face Scene** overridable in settings; playout help and hotkeys in UI.
* **Phase 4 (telestrator):** Delivered in playout with lifecycle-safe reset on exit.
* **Playout window:** Windowed size and aspect lock from **Playout canvas size**; hidden title bar; **fullscreen** optional in code; bounds/maximize restore on exit. Video letterboxed inside the canvas (`BoxFit.contain`).
* **Telestrator overlay:** Draw layer, HUD, clear/undo/colors/brush hotkeys, visibility toggle.
* **Seek and clamp:** Arrow seeks (with modifiers), Alt micro-seek, and clamping at segment bounds.
* **Workspace settings & export:** Telestrator defaults, decoder preferences, MDK/fvp logging options, OBS + webhook profiles, capture paths, ignored folders, JSON export.
* **Display names & clip UX:** Overrides for masters and clips, search considers display names, range nudging in preview.
* **Playout canvas size:** Top-level **Workspace Settings** control for logical width/height (default **1920×1080**; any aspect ratio). Windowed playout and OSG Mode set the OS window to **that exact size in logical pixels** and apply the matching aspect-ratio constraint. Manage preview centers an **AspectRatio** frame at the same aspect with a visible border. Video uses **`BoxFit.contain`** inside the canvas; OSG and telestrator use normalized coords on the **full canvas** (gutters included).
* **On-screen graphics (OSG):** Up to **five** presets stored in workspace settings (template image path under `osg/`, normalized **0..1** frame and text slots; `osgPresetSchemaVersion` **11**). Slots use **fixed** text or text resolved from **tag semantic types** on the current playout media row. Each preset has **show/hide motion** (fade-only or fade+slide), full **enter/exit duration**, and optional **fade duration** (≤ full duration, used when motion includes a slide; fade and slide start together, fade may finish early). **Semantic types** are defined in the OSG editor and stored in SQLite (`tag_semantic_types`); each **`media_tags`** row may carry an optional **`semantic_type_id`** (per attachment). Preview, playout, and OSG Mode hotkeys **`6`–`0`** toggle presets **1–5** (above video, below telestrator in playout). Workspace JSON export includes `playoutOutput`, `osgPresets`, `tagSemanticTypes`, and per-item **`tagRows`**.
* **Clip volume:** Default workspace volume; **↑** / **↓** ±10% and **M** mute in preview and playout hotkey layers; session-only adjustments.
* **Tag chip context menu:** Secondary click on a tag chip (file list or tag panel): **Edit tag value** (rename on that media item while keeping semantic type), assign or **clear semantic type**, or **bulk** assign a semantic type to all attachments sharing that canonical tag.

### Implemented interaction details
* **Keyboard (preview and playout hotkey layers):** **`Space`** play/pause. **`Left` / `Right`** seek **±1 s**. **`Shift` + arrows** seek **±15 s**. **`Ctrl` + arrows** seek **±5 s**. **`Alt` + arrows** seek **±100 ms**. **`Home` / `End`** seek to clip start/end where implemented. **`↑` / `↓`** volume **±10%**; **`M`** mute toggle. In **playout**, preview, and **OSG Mode**, **`6`–`0`** toggle OSG presets **1–5**; in **OSG Mode**, **`1`–`5`** select tag-set quick slots.
* **Mouse:** In **dashboard preview**, clicking the video toggles play/pause. In **playout**, click-to-toggle is **off** by default (telestrator layer and defaults); use **Space** or on-screen affordances for playback control.
* **Playout UX:** Short hint at start (e.g. Escape to return), optional help overlay; HUD reflects telestrator state.
* **Dashboard UX:** File list **scroll offset** is saved before playout and **restored** after exit.

### Partially complete / next (post–initial implementation)
* **Deeper validation:** End-to-end live OBS verification and stress testing.
* **Focused test coverage:** Expand automated tests for tag/save/search, seek/clamp, workspace settings/export, playout and telestrator regressions.