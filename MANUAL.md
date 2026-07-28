# User Manual

**Clipshow** is a desktop app and a local tool for managing, tagging, and playing clip libraries for streaming broadcasts. Beyond the library itself, you can optionally connect it to OBS Studio over WebSocket (scene switches and capture recording) and to HTTP webhooks for other tools, triggering actions on playout. Optional **on-screen graphics** can overlay template artwork and text on the picture in preview and playout (§10). During playout you can use an on-screen **telestrator** for commentary-style markup. **Bake** can render clips with graphics composited into a shareable file offline.

---

## 1. What this app is for

The dashboard is where you work inside a workspace folder: supported videos are discovered and indexed, you search and tag items, preview them, and define **non-destructive clips** (in and out times on the same master file rather than exporting a separate cut). That mode is aimed at organizing and preparing material rather than sending picture to air.

Playout is dedicated playback of a master or a saved clip in a window sized to your workspace **Playout canvas size** (§11.1; default 1920×1080). The canvas aspect ratio is not fixed—video is letterboxed inside that frame rather than stretched. Driving the stream stack is separate: when you enable them in workspace settings, entering and leaving playout can optionally switch OBS program scenes directly via its WebSocket API, and/or call HTTP webhooks so other software can react to the same transitions.

While playout is active, the telestrator lets you draw on top of the picture for analysis or emphasis; the drawing layer sits above the player and does not produce a rendered output file by itself.

Optionally, from the dashboard Capture flow you can start and stop OBS recording into a staging folder, then copy the finished file into an output location and remove the staging copy so the library ingests it once without duplicates or partial recordings in the staging tree. **Bake** and **Record** playout export are separate ways to produce shareable video files without cutting the library master on disk.

---

## 2. Requirements

### 2.1 Machine and OS

Clipshow targets desktop Windows and Linux as built for this project. Smooth playback depends on your GPU and drivers; in practice the player stack favors hardware-backed decoding where it is available. Adjust decoder-related options under Workspace settings if you need to tune behavior on your machine.

> **TODO (Windows):** Revisit this section after Windows builds are validated—confirm playback, paths, capture, and any OS-specific notes.

### 2.2 FFmpeg

Clipshow shells out to `**ffmpeg`** and `**ffprobe`** for thumbnails and duration probing; both must be discoverable on your `**PATH**` (see §13 if they seem missing). Install FFmpeg using your platform’s usual package manager—the commands below install the suite that includes both binaries.

**Linux:** On Debian or Ubuntu, run `sudo apt update` then `sudo apt install ffmpeg`. On Fedora, use `sudo dnf install ffmpeg`. On Arch Linux, use `sudo pacman -S ffmpeg`. Other distributions ship FFmpeg under the same name in their repos.

**Windows:** With **winget**, run `winget install -e --id Gyan.FFmpeg` from PowerShell or Command Prompt (elevated if your policy requires it). Open a **new** terminal afterward so `PATH` picks up the install, then confirm with `ffmpeg -version` and `ffprobe -version`.

**macOS:** With **Homebrew**, run `brew install ffmpeg`. If you use **MacPorts**, run `sudo port install ffmpeg`.

### 2.3 OBS Studio (only if you use the integration)

Clipshow does not require OBS Studio. The library, dashboard, Manage mode, and playout work on their own. If you turn on the OBS integration in Workspace settings, then OBS Studio must be set up so the app can reach it and so your scenes match how you broadcast.

Enable OBS’s WebSocket server (default port 4455; use a password in OBS if you configure one in Clipshow). The app uses that connection for program scene switches during playout and, when you use Capture, for recording control.

For the integration to make sense visually, OBS should expose program scenes you can map in Clipshow: one for your live look when you are *not* playing a clip (**Face**), and one where this application’s window is captured for **clip playout** (**Video**). For **OSG Mode**, configure an optional **OSG Overlay Source** name—a scene item (Window Capture of Clipshow, or a nested scene that contains it) that you place on every program scene you might enter OSG Mode from. Clipshow enables that source on the current program scene and leaves program unchanged. You choose the Video/Face scene names and overlay source on the **Scene Switch** tab in Workspace settings (§11.3); defaults for the program scenes are “Face Scene” and “Video Scene.”

> Screenshot (placeholder): OBS scene list with Face and Video scenes, and the WebSocket server settings panel.

### 2.4 Audio in the broadcast

If OBS is part of your chain and you want this app’s sound in the mix, you route audio through OBS or the OS (for example application audio capture on Windows, or a virtual cable / device path on Linux). Clipshow does not configure routing for you.

---

## 3. Workspaces

