import "dart:async";

import "package:flutter/material.dart";
import "package:path/path.dart" as p;
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/bake/osg_bake_service.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_preview_hotkeys_layer.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
import "package:obs_clipshow/src/features/playout/clip_player_view.dart";
import "package:obs_clipshow/src/features/playout/osg_playout_layer.dart";
import "package:obs_clipshow/src/util/reveal_file_in_folder.dart";
import "package:obs_clipshow/src/workspace/workspace_media_paths.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/widgets/transient_hud_banner.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

class DashboardPreviewPanel extends StatefulWidget {
  const DashboardPreviewPanel({
    super.key,
    required this.onPlayClip,
    required this.onRecordClip,
    required this.focusNode,
  });

  final void Function(PlayoutClip clip) onPlayClip;
  final void Function(PlayoutClip clip) onRecordClip;
  final FocusNode focusNode;

  @override
  State<DashboardPreviewPanel> createState() => _DashboardPreviewPanelState();
}

class _DashboardPreviewPanelState extends State<DashboardPreviewPanel> {
  final ClipPlayerController _previewPlayerController = ClipPlayerController();
  DashboardViewModel? _viewModel;
  bool _showPreviewHelp = false;

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
    final double pad12 = scaleDimension(context, 12);
    final double gap12 = scaleDimension(context, 12);
    final double gap8 = scaleDimension(context, 8);
    final double radius8 = scaleDimension(context, 8);
    final EdgeInsets nudgeButtonPadding = EdgeInsets.symmetric(
      horizontal: scaleDimension(context, 8),
      vertical: scaleDimension(context, 4),
    );
    final PlayoutClip? previewOsgClip =
        workspaceRoot != null &&
            selectedItem != null &&
            previewIssue == MediaIssue.none
        ? toPlayoutClip(
            selectedItem,
            workspaceRoot: workspaceRoot,
            initialOffsetMs: viewModel.previewPositionMs,
            semanticTagSnapshotVersion:
                viewModel.semanticTagSnapshotForItem(selectedItem),
            semanticTypeIdsOnMedia:
                viewModel.semanticTypeIdsOnMedia(selectedItem),
          )
        : null;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(pad12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("Preview"),
            SizedBox(height: gap12),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => widget.focusNode.requestFocus(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius8),
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
                            onOsgPresetSlotToggle: workspaceRoot == null
                                ? null
                                : viewModel.togglePreviewOsgPresetSlot,
                            onVolumeUpRequested: () => viewModel
                                .nudgeClipVolume(PlaybackVolumeDefaults.step),
                            onVolumeDownRequested: () => viewModel
                                .nudgeClipVolume(-PlaybackVolumeDefaults.step),
                            onMuteToggleRequested: viewModel.toggleClipMute,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                ClipPlayerView(
                                  clickTogglesPlayback: true,
                                  controller: _previewPlayerController,
                                  beforeVideoInitialize:
                                      viewModel.awaitPreviewPlayerInitGate,
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
                                  volume: viewModel.effectiveClipVolume,
                                  onPositionChanged:
                                      viewModel.setPreviewPositionMs,
                                  onPlayingChanged: _onPreviewPlayingChanged,
                                  videoAreaOverlay: previewOsgClip != null &&
                                          workspaceRoot != null
                                      ? OsgPlayoutLayer(
                                          key: ValueKey<String>(
                                            selectedItem.stableKey,
                                          ),
                                          clip: previewOsgClip,
                                          config: viewModel.osgWorkspaceConfig,
                                          workspaceRoot: workspaceRoot,
                                          resolveSemantic:
                                              (int semanticTypeId) =>
                                                  viewModel
                                                      .resolveSemanticTagText(
                                                    previewOsgClip,
                                                    semanticTypeId,
                                                  ),
                                          visible: viewModel.previewOsgPresetVisibility,
                                        )
                                      : null,
                                ),
                                if (viewModel.previewOsgRequirementFlashToken > 0)
                                  Positioned(
                                    left: pad12,
                                    top: pad12,
                                    child: TransientHudBanner(
                                      key: ValueKey<int>(
                                        viewModel.previewOsgRequirementFlashToken,
                                      ),
                                      text: viewModel.previewOsgRequirementFlashText,
                                      onDismissed: () => viewModel
                                          .clearPreviewOsgRequirementFlash(),
                                    ),
                                  ),
                                if (viewModel.previewVolumeHudToken > 0)
                                  Positioned(
                                    right: pad12,
                                    top: pad12,
                                    child: TransientHudBanner(
                                      key: ValueKey<int>(
                                        viewModel.previewVolumeHudToken,
                                      ),
                                      text: viewModel.previewVolumeHudText,
                                      onDismissed:
                                          viewModel.clearPreviewVolumeHud,
                                    ),
                                  ),
                                if (_showPreviewHelp)
                                  _PreviewHelpOverlay(
                                    showMarkHotkeys:
                                        selectedMedia != null &&
                                        !isClipSelection,
                                    isClipPreview: isClipSelection,
                                    showOsgHotkeys: workspaceRoot != null,
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
            SizedBox(height: gap12),
            Wrap(
              spacing: gap8,
              runSpacing: gap8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (previewOsgClip != null) ...<Widget>[
                  Text(
                    "OSG",
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  ToggleButtons(
                    borderRadius: BorderRadius.circular(radius8),
                    constraints: BoxConstraints(
                      minWidth: scaleDimension(context, 30),
                      minHeight: scaleDimension(context, 28),
                    ),
                    isSelected: <bool>[
                      for (final OsgPresetSlot s in OsgPresetSlot.values)
                        viewModel.previewOsgPresetVisibility[s],
                    ],
                    onPressed: (int index) {
                      viewModel.togglePreviewOsgPresetSlot(
                        OsgPresetSlot.values[index],
                      );
                    },
                    children: <Widget>[
                      for (final OsgPresetSlot s in OsgPresetSlot.values)
                        Text(s.playoutHotkeyDigitLabel),
                    ],
                  ),
                ],
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
                  Padding(
                    padding: EdgeInsets.only(
                      top: scaleDimension(context, 6),
                    ),
                    child: const Text("Nudge Start:"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipStart(-2500)),
                    child: const Text("-2.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipStart(-500)),
                    child: const Text("-0.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipStart(500)),
                    child: const Text("+0.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipStart(2500)),
                    child: const Text("+2.5s"),
                  ),
                  SizedBox(width: pad12),
                  Padding(
                    padding: EdgeInsets.only(
                      top: scaleDimension(context, 6),
                    ),
                    child: const Text("End:"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipEnd(-2500)),
                    child: const Text("-2.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipEnd(-500)),
                    child: const Text("-0.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: nudgeButtonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        unawaited(viewModel.nudgeSelectedClipEnd(500)),
                    child: const Text("+0.5s"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: nudgeButtonPadding,
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
                FilledButton.tonalIcon(
                  onPressed:
                      selectedItem == null ||
                          previewIssue != MediaIssue.none ||
                          workspaceRoot == null ||
                          viewModel.osgBakeRecipes.isEmpty ||
                          viewModel.bakeActive
                      ? null
                      : () => unawaited(_startBake(context, viewModel)),
                  icon: const Icon(Icons.movie_creation_outlined),
                  label: const Text("Bake"),
                ),
                FilledButton.icon(
                  onPressed:
                      selectedItem == null ||
                          previewIssue != MediaIssue.none ||
                          workspaceRoot == null ||
                          viewModel.obsSceneSwitchConfig?.enabled != true ||
                          viewModel.obsCaptureRecording
                      ? null
                      : () => widget.onRecordClip(
                          toPlayoutClip(
                            selectedItem,
                            workspaceRoot: workspaceRoot,
                            initialOffsetMs: viewModel.previewPositionMs,
                            osgPresetVisibleInitial:
                                viewModel.previewOsgPresetVisibility,
                            semanticTagSnapshotVersion: viewModel
                                .semanticTagSnapshotForItem(selectedItem),
                            semanticTypeIdsOnMedia: viewModel
                                .semanticTypeIdsOnMedia(selectedItem),
                          ),
                        ),
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text("Record"),
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
                            osgPresetVisibleInitial:
                                viewModel.previewOsgPresetVisibility,
                            semanticTagSnapshotVersion: viewModel
                                .semanticTagSnapshotForItem(selectedItem),
                            semanticTypeIdsOnMedia: viewModel
                                .semanticTypeIdsOnMedia(selectedItem),
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

  Future<void> _startBake(
    BuildContext context,
    DashboardViewModel viewModel,
  ) async {
    final OsgBakeRecipe? recipe = await _pickBakeRecipe(
      context,
      viewModel.osgBakeRecipes,
    );
    if (recipe == null || !context.mounted) {
      return;
    }
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  SizedBox(width: scaleDimension(ctx, 16)),
                  const Text("Rendering\u2026"),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => viewModel.requestBakeCancel(),
                  child: const Text("Cancel"),
                ),
              ],
            ),
          );
        },
      ),
    );
    final OsgBakeResult result = await viewModel.bakeSelectedItem(recipe);
    if (!context.mounted) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pop();
    final String? destPath = result.destPath;
    if (destPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Baked to ${p.basename(destPath)}"),
          showCloseIcon: true,
          action: SnackBarAction(
            label: "Reveal",
            onPressed: () {
              unawaited(() async {
                try {
                  await revealFileInFolder(destPath);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Could not open file manager: $e"),
                      ),
                    );
                  }
                }
              }());
            },
          ),
        ),
      );
    } else if (result.errorMessage == "Bake cancelled.") {
      // Operator dismissed the bake; no follow-up snackbar.
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? "Bake failed.")),
      );
    }
  }

  Future<OsgBakeRecipe?> _pickBakeRecipe(
    BuildContext context,
    List<OsgBakeRecipe> recipes,
  ) {
    return showDialog<OsgBakeRecipe>(
      context: context,
      builder: (BuildContext ctx) {
        return SimpleDialog(
          title: const Text("Bake with recipe"),
          children: recipes
              .map(
                (OsgBakeRecipe recipe) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(recipe),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(recipe.name),
                      Text(
                        recipe.cues.map(osgBakeCueSummaryLabel).join("; "),
                        style: Theme.of(ctx).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
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
    this.showOsgHotkeys = false,
  });

  final bool showMarkHotkeys;
  final bool isClipPreview;
  final bool showOsgHotkeys;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double pad20 = scaleDimension(context, 20);
    final double gap12 = scaleDimension(context, 12);
    final double gap10 = scaleDimension(context, 10);
    final double gap6 = scaleDimension(context, 6);
    final double maxHelpWidth = scaleDimension(context, 560);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxHelpWidth),
          child: Card(
            color: colorScheme.surface.withValues(alpha: 0.96),
            child: Padding(
              padding: EdgeInsets.all(pad20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Manage Hotkeys",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: gap12),
                  _previewHotkeySection("Playback", <String, String>{
                    "Space": "Play/Pause",
                  }),
                  SizedBox(height: gap10),
                  _previewHotkeySection("Seek", <String, String>{
                    "Left / Right": "Seek 1s",
                    "Ctrl + Left / Right": "Seek 5s",
                    "Shift + Left / Right": "Seek 15s",
                    "Alt + Left / Right": "Seek 0.1s",
                    "Home / End": "Jump To Start / End",
                  }),
                  SizedBox(height: gap10),
                  _previewHotkeySection("Volume", <String, String>{
                    "Up / Down": "Volume +/- 10%",
                    "M": "Toggle Mute",
                  }),
                  if (showMarkHotkeys) ...<Widget>[
                    SizedBox(height: gap10),
                    _previewHotkeySection("Mark Clip", <String, String>{
                      "I": "Mark In",
                      "O": "Mark Out",
                      "S": "Save Clip",
                    }),
                  ],
                  if (isClipPreview) ...<Widget>[
                    SizedBox(height: gap10),
                    Text(
                      "Clip Range",
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SizedBox(height: gap6),
                    Text(
                      "Nudge start and end with the -2.5s / -0.5s / +0.5s / "
                      "+2.5s buttons below the player (no keyboard shortcuts).",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  if (showOsgHotkeys) ...<Widget>[
                    SizedBox(height: gap10),
                    _previewHotkeySection("OSG", <String, String>{
                      "6 / 7 / 8 / 9 / 0": "Toggle OSG Presets 1 Through 5",
                    }),
                  ],
                  SizedBox(height: gap10),
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
        final double gap6 = scaleDimension(context, 6);
        final double rowVertPad = scaleDimension(context, 2);
        final double keyColWidth = scaleDimension(context, 200);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            SizedBox(height: gap6),
            ...entries.entries.map(
              (MapEntry<String, String> item) => Padding(
                padding: EdgeInsets.symmetric(vertical: rowVertPad),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: keyColWidth,
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
    final double pad24 = scaleDimension(context, 24);
    final double gap16 = scaleDimension(context, 16);
    final double issueIconSize = scaleDimension(context, 48);
    final IconData icon = issue == MediaIssue.empty
        ? Icons.insert_drive_file_outlined
        : Icons.close;
    final String message = issue == MediaIssue.empty
        ? "This file is empty (0 bytes)."
        : "This file could not be read (missing moov / corrupt / invalid).";

    return Center(
      child: Padding(
        padding: EdgeInsets.all(pad24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white54, size: issueIconSize),
            SizedBox(height: gap16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            if (issue == MediaIssue.unreadable &&
                detail != null &&
                detail!.trim().isNotEmpty) ...<Widget>[
              SizedBox(height: gap16),
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
