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
