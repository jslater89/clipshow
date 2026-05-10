# User Manual

**Clipshow** is a desktop app and a local tool for managing, tagging, and playing clip libraries for streaming broadcasts. Beyond the library itself, you can optionally connect it to OBS Studio over WebSocket (scene switches and capture recording) and to HTTP webhooks for other tools, triggering actions on playout. During playout you can use an on-screen **telestrator** for commentary-style markup.

---

## 1. What this app is for

The dashboard is where you work inside a workspace folder: supported videos are discovered and indexed, you search and tag items, preview them, and define **non-destructive clips** (in and out times on the same master file rather than exporting a separate cut). That mode is aimed at organizing and preparing material rather than sending picture to air.

Playout is dedicated playback of a master or a saved clip in a 16:9–locked window sized for the source (fullscreen is optional if you prefer it). Driving the stream stack is separate: when you enable them in workspace settings, entering and leaving playout can optionally switch OBS program scenes directly via its WebSocket API, and/or call HTTP webhooks so other software can react to the same transitions.

While playout is active, the telestrator lets you draw on top of the picture for analysis or emphasis; the drawing layer sits above the player and does not produce a rendered output file by itself.

Optionally, from the dashboard Capture flow you can start and stop OBS recording into a staging folder, then copy the finished file into an output location so the library ingests it once without picking up partial recordings.

---

## 2. Requirements

### 2.1 Machine and OS

Clipshow targets desktop Windows and Linux as built for this project. Smooth playback depends on your GPU and drivers; in practice the player stack favors hardware-backed decoding where it is available. Adjust decoder-related options under Workspace settings if you need to tune behavior on your machine.

> **TODO (Windows):** Revisit this section after Windows builds are validated—confirm playback, paths, capture, and any OS-specific notes.

### 2.2 FFmpeg

Clipshow shells out to `**ffmpeg`** and `**ffprobe`** for thumbnails and duration probing; both must be discoverable on your `**PATH**` (see §11 if they seem missing). Install FFmpeg using your platform’s usual package manager—the commands below install the suite that includes both binaries.

**Linux:** On Debian or Ubuntu, run `sudo apt update` then `sudo apt install ffmpeg`. On Fedora, use `sudo dnf install ffmpeg`. On Arch Linux, use `sudo pacman -S ffmpeg`. Other distributions ship FFmpeg under the same name in their repos.

**Windows:** With **winget**, run `winget install -e --id Gyan.FFmpeg` from PowerShell or Command Prompt (elevated if your policy requires it). Open a **new** terminal afterward so `PATH` picks up the install, then confirm with `ffmpeg -version` and `ffprobe -version`.

**macOS:** With **Homebrew**, run `brew install ffmpeg`. If you use **MacPorts**, run `sudo port install ffmpeg`.

### 2.3 OBS Studio (only if you use the integration)

Clipshow does not require OBS Studio. The library, dashboard, Manage mode, and playout work on their own. If you turn on the OBS integration in Workspace settings, then OBS Studio must be set up so the app can reach it and so your scenes match how you broadcast.

Enable OBS’s WebSocket server (default port 4455; use a password in OBS if you configure one in Clipshow). The app uses that connection for program scene switches during playout and, when you use Capture, for recording control.

For the integration to make sense visually, OBS should expose at least two program scenes you can map in Clipshow: one that shows what you want live when you are *not* playing a clip from this app (for example camera and microphone), and one that shows this application—typically via a Window Capture (or similar) source pointed at Clipshow’s window, sized to match your output resolution (for example 1920×1080). You choose the actual scene names in Workspace settings (see §9); they do not have to be called “Face” and “Video.”

> Screenshot (placeholder): OBS scene list with Face and Video scenes, and the WebSocket server settings panel.

### 2.4 Audio in the broadcast

If OBS is part of your chain and you want this app’s sound in the mix, you route audio through OBS or the OS (for example application audio capture on Windows, or a virtual cable / device path on Linux). Clipshow does not configure routing for you.

---

## 3. Workspaces

Everything in Clipshow is scoped to a **workspace**: one directory on disk that acts as your library “home.” That folder can contain your media in any subfolder layout you prefer. At the root of that same folder the app keeps a SQLite database file, `obs_clipshow.db`, which holds tags, clip definitions, workspace settings, ignored-path rules, and the rest of the metadata the UI depends on. Keeping media and database together makes the workspace a single bundle you can archive, copy to an external drive, or hand to another machine.