Everything in Clipshow is scoped to a **workspace**: one directory on disk that acts as your library “home.” That folder can contain your media in any subfolder layout you prefer. At the root of that same folder the app keeps a SQLite database file, `obs_clipshow.db`, which holds tags, clip definitions, workspace settings, ignored-path rules, and the rest of the metadata the UI depends on. Keeping media and database together makes the workspace a single bundle you can archive, copy to an external drive, or hand to another machine.

Inside the database, paths to video files are stored relative to the workspace root (with normalized separators). As long as you preserve the structure inside the folder when you move or sync it, opening that folder again resolves every track the same way.

### 3.1 Opening a workspace

Use Open workspace in the top bar (folder icon) to choose a directory. The app remembers the last selection in its own application data and reopens it on the next launch until you pick something else. If no workspace is selected yet, the dashboard tells you that no workspace is selected and expects you to choose one before the library UI is meaningful. Opening a folder creates `obs_clipshow.db` there if needed with default **ignored folders** (`recordings`, `export`) so Capture staging and Record/Bake output stay out of the library until you choose otherwise.

### 3.2 Ingestion

While a workspace is open, the app watches the tree for supported video files. Creating, editing, or removing a file under the workspace updates the corresponding **master** row and refreshes the file list; you do not import files through a separate dialog. (Files added while Clipshow is closed will be scanned on application start.) Large copies may take a couple of seconds after the last write before size/duration settle in the list—MODIFY events are debounced so in-progress transfers do not thrash the database. Paths configured as ignored folders on the **Workspace and Canvas** tab (§11.1) are skipped together with their subtrees, which keeps scratch or in-progress capture directories out of the library.

The built-in supported extensions are `.mp4`, `.mov`, `.mkv`, `.avi`, and `.webm`.

> Screenshot (placeholder): Header showing “Workspace: /path/to/…” and the empty or populated file list.

---

## 4. Dashboard layout

With a workspace open, the dashboard is a wide horizontal layout: the file list occupies roughly the left two-fifths of the window and the right column fills the rest.

Across the top, the header shows the folder control for Open workspace, a single line with the current workspace path (ellipsized when long), a **Reveal On Filesystem** control (outlined folder) that opens the workspace directory in your file manager when a workspace is selected, and a gear button that opens Workspace settings. When an OBS scene-switch profile is enabled in Workspace settings, an antenna icon appears between the path and the gear: green means the last periodic check reached OBS over WebSocket, red means it did not (the app keeps retrying). Hover the icon for a short status line, including the last successful contact time when known. If OBS integration is turned off or unset, that indicator is hidden altogether.

The right column starts with a segmented control for **Manage**, **Capture**, **Tag Sets**, and—when the workspace defines at least one **bake recipe**—**Bake Queue**. On Manage, the upper area is the video player; a horizontal drag handle separates it from the tag and metadata tools below. Dragging adjusts how much vertical space goes to the player versus the Tags card, within fixed limits. On Capture, the whole column is dedicated to the capture workflow—there is no player/tag split. Tag Sets and Bake Queue each fill the column with their own panels (§7 and §6.6).

> Screenshot (placeholder): Three-panel layout with a file selected, video playing in Manage, and the Tags card visible.

---

## 5. Files list, search, and filters

A **master** is an ingested video file in the workspace; a **clip** is a saved in/out range on one of those files (how you create clips is covered in §6). The Files pane lists both in one scrollable column—each row is either a master or a clip. On ingest, the app attaches internal tags (`Master` and `Clip`) automatically so every item’s type is obvious in the chip row; that is separate from any tags you add yourself. Selecting a row loads it in the right-side panes.

### 5.1 Search and filter controls

Across the top of the pane, two independent search fields sit next to an Untagged toggle:

The tag filter field (hint: “Search tag to filter”) suggests existing tags from your library as you type. Choosing a suggestion or pressing Enter with text adds that tag to an active filter set shown as removable chips below (“Filter: …”). Items must contain every active tag at once (logical AND). Filters persist until you delete their chips.

The text search field adapts its hint to the current scope—either “Search filename” or “Search workspace path.” Use the suffix icon to flip between modes. In filename mode, matching is case-insensitive against each row’s file base name and display name (see below); the folder portion of the path is not scanned. In full workspace path mode, the same query also matches the workspace-relative path string plus file name and display name—useful when you remember a folder but not the exact filename.

The Untagged chip keeps only items that have no user-added tags. The internal `Master` / `Clip` labels do not count toward “tagged” for this filter.

Below the search row, active filters appear as chips you can delete individually; when none apply, the UI shows placeholder copy (“No active tag filters”). A count on the right shows how many rows remain after everything is combined.

