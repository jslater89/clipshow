import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_preview_hotkeys_layer.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
import "package:obs_clipshow/src/features/playout/clip_player_view.dart";
import "package:obs_clipshow/src/workspace/workspace_media_paths.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";

class DashboardPreviewPanel extends StatefulWidget {
  const DashboardPreviewPanel({
    super.key,
    required this.onPlayClip,
    required this.focusNode,
  });

  final void Function(PlayoutClip clip) onPlayClip;
  final FocusNode focusNode;

  @override
  State<DashboardPreviewPanel> createState() => _DashboardPreviewPanelState();
}

class _DashboardPreviewPanelState extends State<DashboardPreviewPanel> {
  final ClipPlayerController _previewPlayerController = ClipPlayerController();
  DashboardViewModel? _viewModel;
  bool _showPreviewHelp = false;
  static const EdgeInsets _nudgeButtonPadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 4,
  );

  void _togglePreviewHelp() {
    setState(() {
      _showPreviewHelp = !_showPreviewHelp;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel = Provider.of<DashboardViewModel>(context, listen: false);
  }

  @override
  void dispose() {
    _viewModel?.setPreviewPlaying(false);
    super.dispose();
  }

  void _onPreviewPlayingChanged(bool playing) {
    _viewModel?.setPreviewPlaying(playing);
  }

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final String? workspaceRoot = viewModel.workspacePath;
    final MediaListItem? selectedItem = viewModel.selectedItem;
    final MasterMediaFile? selectedMedia = viewModel.selectedMedia;
    final MediaIssue previewIssue = selectedItem == null
        ? MediaIssue.none
        : selectedItem.mediaIssue;
    final bool isClipSelection =
        selectedItem != null && selectedItem.type == MediaListItemType.clip;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("Preview"),
            const SizedBox(height: 12),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => widget.focusNode.requestFocus(),
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
                            focusNode: widget.focusNode,
                            onHelpToggleRequested: _togglePreviewHelp,
                            onMarkInRequested: selectedMedia == null
                                ? null
                                : viewModel.markInAtCurrentPosition,
                            onMarkOutRequested: selectedMedia == null
                                ? null
                                : viewModel.markOutAtCurrentPosition,
                            onSaveClipRequested: selectedMedia == null
                                ? null
                                : () => viewModel.saveClipFromCurrentMarks(
                                    context,
                                  ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                ClipPlayerView(
                                  clickTogglesPlayback: true,
                                  controller: _previewPlayerController,
                                  filePath: workspaceRoot == null
                                      ? selectedItem.filePath
                                      : WorkspaceMediaPaths.absoluteMasterPath(
                                          workspaceRoot,
                                          selectedItem.filePath,
                                        ),
                                  startTimeMs:
                                      selectedItem.type ==
                                          MediaListItemType.clip
                                      ? selectedItem.clip!.inMs
                                      : 0,
                                  endTimeMs:
                                      selectedItem.type ==
                                          MediaListItemType.clip
                                      ? selectedItem.clip!.outMs
                                      : null,
                                  autoPlay: false,
                                  showControls: true,
                                  onPositionChanged:
                                      viewModel.setPreviewPositionMs,
                                  onPlayingChanged: _onPreviewPlayingChanged,
                                ),
                                if (_showPreviewHelp)
                                  _PreviewHelpOverlay(
                                    showMarkHotkeys:
                                        selectedMedia != null &&
                                        !isClipSelection,
                                    isClipPreview: isClipSelection,
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                if (!isClipSelection) ...<Widget>[
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
                ],
                if (isClipSelection) ...<Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text("Nudge Start:"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: _nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipStart(-2500)),
                    child: const Text("-2.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: _nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipStart(-500)),
                    child: const Text("-0.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: _nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipStart(500)),
                    child: const Text("+0.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: _nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipStart(2500)),
                    child: const Text("+2.5s"),
                  ),
                  const SizedBox(width: 12),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text("End:"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: _nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipEnd(-2500)),
                    child: const Text("-2.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: _nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipEnd(-500)),
                    child: const Text("-0.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: _nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipEnd(500)),
                    child: const Text("+0.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: _nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipEnd(2500)),
                    child: const Text("+2.5s"),
                  ),
                ],
                if (isClipSelection)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final bool ok = await _confirmDeleteClip(context);
                      if (!ok || !context.mounted) {
                        return;
                      }
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
                  )
                else
                  OutlinedButton.icon(
                    onPressed: selectedMedia == null
                        ? null
                        : () async {
                            final bool ok = await _confirmTrashMasterFile(
                              context,
                            );
                            if (!ok || !context.mounted) {
                              return;
                            }
                            final String? error = await viewModel
                                .trashSelectedMasterFile();
                            if (error != null && context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text(error)));
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text("Trash File"),
                  ),
                FilledButton.icon(
                  onPressed:
                      selectedItem == null ||
                          previewIssue != MediaIssue.none ||
                          workspaceRoot == null
                      ? null
                      : () => widget.onPlayClip(
                          toPlayoutClip(
                            selectedItem,
                            workspaceRoot: workspaceRoot,
                            initialOffsetMs: viewModel.previewPositionMs,
                          ),
                        ),
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

  Future<bool> _confirmDeleteClip(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text("Delete Clip"),
          content: const Text(
            "Remove this clip from the library? The source video file will not be deleted.",
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<bool> _confirmTrashMasterFile(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text("Move File To Trash"),
          content: const Text(
            "Move this video to the system trash and remove it from the library? "
            "All clips that reference this file will be removed.",
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Move To Trash"),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

}

class _PreviewHelpOverlay extends StatelessWidget {
  const _PreviewHelpOverlay({
    required this.showMarkHotkeys,
    required this.isClipPreview,
  });

  final bool showMarkHotkeys;
  final bool isClipPreview;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            color: colorScheme.surface.withValues(alpha: 0.96),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Preview Hotkeys",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _previewHotkeySection("Playback", <String, String>{
                    "Space": "Play/Pause",
                  }),
                  const SizedBox(height: 10),
                  _previewHotkeySection("Seek", <String, String>{
                    "Left / Right": "Seek 1s",
                    "Ctrl + Left / Right": "Seek 5s",
                    "Shift + Left / Right": "Seek 15s",
                    "Alt + Left / Right": "Seek 0.1s",
                    "Home / End": "Jump To Start / End",
                  }),
                  if (showMarkHotkeys) ...<Widget>[
                    const SizedBox(height: 10),
                    _previewHotkeySection("Mark Clip", <String, String>{
                      "I": "Mark In",
                      "O": "Mark Out",
                      "S": "Save Clip",
                    }),
                  ],
                  if (isClipPreview) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      "Clip Range",
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Nudge start and end with the -2.5s / -0.5s / +0.5s / "
                      "+2.5s buttons below the preview (no keyboard shortcuts).",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 10),
                  _previewHotkeySection("Help", <String, String>{
                    "H": "Toggle This Help",
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewHotkeySection(String title, Map<String, String> entries) {
    return Builder(
      builder: (BuildContext context) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            ...entries.entries.map(
              (MapEntry<String, String> item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 200,
                      child: Text(
                        item.key,
                        style: TextStyle(
                          fontFamily: "monospace",
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: Text(item.value)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
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