Inside the database, paths to video files are stored relative to the workspace root (with normalized separators). As long as you preserve the structure inside the folder when you move or sync it, opening that folder again resolves every track the same way.

### 3.1 Opening a workspace

Use Open workspace in the top bar (folder icon) to choose a directory. The app remembers the last selection in its own application data and reopens it on the next launch until you pick something else. If no workspace is selected yet, the dashboard tells you that no workspace is selected and expects you to choose one before the library UI is meaningful.

### 3.2 Ingestion

While a workspace is open, the app watches the tree for supported video files. Creating, editing, or removing a file under the workspace updates the corresponding **master** row and refreshes the file list; you do not import files through a separate dialog. Paths configured as ignored folders under Workspace settings (see §9) are skipped together with their subtrees, which keeps scratch or in-progress capture directories out of the library.

The built-in supported extensions are `.mp4`, `.mov`, `.mkv`, `.avi`, and `.webm`.

> Screenshot (placeholder): Header showing “Workspace: /path/to/…” and the empty or populated file list.

---

## 4. Dashboard layout

With a workspace open, the dashboard is a wide horizontal layout: the file list occupies roughly the left two-fifths of the window and the Manage or Capture column fills the rest.

Across the top, the header shows the folder control for Open workspace, a single line with the current workspace path (ellipsized when long), and a gear button that opens Workspace settings. When an OBS scene-switch profile is enabled in Workspace settings, an antenna icon appears between the path and the gear: green means the last periodic check reached OBS over WebSocket, red means it did not (the app keeps retrying). Hover the icon for a short status line, including the last successful contact time when known. If OBS integration is turned off or unset, that indicator is hidden altogether.

The right column starts with a Manage / Capture segmented control. On Manage, the upper area is the video player; a horizontal drag handle separates it from the tag and metadata tools below. Dragging adjusts how much vertical space goes to the player versus the Tags card, within fixed limits. On Capture, the whole column is dedicated to the capture workflow—there is no player/tag split.

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

Each row corresponds to one media item (a master or a clip): thumbnail on the left, primary text and tags in the middle, and play on the right. Click the row body to select it (highlighted background); the play button sends a healthy item to Playout.

The thumbnail shows a duration line when known (full length for a master, segment length for a clip with both marks set). The image comes from a sidecar file (`video.mp4.thumb.jpg`) when present, otherwise a placeholder until thumbnails finish. Masters can surface empty/unreadable-file states here and block play; clips reuse the source file for artwork and do not duplicate those warnings on this control.

The main title uses the display name when you have set one, otherwise the filename; clips add their time range in parentheses. A small pencil appears only when the display name differs from the filename. Under that, a muted line shows the workspace-relative path. Tags appear as chips (“No tags” when empty); pressing a tag chip toggles that tag in the active filter set.

> Screenshot (placeholder): File list with tags on chips and the search field visible.

---

## 6. Manage mode (library prep)

Use **Manage** on the right column (versus **Capture**) when you are preparing existing library media. Manage stacks two cards—the upper **Manage** card holds the video player and editing controls; the lower **Tags** card holds naming, tagging, and bulk-tag workflows. The draggable split between them is described in §4. Whatever you select in the file list drives both cards.

### 6.1 Playout from Manage

The Manage card ends with a prominent **Playout** control (the file list offers the same intent per row). Both route into broadcast playback (§8). **Playout starts from the current playhead position** in the Manage player when you launch it here, so you can line up on the frame you want before going to air. The button is unavailable when no playable item is selected, when the workspace is invalid, or when the selected master has a blocking media issue.

### 6.2 With a master selected

Scrub with the timeline and transport controls; clicking the video toggles play/pause. **Mark In** and **Mark Out** stamp the current playhead into working marks (shown on the buttons). Setting Mark In after Mark Out clears Mark Out if the pair would be invalid. **Save clip** persists a new **clip** row from those marks on the selected master; if both marks exist, Mark Out must be later than Mark In. Mark Out may stay unset for an open-ended clip. Keyboard shortcuts **I**, **O**, and **S** mirror Mark In, Mark Out, and Save clip when focus is on the player—click the video surface if shortcuts stop responding.