### 5.2 Anatomy of a list row

Each row corresponds to one media item (a master or a clip): thumbnail on the left, primary text and tags in the middle, and **Reveal On Filesystem** plus play on the right (tag-set rows show Enter OSG Mode instead). Click the row body to select it (highlighted background); the play button sends a healthy item to Playout. Right-click the row (outside a tag chip) for **Reveal On Filesystem**, which opens the master video in your file manager (same as the outlined-folder icon next to Play). Clips reveal their underlying master file.

The thumbnail shows a duration line when known (full length for a master, segment length for a clip with both marks set). The image comes from a sidecar file (`video.mp4.thumb.jpg`) when present, otherwise a placeholder until thumbnails finish. Masters can surface empty/unreadable-file states here and block play; clips reuse the source file for artwork and do not duplicate those warnings on this control.

The main title uses the display name when you have set one, otherwise the filename; clips add their time range in parentheses. A small pencil appears only when the display name differs from the filename. Under that, a muted line shows the workspace-relative path. Tags appear as chips (“No tags” when empty); pressing a tag chip toggles that tag in the active filter set.

> Screenshot (placeholder): File list with tags on chips and the search field visible.

---

## 6. Manage mode (library prep)

Use **Manage** on the right column (versus **Capture**) when you are preparing existing library media. Manage stacks two cards—the upper **Manage** card holds the video player and editing controls; the lower **Tags** card holds naming, tagging, and bulk-tag workflows. The draggable split between them is described in §4. Whatever you select in the file list drives both cards.

### 6.1 Playout from Manage

The Manage card ends with a prominent **Playout** control (the file list offers the same intent per row). Both route into broadcast playback (§9). **Playout starts from the current playhead position** in the Manage player when you launch it here, so you can line up on the frame you want before going to air. The button is unavailable when no playable item is selected, when the workspace is invalid, or when the selected master has a blocking media issue.

When the workspace defines **on-screen graphics**, the preview can draw those overlays on the video; use the **6–0** toggles beside the player to show or hide each preset (see §10). **Bake**, **Export OSG Graphics**, and **Record** sit on the same action bar when applicable (§6.6, §6.7, and §9.7).

### 6.2 With a master selected

Scrub with the timeline and transport controls; clicking the video toggles play/pause. **Mark In** and **Mark Out** stamp the current playhead into working marks (shown on the buttons). Setting Mark In after Mark Out clears Mark Out if the pair would be invalid. **Save clip** persists a new **clip** row from those marks on the selected master; if both marks exist, Mark Out must be later than Mark In. Mark Out may stay unset for an open-ended clip. Keyboard shortcuts **I**, **O**, and **S** mirror Mark In, Mark Out, and Save clip when focus is on the player—click the video surface if shortcuts stop responding.

**Trash file** confirms, then moves the underlying video to the system trash when possible (otherwise a fallback folder under the workspace), removes the master from the database, and drops clips that depended on that file. If the video is already missing from disk, a second confirm offers to remove the orphaned master (and its clips) from the library without touching the filesystem.

### 6.3 With a clip selected

The player stays within the clip’s range. Mark In / Out and Save clip give way to **nudge** controls that move the clip’s start or end by ±0.5 s or ±2.5 s (buttons only—no hotkeys). **Delete clip** confirms, then removes the clip row only; the master file on disk is untouched.

### 6.4 Seeking and keyboard shortcuts

Manage shares the same seek increments as Playout (§9) for review. Press **H** while the player has focus to toggle an overlay that summarizes shortcuts.


| Action              | Shortcut      |
| ------------------- | ------------- |
| Seek ±100 ms        | Alt + ← / →   |
| Seek ±1 s           | ← / →         |
| Seek ±5 s           | Ctrl + ← / →  |
| Seek ±15 s          | Shift + ← / → |
| Jump to start / end | Home / End    |
| Volume ±10%         | ↑ / ↓         |
| Mute / unmute       | M             |
| Toggle help overlay | H             |


Space toggles play/pause; **H** toggles the help overlay.

### 6.5 Tags panel

The Tags card always reflects the current list selection. At the top it shows the item’s display name (and filename when they differ) with **Edit** to change the display override and **Clear** to drop it back to the filename.

For a **clip**, **Go to Source Master** jumps selection to the underlying master file. For a **master** that already has clips, **Show Clips** / **Clear Clip Filter** toggles the file-list filter that limits the list to clips of that master (see §5).

