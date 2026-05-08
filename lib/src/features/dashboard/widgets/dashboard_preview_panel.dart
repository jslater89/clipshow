import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_preview_hotkeys_layer.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
import "package:obs_clipshow/src/features/playout/clip_player_view.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";

class DashboardPreviewPanel extends StatefulWidget {
  const DashboardPreviewPanel({super.key, required this.onPlayClip});

  final void Function(PlayoutClip clip) onPlayClip;

  @override
  State<DashboardPreviewPanel> createState() => _DashboardPreviewPanelState();
}

class _DashboardPreviewPanelState extends State<DashboardPreviewPanel> {
  final ClipPlayerController _previewPlayerController = ClipPlayerController();
  static const String _debugLogPath =
      "/home/jay/development/personal/obs_clipshow/.cursor/debug-c1d67a.log";
  String? _lastLoggedSelectionKey;

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final MediaListItem? selectedItem = viewModel.selectedItem;
    final MasterMediaFile? selectedMedia = viewModel.selectedMedia;
    if (selectedItem?.stableKey != _lastLoggedSelectionKey) {
      _lastLoggedSelectionKey = selectedItem?.stableKey;
      // #region agent log
      _debugLog(
        hypothesisId: "H1,H2,H4",
        location: "dashboard_preview_panel.dart:build:selectionChanged",
        message: "Preview selection changed",
        data: <String, Object?>{
          "selectedItemKey": selectedItem?.stableKey,
          "selectedPath": selectedItem?.filePath,
          "selectedType": selectedItem?.type.name,
          "selectedIssue": selectedItem?.mediaIssue.name,
        },
      );
      // #endregion
    }
    final MediaIssue previewIssue = selectedItem == null
        ? MediaIssue.none
        : selectedItem.mediaIssue;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("Preview"),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.black,
                  child: selectedItem == null
                      ? const Center(
                          child: Text(
                            "Select a file from the list.",
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : previewIssue != MediaIssue.none
                      ? _PreviewIssueMessage(
                          issue: previewIssue,
                          detail: selectedItem.mediaIssueDetail,
                        )
                      : DashboardPreviewHotkeysLayer(
                          controller: _previewPlayerController,
                          onMarkInRequested: selectedMedia == null
                              ? null
                              : viewModel.markInAtCurrentPosition,
                          onMarkOutRequested: selectedMedia == null
                              ? null
                              : viewModel.markOutAtCurrentPosition,
                          onSaveClipRequested: selectedMedia == null
                              ? null
                              : () =>
                                    viewModel.saveClipFromCurrentMarks(context),
                          child: ClipPlayerView(
                            controller: _previewPlayerController,
                            filePath: selectedItem.filePath,
                            startTimeMs:
                                selectedItem.type == MediaListItemType.clip
                                ? selectedItem.clip!.inMs
                                : 0,
                            endTimeMs:
                                selectedItem.type == MediaListItemType.clip
                                ? selectedItem.clip!.outMs
                                : null,
                            autoPlay: false,
                            showControls: true,
                            onPositionChanged: viewModel.setPreviewPositionMs,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                OutlinedButton(
                  onPressed: selectedMedia == null
                      ? null
                      : viewModel.markInAtCurrentPosition,
                  child: Text(
                    viewModel.markInMs == null
                        ? "(i) Mark In"
                        : "(i) Mark In ${formatMs(viewModel.markInMs!)}",
                  ),
                ),
                OutlinedButton(
                  onPressed: selectedMedia == null
                      ? null
                      : viewModel.markOutAtCurrentPosition,
                  child: Text(
                    viewModel.markOutMs == null
                        ? "(o) Mark Out"
                        : "Mark Out ${formatMs(viewModel.markOutMs!)}",
                  ),
                ),
                OutlinedButton(
                  onPressed: selectedMedia == null
                      ? null
                      : () => viewModel.saveClipFromCurrentMarks(context),
                  child: const Text("(s) Save Clip"),
                ),
                OutlinedButton.icon(
                  onPressed:
                      selectedItem == null ||
                          selectedItem.type != MediaListItemType.clip
                      ? null
                      : () async {
                          final String? error = await viewModel
                              .deleteSelectedClip();
                          if (error != null && context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(error)));
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text("Delete Clip"),
                ),
                FilledButton.icon(
                  onPressed:
                      selectedItem == null || previewIssue != MediaIssue.none
                      ? null
                      : () => widget.onPlayClip(toPlayoutClip(selectedItem)),
                  icon: const Icon(Icons.fullscreen),
                  label: const Text("Playout"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _debugLog({
    required String hypothesisId,
    required String location,
    required String message,
    required Map<String, Object?> data,
    String runId = "initial",
  }) {
    final Map<String, Object?> payload = <String, Object?>{
      "sessionId": "c1d67a",
      "runId": runId,
      "hypothesisId": hypothesisId,
      "location": location,
      "message": message,
      "data": data,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };
    unawaited(_appendDebugLog(payload));
  }

  Future<void> _appendDebugLog(Map<String, Object?> payload) async {
    try {
      await File(_debugLogPath).writeAsString(
        "${jsonEncode(payload)}\n",
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }
}

class _PreviewIssueMessage extends StatelessWidget {
  const _PreviewIssueMessage({required this.issue, this.detail});

  final MediaIssue issue;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final IconData icon = issue == MediaIssue.empty
        ? Icons.insert_drive_file_outlined
        : Icons.close;
    final String message = issue == MediaIssue.empty
        ? "This file is empty (0 bytes)."
        : "This file could not be read (missing moov / corrupt / invalid).";

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            if (issue == MediaIssue.unreadable &&
                detail != null &&
                detail!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              SelectableText(
                detail!.trim(),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  height: 1.35,
                  fontFamily: "monospace",
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