**Trash file** confirms, then moves the underlying video to the system trash when possible (otherwise a fallback folder under the workspace), removes the master from the database, and drops clips that depended on that file.

### 6.3 With a clip selected

The player stays within the clip’s range. Mark In / Out and Save clip give way to **nudge** controls that move the clip’s start or end by ±0.5 s or ±2.5 s (buttons only—no hotkeys). **Delete clip** confirms, then removes the clip row only; the master file on disk is untouched.

### 6.4 Seeking and keyboard shortcuts

Manage shares the same seek increments as Playout (§8) for review. Press **H** while the player has focus to toggle an overlay that summarizes shortcuts.


| Action              | Shortcut      |
| ------------------- | ------------- |
| Seek ±100 ms        | Alt + ← / →   |
| Seek ±1 s           | ← / →         |
| Seek ±5 s           | Ctrl + ← / →  |
| Seek ±15 s          | Shift + ← / → |
| Jump to start / end | Home / End    |
| Toggle help overlay | H             |


Space toggles play/pause; **H** toggles the help overlay.

### 6.5 Tags panel

The Tags card always reflects the current list selection. At the top it shows the item’s display name (and filename when they differ) with **Edit** to change the display override and **Clear** to drop it back to the filename.

For a **clip**, **Go to Source Master** jumps selection to the underlying master file. For a **master** that already has clips, **Show Clips** / **Clear Clip Filter** toggles the file-list filter that limits the list to clips of that master (see §5).

Every tag on the item appears as a chip. Internal type tags cannot be deleted but behave like other chips for filtering the file list. Use **Add Tag** (with autocomplete from your library) and **Add** to attach user tags to the selection. The small **capture** control merges the selected item’s user tags into the Capture pane’s tag basket so new recordings inherit them.

Below the divider, **Saved Tags** is a reusable palette stored in the workspace: chips can be removed individually. **Add Saved Tag** maintains that list. Three bulk actions use the saved set to push tags to other parts of the application, indicated by the arrows: **filtered** or **all** applies those tags to every visible list row or the entire library (depending on whether file-list filters are active—confirmed by dialog); **current** applies them only to the selected item; **capture** merges the saved set into the Capture tag basket. Both **capture** buttons feed Capture mode (§7).

> Screenshot (placeholder): Manage mode with the player, clip marks or nudge controls, and the Tags card visible.

---

## 7. Capture mode (OBS recording)

Switch the right column to **Capture** when you want OBS to record new footage straight into the workspace library and automatically apply Clipshow tags. Clipshow does not capture A/V itself; it controls **OBS Studio** over the same WebSocket connection as scene switching, then moves the finished file where ingestion can see it.

You need a **workspace** open and an **enabled** OBS profile in Workspace settings (§9). Until then, the Capture pane explains that OBS must be enabled; **Start Recording** stays inactive.

### 7.1 Why a `recordings` folder (or similar) appears

While **Start Recording** is active, Clipshow tells OBS to use a **recording** directory **inside your workspace**—the path configured under Capture paths (§9), often a folder such as `recordings/`. OBS’s global “recording path” is temporarily pointed there so the growing file lands under your project. That folder is normally **ignored** by the library scanner so half-written takes do not show up as masters. When you **Stop And Save**, Clipshow stops the encoder, waits for the file on disk to settle, then **copies** the result into your **output** folder (§9—commonly the workspace root or another non-ignored location). Ingestion only indexes the copy; partial files stay quarantined in the recording tree. Afterward Clipshow **restores OBS’s recording directory** to whatever it was before this session and closes the capture WebSocket client, so your everyday OBS layout is not permanently changed.

If you set an optional **capture** program scene name in settings, Clipshow switches OBS to that scene before starting the encoder so your sources and layout match how you want to record.

### 7.2 Tags and timing

Add tags with the field and **Add**; tags can be edited while a recording is in progress. The tag list in the panel at the instant you press **Stop And Save** is what gets applied to the new **master** after the file copies and ingests. That snapshot is taken when you stop—you can immediately edit chips for the **next** take while copy and ingest still run in the background.

> Screenshot (placeholder): Capture mode with Start/Stop and status message.

---

## 8. Playout (broadcast mode)