Every tag on the item appears as a chip. Internal type tags cannot be deleted but behave like other chips for filtering the file list. Use **Add Tag** (with autocomplete from your library) and **Add** to attach user tags to the selection. The small **capture** control merges the selected item’s user tags into the Capture pane’s tag basket so new recordings inherit them.

Below the divider, **Saved Tags** is a reusable palette stored in the workspace: chips can be removed individually. **Add Saved Tag** maintains that list. Three bulk actions use the saved set to push tags to other parts of the application, indicated by the arrows: **filtered** or **all** applies those tags to every visible list row or the entire library (depending on whether file-list filters are active—confirmed by dialog); **current** applies them only to the selected item; **capture** merges the saved set into the Capture tag basket. Both **capture** buttons feed Capture mode (§8).

> Screenshot (placeholder): Manage mode with the player, clip marks or nudge controls, and the Tags card visible.

### 6.6 Bake (offline export)

**Bake** renders the selected clip or master to an MP4 with on-screen graphics composited in according to a **bake recipe**—an offline ffmpeg pipeline, not a live playout session. You need at least one bake recipe on the **On-Screen Graphics** tab in Workspace settings (§11.2) before the **Bake** button appears on the preview action bar.

Choosing **Bake** opens a recipe picker. For each recipe you can **Queue** the job for the **Bake Queue** tab or run **Now** and wait while rendering finishes (you can cancel once the job is actually running). Finished files land in the workspace **playout output** folder (default `export`, same as Record playout—§9.7) as `{displayName}_baked.mp4`, with a numeric suffix if that name already exists. A bottom banner offers **Reveal** when a bake completes.

Recipes define timed **cues**—which OSG preset is visible from which anchor in clip time (clip start/end, offset from start, or offset from end). At queue time Clipshow checks that the selected item satisfies each cue preset’s required semantic tags; missing tags block the job with an error.

When the workspace has bake recipes, the **Bake Queue** tab shows the runner (**Start** / **Pause**), the currently running task with a progress bar (percent of overlay frames streamed), and pending and finished tasks. Pausing stops dequeuing new work; a **Now** bake still runs immediately when you choose it from Manage. Completed rows can reveal the output file in your file manager.

### 6.7 Export OSG Graphics (ZIP)

**Export OSG Graphics** exports hold-state PNGs plus a **manifest** for use in an external NLE—not a baked video. It appears on the preview action bar when the workspace has at least one bake recipe (same gate as **Bake**). Select a clip or master with valid semantic tags for the recipe, choose **Export OSG Graphics**, pick a recipe, then choose where to save the ZIP.

Each distinct OSG slot referenced by the recipe becomes one **playout-canvas-sized** transparent PNG (`osg6.png` … `osg0.png`, matching hotkeys **6–0**). The ZIP also contains **`manifest.json`** with:

- **Canvas** size and **source clip** identity (`fileName`, `workspaceRelativePath` under the workspace root), plus range (`inMs`, `outMs`, `durationMs`) used to resolve timing
- Per slot: **`frameNorm`** and **`frameCanvasPx`** (placement), **`enter`** / **`exit`** motion (`slideDistanceNorm`, **`slideDistanceCanvasPx`**, **`durationMs`**, **`fadeDurationMs`**, easing), **`cues`** (raw bake anchors plus resolved `inResolvedMs` / `outResolvedMs` and enter/exit animation bounds), and resolved **text**

Slide distance in pixels is along the motion axis, computed from the preset frame size on the canvas (same rules as playout and bake). **`durationMs`** is the full transition; **`fadeDurationMs`** may be shorter when the motion includes a slide (fade and slide start together). Timing in the manifest matches the bake recipe resolved against the selected clip; you place and keyframe in the NLE.

This is separate from **Export OSG presets (ZIP)** in the on-screen graphics editor, which shares preset templates and JSON between workspaces.

---

## 7. Tag Sets and OSG Mode

The **Tag Sets** tab manages **bare tag sets**—named bundles of tags and annotations with no video file. Use them to pre-build data-driven on-screen graphics (OSGs) that read semantic tag values from the active tag set.

Create tag sets, attach tags (with optional semantic types), and assign up to five **quick slots** (keys **1–5** while in OSG Mode). Enable **OSG Mode** on the **On-Screen Graphics** tab in Workspace settings (§11.2). **Enter OSG Mode** switches the app to a transparent full-window graphics surface. When OBS integration is enabled and an **OSG Overlay Source** is set, Clipshow looks up that source on the **current** OBS program scene, enables it after the first frame paints, and disables the same item on **Escape**—program scene is not switched. If the source is missing from the current scene, enter fails with an error. Leave the overlay source empty to skip OBS overlay automation (webhooks may still fire). Hotkeys **6–0** toggle OSG presets; **1–5** switch among quick-slot tag sets.

Build each live look in OBS with your camera (or other) background and a same-named Clipshow Window Capture (or nested overlay scene) so OSG Mode can sit over stage, booth, or any other program scene.

---

## 8. Capture mode

Switch the right column to **Capture** when you want OBS to record new footage straight into the workspace library and automatically apply Clipshow tags. Clipshow does not capture A/V itself; it controls **OBS Studio** over the same WebSocket connection as scene switching, then moves the finished file where ingestion can see it. An example workflow would be clipping and tagging a live HDMI feed as it happens for later playback.

You need a **workspace** open and an **enabled** OBS profile on the **Scene Switch** tab (§11.3). Until then, the Capture pane explains that OBS must be enabled; **Start Recording** stays inactive.

### 8.1 Why a `recordings` folder (or similar) appears

While **Start Recording** is active, Clipshow tells OBS to use a **recording** directory **inside your workspace**—the path configured under **OBS Paths** (§11.3), often a folder such as `recordings/`. OBS’s global “recording path” is temporarily pointed there so the growing file lands under your project. That folder is normally **ignored** by the library scanner so half-written takes do not show up as masters. When you **Stop And Save**, Clipshow stops the encoder, waits for the file on disk to settle, then **copies** the result into your **output** folder (§11.3—commonly the workspace root or another non-ignored location) and **deletes** the staging copy so you do not keep duplicates. Ingestion only indexes the output copy; partial files still in the recording tree while a take is in progress stay quarantined there until stop completes. Afterward Clipshow **restores OBS’s recording directory** to whatever it was before this session and closes the capture WebSocket client, so your everyday OBS layout is not permanently changed.

Capture also supports keyboard triggers: press **R** to start recording and **S** to stop and save.

If you set an optional **capture** program scene name in settings, Clipshow switches OBS to that scene before starting the encoder so your sources and layout match how you want to record.

### 8.2 Tags and timing

Add tags with the field and **Add**; tags can be edited while a recording is in progress. The tag list in the panel at the instant you press **Stop And Save** is what gets applied to the new **master** after the file copies and ingests. That snapshot is taken when you stop—you can immediately edit chips for the **next** take while copy and ingest still run in the background.

> Screenshot (placeholder): Capture mode with Start/Stop and status message.

---

## 9. Playout (broadcast mode)

**Playout** is full-window playback for sending a master or clip to air. In a native OBS workflow it lets Clipshow act as a simple **director**: on demand it switches your **program** output between a scene that carries your main stream (camera, game, graphics—whatever you configure as your “live” look) and a scene where **Clipshow’s window** is the primary source for replays and analysis. Frame-accurate seeking and telestration (below) replace a loose combination of external player, drawing tool, and manual OBS scene changes, while optional integrations still advance OBS and other tools on enter and exit so the rest of your stack stays aligned.

### 9.1 Entering playout

From the dashboard, use **Playout** in Manage or the play control on a file row. The dashboard UI is replaced by the player until you leave.

Use **Record** on the preview action bar (next to **Playout**) when you want OBS to write a finished file while you run the same playout session—see §9.7.

### 9.2 OBS and the broadcast chain

When integrations are enabled, entering Playout switches OBS’s **program** scene to the one you configured for showing this application **after** the playout player has loaded and painted its first frame (so window capture is less likely to show a black or empty frame). Leaving Playout (`Escape`) switches back to your configured “live” scene and restores the dashboard (scroll position is restored when possible). The same transitions can also invoke **HTTP webhooks** you configured in Workspace settings so companion automation stays in step. None of this runs if OBS or webhooks are disabled, but you can still use Playout as a local fullscreen reviewer.

### 9.3 Window and layout

On enter, Playout resizes the OS window to **Playout canvas size** from the **Workspace and Canvas** tab (§11.1): logical width and height in pixels (default **1920×1080**). Any aspect ratio is valid—the window is set to that exact size in windowed mode, and the OS aspect-ratio lock matches the canvas. The title bar is hidden for a clean OBS Window Capture; windowed playout is the typical case.

Decoded video is **letterboxed**, not stretched: it keeps the source aspect ratio inside the canvas (`BoxFit.contain`), with empty bars when the source and canvas aspects differ. **On-screen graphics** and the **telestrator** use the full playout canvas (including gutters), matching the editor, bake output, and OBS window capture. Set **Playout canvas size** to match how you window-capture Clipshow in OBS (see also §10).

### 9.4 End of video

For clips and master files, playback **pauses on the last frame** so you can keep commenting or drawing before you exit, or seek to other points in the file to replay certain parts of it.