**Playout** is full-window playback for sending a master or clip to air. In a native OBS workflow it lets Clipshow act as a simple **director**: on demand it switches your **program** output between a scene that carries your main stream (camera, game, graphics—whatever you configure as your “live” look) and a scene where **Clipshow’s window**—the built-in 16:9 player—is the primary source for replays and analysis. Fullscreen playback, frame-accurate seeking, and telestration (below) replace a loose combination of external player, drawing tool, and manual OBS scene changes, while optional integrations still advance OBS and other tools on enter and exit so the rest of your stack stays aligned.

### 8.1 Entering playout

From the dashboard, use **Playout** in Manage or the play control on a file row. The dashboard UI is replaced by the player until you leave.

### 8.2 OBS and the broadcast chain

When integrations are enabled, entering Playout switches OBS’s **program** scene to the one you configured for showing this application; leaving Playout (`Escape`) switches back to your configured “live” scene and restores the dashboard (scroll position is restored when possible). The same transitions can also invoke **HTTP webhooks** you configured in Workspace settings so companion automation stays in step. None of this runs if OBS or webhooks are disabled—you can still use Playout as a local fullscreen reviewer.

### 8.3 Window and layout

Playout constrains the window to **16:9**, hides the normal title bar for a clean capture, sizes the window from the source (with sensible minimums), and may use fullscreen depending on build settings; windowed playout remains typical for OBS Window Capture.

### 8.4 End of video

For clips and master files, playback **pauses on the last frame** so you can keep commenting or drawing before you exit, or seek to other points in the file to replay certain parts of it.

### 8.5 Keyboard — playback and navigation


| Action                             | Shortcut      |
| ---------------------------------- | ------------- |
| Play / pause                       | Space         |
| Seek ±100 ms                       | Alt + ← / →   |
| Seek ±1 s                          | ← / →         |
| Seek ±5 s                          | Ctrl + ← / →  |
| Seek ±15 s                         | Shift + ← / → |
| Jump to start / end                | Home / End    |
| Toggle help overlay                | H             |
| Exit playout (return to dashboard) | Escape        |


> Screenshot (placeholder): Playout screen with optional help/hints visible.

### 8.6 Telestrator (drawing on air)

While Playout is active you can draw on top of the picture for commentary—strokes live on a transparent overlay and are not burned into a file. Defaults (colors, brush, whether drawing starts on or off) come from Workspace settings (§9).


| Action                 | Shortcut  |
| ---------------------- | --------- |
| Toggle drawing mode    | T         |
| Clear strokes          | C         |
| Undo                   | Z         |
| Pen colors             | 1 / 2 / 3 |
| Smaller / larger brush | [ / ]     |


Leaving Playout clears the canvas for the next session.

> Screenshot (placeholder): Playout with arrows or circles drawn over the video.

---

## 9. Workspace settings

Open **Workspace settings** from the gear control in the dashboard header. Everything here is stored in the current workspace’s database and applies only while that workspace is open.

Each section's settings are saved separately. Use the blue button at the bottom of each section to persist its settings.

### 9.1 Telestrator defaults

Defaults for Playout drawing: three stroke colors, brush size, and whether telestration starts enabled when you enter Playout. These complement the in-session shortcuts described in §8.

### 9.2 Decoder config

Choose which decode **profiles** are active and in what **priority order**, plus separate dropdowns for **MDK** and **fvp** (video playback libraries) log verbosity when you need diagnostics. **Apply Decoder Settings** commits the list; this section is mainly for troubleshooting or tuning playback on a specific GPU stack.

The application must be restarted when changing decoder configuration.

### 9.3 Ingestion and preview

**Pause background ingest during Manage playback** reduces concurrent disk access while the Manage-column player is playing (useful on slow USB disks). Full-window **Playout** always pauses background ingest regardless of this toggle for maximum playback stability.

### 9.4 Scene switch settings

Scene switching is modeled as **profiles**: one **OBS** connection (host, port, password, enable/disable) plus any number of **HTTP webhooks**. Each profile can be turned on or off without deleting it.

Under **OBS**, set the WebSocket address and the **program** scene names Clipshow should select for “video” (showing this app), “face” (your live/camera layout), and optionally **capture** (switched before OBS recording starts in Capture mode—§7). Save applies that block.

**OBS Capture paths** are the workspace-relative **recording** and **output** folders used in Capture mode: OBS writes the growing file under **recording** (typically ignored by ingestion); **Stop And Save** copies the finished file into **output** (empty means the workspace root). Output must not sit inside the recording tree—the UI rejects bad combinations. This is the settings-side view of the same paths explained in §7.

Under **Webhooks**, add HTTP endpoints that fire on the same playout enter/exit transitions as OBS (method, URL, and body/query shape). Saved webhooks appear in the profile list with their own enable switches. The payload value is always a fixed token—**video** when entering Playout and **face** when leaving—under your chosen query parameter or JSON/form key (not your OBS scene names).

### 9.5 Ignored folders

Workspace-relative directory paths that ingestion skips entirely (including nested files). You can add paths manually; the Capture **recording** folder may also be registered here automatically so partial recordings stay out of the library until the finished copy lands elsewhere.

### 9.6 Export workspace

Write workspace metadata and media rows to JSON for backup or tooling (full JSON shape is described in §10). Video files themselves are never copied.

Apply changes using the dialog’s save actions; invalid capture/output pairings are blocked or explained inline.

> Screenshot (placeholder): Workspace settings dialog with OBS and Capture sections visible.

---

## 10. Export

Under **Export workspace** in Workspace settings (§9.6), **Export JSON** opens a save dialog (default name `workspace_export.json`). The app writes a single JSON document with top-level keys `**workspacePath`** (absolute root you have open), `**settings`**, and `**mediaItems**`—one media object per master or clip currently in the library.

The **settings** object mirrors what lives in the workspace database: telestrator defaults, decoder profile names and verbosity levels, OBS WebSocket configuration (including scene names), webhook definitions, capture recording/output paths, and ignored-folder entries. **Media items** include workspace-relative paths, display overrides, sorted tag lists, and for clips the in/out millisecond range.

Video files are **not** copied or embedded; the export is metadata only. Treat the file as **sensitive** if your OBS block includes a password—it is serialized in plain text. Use the export for backups, migration notes, or external tooling that understands this shape.

---

## 11. Tips and troubleshooting

Most issues fall into a few buckets: integration connectivity, tooling on disk, capture path layout, playback tuning, and how workspaces move between machines.

### 11.1 OBS indicator red or scene switches failing

The antenna icon in the dashboard header (§4) reflects whether Clipshow’s last periodic WebSocket check reached OBS. If it stays red, confirm OBS is running, WebSocket is enabled in OBS (typical port **4455**), and host, port, and password in Workspace settings (§9) match. Scene names must be **program** scenes exactly as named in OBS. After correcting settings, wait for the next check or restart the app if needed.

### 11.2 Thumbnails or durations missing

Sidecar thumbnails (`*.thumb.jpg` next to each video) are produced with **ffprobe** (duration) and **ffmpeg** (frame grab). Both commands must be available on your **PATH** like any other CLI tool—install FFmpeg per §2.2. If a file is corrupt or unreadable, the list may show a problem state instead of a thumbnail.

### 11.3 Capture stopped but no new library item

Follow the Capture flow end-to-end (§7): recording must finish cleanly with **Stop And Save**, the **output** folder must be somewhere ingestion scans (not inside an incorrectly ignored tree), and output cannot be nested inside the **recording** staging folder. Very slow disks may need a moment after stop before the copy appears.

### 11.4 Playback stutters, errors, or wrong decoder behavior

Try adjusting **Decoder config** in Workspace settings (§9)—profile order and availability depend on your operating system, GPU, and drivers. For diagnostics, raise **MDK** or **fvp** log verbosity temporarily; remember to lower it afterward.

### 11.5 Manage shortcuts ignored

Keyboard shortcuts in the Manage player (§6) apply when that region has focus—click the video surface if keys stop responding after interacting elsewhere.

### 11.6 Moving or cloning a workspace

Keep `**obs_clipshow.db`** at the workspace root together with your media tree. Paths inside the database are relative to that root; moving the whole folder preserves them as long as internal layout stays the same.

### 11.7 Webhooks or companion automation out of sync

Confirm each webhook entry is enabled, URLs are reachable, and method and body or query settings match what your receiver expects (§9). Payload values are always the literals **video** (enter Playout) and **face** (leave)—not your OBS scene names. Webhooks fire when you enter and leave Playout—the same moments as OBS **program** scene switches when OBS integration is enabled. Each transition attempts every enabled webhook once, and failures are logged rather than retried automatically.

### 11.8 Exported JSON

See §10 for contents. Do not share exports casually if they include secrets or internal paths you consider private.