### 9.5 Keyboard — playback and navigation


| Action                             | Shortcut      |
| ---------------------------------- | ------------- |
| Play / pause                       | Space         |
| Seek ±100 ms                       | Alt + ← / →   |
| Seek ±1 s                          | ← / →         |
| Seek ±5 s                          | Ctrl + ← / →  |
| Seek ±15 s                         | Shift + ← / → |
| Jump to start / end                | Home / End    |
| Volume ±10%                        | ↑ / ↓         |
| Mute / unmute                      | M             |
| Toggle help overlay                | H             |
| Exit playout (return to dashboard) | Escape        |


> Screenshot (placeholder): Playout screen with optional help/hints visible.

### 9.6 Telestrator (drawing on air)

While Playout is active you can draw on top of the picture for commentary—strokes live on a transparent overlay and are not burned into a file. (If you want to burn telestrator output into a file, record the stream in OBS or use Clipshow's Record mode.) Defaults (colors, brush, whether drawing starts on or off) come from **Telestrator settings** on the **On-Screen Graphics** tab (§11.2).


| Action                 | Shortcut  |
| ---------------------- | --------- |
| Toggle drawing mode    | T         |
| Clear strokes          | C         |
| Undo                   | Z         |
| Pen colors             | 1 / 2 / 3 |
| Smaller / larger brush | [ / ]     |


Leaving Playout clears the canvas for the next session.

> Screenshot (placeholder): Playout with arrows or circles drawn over the video.

### 9.7 Record playout export

**Record** starts normal playout (OSGs, telestrator) and tells OBS to **record program output** after the same first-frame gate, then the Video scene switch, while you run the clip. When you press **Escape**, Clipshow stops OBS, copies the file into your configured **playout output** folder (and removes the staging copy), restores OBS’s recording directory, then switches back to your live scene. Recording runs in **real time** (a 30-second clip takes about 30 seconds plus stop/copy time).

**Requirements:** An **enabled** OBS profile on the **Scene Switch** tab (§11.3). Capture mode cannot be recording at the same time; OBS must not already be recording on its own.

**Paths:** Under **OBS Paths** (§11.3), **Playout Record** is where OBS writes the growing file (default `recordings/export`). **Playout Output** is where the finished copy lands (default `export`). New workspaces ignore `export` by default so finished files are not ingested; you can remove that ignore under **Ignored folders** if you want baked/recorded videos in the library later. Capture paths are separate—Capture still uses **Capture Recording** / **Capture Output**. Bake exports use the same **Playout Output** folder (§6.6).

**Audio and picture:** Whatever your **Video** scene sends to program—including window capture of Clipshow and your mic if routed in OBS—is what the file contains. Route commentary in OBS, not only in Clipshow.

**After export:** A SnackBar offers **Reveal** to show the file in your file manager.

> Screenshot (placeholder): Preview bar with Record and Playout buttons.

---

## 10. On-screen graphics (OSG)

**On-screen graphics** are workspace-defined overlays: a **template** (still image or solid color) plus optional **text slots**, composited on the playout canvas in **Manage preview** and **Playout**. Layout is stored internally as normalized coordinates (0…1) on the logical **broadcast canvas**; in the editor, **frame** position and size are shown as playout canvas pixels for your configured canvas size, and **text slots** use percentages within the template. Set that canvas on the **Workspace and Canvas** tab in Workspace settings (§11.1); the Manage preview frames the player at that aspect ratio so WYSIWYG matches playout and bake.

### 10.1 Opening the editor

In **Workspace settings** (gear in the dashboard header), open the **On-Screen Graphics** tab and choose **Open on-screen graphics editor…**. The editor runs full-screen until you tap **Done**.

There you maintain:

- **Semantic tag types** — Categories used when tagging media (with optional icons). OSG text slots can show the value of a semantic tag.
- **Five presets**, one per tab, mapped to keys **6** through **0** in preview, playout, and OSG Mode.

Use **Save all OSG settings** to persist changes to the workspace database.

### 10.2 Designing a preset

For each preset you can:

- **Enable** or disable it entirely.
- Choose a **template** — import a PNG/JPEG (or similar) file into the workspace, or use a **solid** fill (color, corner radius, and notional width/height for aspect).
- **Place the frame** — In the **screen** preview (right), drag the overlay on the gray canvas and resize with the corner handle, or type **X**, **Y**, **W**, and **H** in playout canvas pixels. The frame’s aspect follows the template (image pixels or solid aspect).
- **Add text slots** — In the **template-only** preview (left), drag boxes and resize, or edit position and size as percentages of the template; slot **Source** can be fixed text, **Tag value** (semantic type), or **Annotation** (from the selected item’s annotation field in the Tags card). Adjust font size (% of template height), alignment, and color.
- Set **layer opacity**, optional **rounded corners** on the template, and **required semantic tags** — if the current media row does not satisfy those tag types, the preset stays hidden even when toggled on.
- Configure **Show / Hide Motion**: enter and exit as **Fade Only** or **Fade + slide** from/to an edge. **Enter/Exit Duration** is the full transition (slide window). When a slide is selected, **Enter/Exit Fade Duration** may be shorter so the fade finishes while motion continues (both start together; remaining slide is fully opaque on enter, fully invisible on exit). Use **Preview Motion** to play exit → pause → enter on the editor canvas.

### 10.3 Manage preview (dashboard)

With a playable item selected and a workspace open, the Preview card in the Manage tab frames the player at **Playout canvas size** aspect ratio (bordered canvas on a black surround) and shows **OSG** toggle buttons **6** through **0** below the preview. Each button toggles whether that preset is drawn on the dashboard preview for the current selection. Transport controls sit below the framed canvas, outside the broadcast area.

### 10.4 Playout

In **Playout** (§9), the same keys **6** through **0** toggle presets **over the broadcast picture**.

Starting Playout from the Preview card's **Playout** button carries over the current preview visibility for all five presets so you do not have to re-toggle before going to air. You can still change toggles during Playout.

---

## 11. Workspace settings

Open **Workspace settings** from the gear control in the dashboard header. Everything here is stored in the current workspace’s database and applies only while that workspace is open.

The dialog has three tabs. Each section has its own **Save** (or **Apply**) control—change a block and save it before you rely on the value elsewhere in the app.

### 11.1 Workspace and Canvas

**Playout canvas size** sets the logical broadcast resolution (width and height in pixels; default 1920×1080). It drives playout and OSG Mode window sizing, OSG layout, and bake output framing—there is no fixed aspect ratio.

**Playback** — **Default clip volume** (0–100%) applies when the workspace loads. During preview and playout, **↑** / **↓** nudge volume by 10% and **M** toggles mute; those session adjustments are not saved.

**Decoder config** — Choose which decode **profiles** are active and in what **priority order**, plus separate dropdowns for **MDK** and **fvp** log verbosity when you need diagnostics. **Apply Decoder Settings** commits the list; restart the app after changing decoder configuration.

**Ingestion and preview** — **Pause background ingest during Manage playback** reduces concurrent disk access while the dashboard preview player is running (useful on slow USB disks). Full-window **Playout** always pauses background ingest regardless of this toggle. **Ffprobe batch size** and **thumbnail concurrency** tune how aggressively the workspace scanner probes durations and generates sidecar thumbnails.

**Ignored folders** — Workspace-relative paths that ingestion skips entirely (including nested files). New workspaces start with `recordings` and `export`. You can add or remove paths manually; removing `export` lets Record/Bake output ingest for later playback, and Clipshow will not put that ignore back on open.

**Export workspace** — **Export JSON** writes workspace metadata and media rows for backup or tooling (full shape in §12). Video files are not copied.

### 11.2 On-Screen Graphics

**Telestrator settings** — Defaults for Playout drawing: three stroke colors, brush size, and whether telestration starts enabled when you enter Playout. **Apply Telestrator Settings** saves; see §9.6 for in-session shortcuts.

**On-screen graphics** — **OSG Mode enabled** toggles whether **Enter OSG Mode** is available on the Tag Sets tab. **Open on-screen graphics editor…** opens the full-screen preset editor (§10).

**Bake recipes** — Named timing sets for **Bake** (§6.6). Add, edit, or delete recipes; each lists **cues** (preset slot plus start and end anchors in clip time). The dashboard **Bake Queue** tab appears once at least one recipe exists.

### 11.3 Scene Switch

Scene switching is modeled as **profiles** shown at the top of the tab: one **OBS** connection plus any number of **HTTP webhooks**. Each profile can be enabled or disabled without deleting it.

**OBS** — WebSocket address, port, password, and **program** scene names for **video** (clip playout), **face** (return after playout), optionally **OSG Overlay Source** (scene-item name enabled on the current program scene during OSG Mode—§7), and optionally **capture** (switched before OBS recording starts in Capture mode—§8). An empty overlay source disables OSG overlay automation. **Save OBS** applies that block.

**OBS Paths** — **Capture Recording** and **Capture Output** for Capture mode (§8). **Playout Record** is staging for **Record** playout (§9.7); default `recordings/export`. **Playout Output** is where finished Record and Bake exports land (default `export`). Playout output must not sit inside playout staging. **Save Paths** persists all path fields; capture recording and playout staging are kept in **ignored folders** when not already covered. Changing **Playout Output** to a new folder adds that folder to ignored once; clearing an ignore for the current output folder is preserved across later saves of the same path.

**Webhooks** — HTTP endpoints that fire on playout and OSG Mode transitions (method, URL, and body/query shape). The payload value is a fixed token—**video** when entering Playout, **face** when leaving Playout, **osg_on** when entering OSG Mode, and **osg_off** when leaving OSG Mode—under your chosen query parameter or JSON/form key (not your OBS scene names).

Invalid capture/output pairings are blocked or explained inline when you save paths.

> Screenshot (placeholder): Workspace settings dialog with Scene Switch tab visible.

---

## 12. Export

Under **Export workspace** on the **Workspace and Canvas** tab (§11.1), **Export JSON** opens a save dialog (default name `workspace_export.json`). The app writes a single JSON document with top-level keys `**workspacePath`** (absolute root you have open), `**settings`**, and `**mediaItems**`—one media object per master or clip currently in the library.

The **settings** object mirrors what lives in the workspace database: telestrator defaults, decoder profile names and verbosity levels, default clip volume, OBS WebSocket configuration (including scene names), webhook definitions, capture and playout record paths, bake recipes, and ignored-folder entries. **Media items** include workspace-relative paths, display overrides, sorted tag lists, and for clips the in/out millisecond range.

Video files are **not** copied or embedded; the export is metadata only. Treat the file as **sensitive** if your OBS block includes a password—it is serialized in plain text. Use the export for backups, migration notes, or external tooling that understands this shape.

---

## 13. Tips and troubleshooting

Most issues fall into a few buckets: integration connectivity, tooling on disk, capture path layout, playback tuning, and how workspaces move between machines.

### 13.1 OBS indicator red or scene switches failing

The antenna icon in the dashboard header (§4) reflects whether Clipshow’s last periodic WebSocket check reached OBS. If it stays red, confirm OBS is running, WebSocket is enabled in OBS (typical port **4455**), and host, port, and password on the **Scene Switch** tab (§11.3) match. Scene names must be **program** scenes exactly as named in OBS. After correcting settings, wait for the next check or restart the app if needed.

### 13.2 Thumbnails or durations missing

Sidecar thumbnails (`*.thumb.jpg` next to each video) are produced with **ffprobe** (duration) and **ffmpeg** (frame grab). Both commands must be available on your **PATH** like any other CLI tool—install FFmpeg per §2.2. If a file is corrupt or unreadable, the list may show a problem state instead of a thumbnail.

### 13.3 Capture stopped but no new library item

Follow the Capture flow end-to-end (§8): recording must finish cleanly with **Stop And Save**, the **output** folder must be somewhere ingestion scans (not inside an incorrectly ignored tree), and output cannot be nested inside the **recording** staging folder. Very slow disks may need a moment after stop before the copy appears.

### 13.4 Playback stutters, errors, or wrong decoder behavior

Try adjusting **Decoder config** on the **Workspace and Canvas** tab (§11.1)—profile order and availability depend on your operating system, GPU, and drivers. For diagnostics, raise **MDK** or **fvp** log verbosity temporarily; remember to lower it afterward.

### 13.5 Manage shortcuts ignored

Keyboard shortcuts in the Manage player (§6) apply when that region has focus—click the video surface if keys stop responding after interacting elsewhere.

### 13.6 Moving or cloning a workspace

Keep `**obs_clipshow.db`** at the workspace root together with your media tree. Paths inside the database are relative to that root; moving the whole folder preserves them as long as internal layout stays the same.

### 13.7 Webhooks or companion automation out of sync

Confirm each webhook entry is enabled, URLs are reachable, and method and body or query settings match what your receiver expects (§11.3). Payload values are the literals **video** (enter Playout), **face** (leave Playout), **osg_on** (enter OSG Mode), and **osg_off** (leave OSG Mode)—not your OBS scene names. Playout webhooks align with OBS program scene switches when OBS integration is enabled; OSG Mode webhooks track overlay/lifecycle, not a Face scene cut. Each transition attempts every enabled webhook once, and failures are logged rather than retried automatically.

### 13.8 Bake failed or blocked

Confirm the item has the semantic tags required by the recipe’s presets, **ffmpeg** is on your **PATH** (§2.2), and **Playout canvas size** is valid. Check the Bake Queue tab for error messages on failed tasks.

### 13.9 Exported JSON

See §12 for contents. Do not share exports casually if they include secrets or internal paths you consider private.