import "dart:io";
import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:path/path.dart" as p;

import "../../media/master_media_file.dart";
import "../../media/media_clip.dart";
import "../../media/media_list_item.dart";
import "../playout/clip_player_view.dart";
import "../playout/playout_clip.dart";
import "dashboard_view_model.dart";

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.viewModel,
    required this.onPlayClip,
    this.scrollController,
  });

  final DashboardViewModel viewModel;
  final void Function(PlayoutClip clip) onPlayClip;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          appBar: AppBar(title: const Text("dashboard")),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _WorkspaceHeader(viewModel: viewModel),
                const SizedBox(height: 16),
                Expanded(
                  child: _BodyState(
                    viewModel: viewModel,
                    isLoading: viewModel.isLoading,
                    workspacePath: viewModel.workspacePath,
                    mediaFiles: viewModel.mediaFiles,
                    onPlayClip: onPlayClip,
                    scrollController: scrollController,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            viewModel.workspacePath == null
                ? "No workspace selected."
                : "Workspace: ${viewModel.workspacePath}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: viewModel.isLoading ? null : viewModel.pickAndSetWorkspace,
          child: Text(
            viewModel.workspacePath == null
                ? "Select Workspace"
                : "Change Workspace",
          ),
        ),
      ],
    );
  }
}

class _BodyState extends StatelessWidget {
  const _BodyState({
    required this.viewModel,
    required this.isLoading,
    required this.workspacePath,
    required this.mediaFiles,
    required this.onPlayClip,
    this.scrollController,
  });

  final DashboardViewModel viewModel;
  final bool isLoading;
  final String? workspacePath;
  final List<MasterMediaFile> mediaFiles;
  final void Function(PlayoutClip clip) onPlayClip;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (workspacePath == null) {
      return const Center(
        child: Text("Select a workspace to start ingesting media."),
      );
    }
    final List<MediaListItem> visibleMediaItems = viewModel.visibleItems;
    if (mediaFiles.isEmpty) {
      return const Center(
        child: Text("No supported media files found in this workspace."),
      );
    }
    return Row(
      children: <Widget>[
        Expanded(
          flex: 4,
          child: _FileListPanel(
            viewModel: viewModel,
            workspacePath: workspacePath!,
            mediaItems: visibleMediaItems,
            scrollController: scrollController,
            onPlayClip: onPlayClip,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 6,
          child: Column(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: _PreviewPanel(
                  viewModel: viewModel,
                  onPlayClip: onPlayClip,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(child: _TagPanel(viewModel: viewModel)),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileListPanel extends StatelessWidget {
  const _FileListPanel({
    required this.viewModel,
    required this.workspacePath,
    required this.mediaItems,
    required this.onPlayClip,
    this.scrollController,
  });

  final DashboardViewModel viewModel;
  final String workspacePath;
  final List<MediaListItem> mediaItems;
  final void Function(PlayoutClip clip) onPlayClip;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text("Files"),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: "Search tag to filter",
                          border: OutlineInputBorder(),
                        ),
                        onChanged: viewModel.setTagSearchQuery,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text("Untagged"),
                      selected: viewModel.showUntaggedOnly,
                      onSelected: viewModel.setShowUntaggedOnly,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: viewModel.activeTagFilters.isEmpty
                      ? <Widget>[const Text("No active tag filters")]
                      : viewModel.activeTagFilters
                            .map(
                              (String tag) => InputChip(
                                label: Text("Filter: $tag"),
                                onDeleted: () => viewModel.toggleTagFilter(tag),
                              ),
                            )
                            .toList(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              itemCount: mediaItems.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final MediaListItem item = mediaItems[index];
                final String relativePath = p.relative(
                  item.filePath,
                  from: workspacePath,
                );
                final bool isSelected =
                    viewModel.selectedItemKey == item.stableKey;
                final MediaIssue mediaIssue = item.mediaIssue;
                final List<String> tags = _sortTags(
                  viewModel.tagsForItem(item).toList(),
                );

                return ListTile(
                  selected: isSelected,
                  selectedTileColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  leading: _ThumbnailPreview(
                    videoPath: item.filePath,
                    issue: mediaIssue,
                  ),
                  title: Text(
                    item.type == MediaListItemType.master
                        ? item.fileName
                        : "${item.fileName} (${_clipRangeLabel(item.clip!)})",
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        relativePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: tags.isEmpty
                            ? <Widget>[const Text("No tags")]
                            : tags
                                  .map(
                                    (String tag) => ActionChip(
                                      label: Text(tag),
                                      backgroundColor: _tagChipColor(
                                        context,
                                        tag,
                                      ),
                                      onPressed: () =>
                                          viewModel.toggleTagFilter(tag),
                                    ),
                                  )
                                  .toList(),
                      ),
                    ],
                  ),
                  onTap: () => viewModel.selectItem(item),
                  trailing: IconButton(
                    tooltip: mediaIssue == MediaIssue.none
                        ? "Play"
                        : mediaIssue == MediaIssue.empty
                        ? "Empty file"
                        : "Unreadable or corrupt file",
                    onPressed: mediaIssue == MediaIssue.none
                        ? () => onPlayClip(_toPlayoutClip(item))
                        : null,
                    icon: Icon(
                      mediaIssue == MediaIssue.none
                          ? Icons.play_arrow
                          : mediaIssue == MediaIssue.empty
                          ? Icons.remove_circle_outline
                          : Icons.close,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _clipRangeLabel(MediaClip clip) {
    final int start = clip.inMs;
    final int? end = clip.outMs;
    if (end == null) {
      return "${_formatMs(start)} - End";
    }
    return "${_formatMs(start)} - ${_formatMs(end)}";
  }

  String _formatMs(int value) {
    final Duration duration = Duration(milliseconds: value);
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds % 60;
    return "${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
  }

  PlayoutClip _toPlayoutClip(MediaListItem item) {
    if (item.type == MediaListItemType.master) {
      return PlayoutClip(
        filePath: item.filePath,
        startTimeMs: 0,
        endTimeMs: null,
      );
    }
    return PlayoutClip(
      filePath: item.filePath,
      startTimeMs: item.clip!.inMs,
      endTimeMs: item.clip!.outMs,
    );
  }
}

class _PreviewPanel extends StatefulWidget {
  const _PreviewPanel({required this.viewModel, required this.onPlayClip});

  final DashboardViewModel viewModel;
  final void Function(PlayoutClip clip) onPlayClip;

  @override
  State<_PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<_PreviewPanel> {
  final ClipPlayerController _previewPlayerController = ClipPlayerController();

  @override
  Widget build(BuildContext context) {
    final MediaListItem? selectedItem = widget.viewModel.selectedItem;
    final MasterMediaFile? selectedMedia = widget.viewModel.selectedMedia;
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
                      : _PreviewHotkeysLayer(
                          controller: _previewPlayerController,
                          onMarkInRequested: selectedMedia == null
                              ? null
                              : widget.viewModel.markInAtCurrentPosition,
                          onMarkOutRequested: selectedMedia == null
                              ? null
                              : widget.viewModel.markOutAtCurrentPosition,
                          onSaveClipRequested: selectedMedia == null
                              ? null
                              : () => widget.viewModel.saveClipFromCurrentMarks(
                                  context,
                                ),
                          child: ClipPlayerView(
                            controller: _previewPlayerController,
                            filePath: selectedItem.filePath,
                            startTimeMs:
                                selectedItem.type == MediaListItemType.clip
                                ? selectedItem.clip!.inMs
                                : 0,
                            endTimeMs: selectedItem.type == MediaListItemType.clip
                                ? selectedItem.clip!.outMs
                                : null,
                            autoPlay: false,
                            showControls: true,
                            onPositionChanged:
                                widget.viewModel.setPreviewPositionMs,
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
                      : widget.viewModel.markInAtCurrentPosition,
                  child: Text(
                    widget.viewModel.markInMs == null
                        ? "(i) Mark In"
                        : "(i) Mark In ${_formatMs(widget.viewModel.markInMs!)}",
                  ),
                ),
                OutlinedButton(
                  onPressed: selectedMedia == null
                      ? null
                      : widget.viewModel.markOutAtCurrentPosition,
                  child: Text(
                    widget.viewModel.markOutMs == null
                        ? "(o) Mark Out"
                        : "Mark Out ${_formatMs(widget.viewModel.markOutMs!)}",
                  ),
                ),
                OutlinedButton(
                  onPressed: selectedMedia == null
                      ? null
                      : () => widget.viewModel.saveClipFromCurrentMarks(context),
                  child: const Text("(s) Save Clip"),
                ),
                OutlinedButton.icon(
                  onPressed: selectedItem == null || selectedItem.type != MediaListItemType.clip
                      ? null
                      : () async {
                          final String? error = await widget.viewModel
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
                      : () => widget.onPlayClip(
                          PlayoutClip(
                            filePath: selectedItem.filePath,
                            startTimeMs:
                                selectedItem.type == MediaListItemType.clip
                                ? selectedItem.clip!.inMs
                                : 0,
                            endTimeMs:
                                selectedItem.type == MediaListItemType.clip
                                ? selectedItem.clip!.outMs
                                : null,
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

  String _formatMs(int value) {
    final Duration duration = Duration(milliseconds: value);
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds % 60;
    return "${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
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

class _TagPanel extends StatefulWidget {
  const _TagPanel({required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  State<_TagPanel> createState() => _TagPanelState();
}

class _TagPanelState extends State<_TagPanel> {
  late final TextEditingController _savedTagController;
  TextEditingController? _activeTagInputController;
  bool _handledAutocompleteSelection = false;

  @override
  void initState() {
    super.initState();
    _savedTagController = TextEditingController();
  }

  @override
  void dispose() {
    _savedTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaListItem? selectedItem = widget.viewModel.selectedItem;
    final List<String> selectedTags =
        selectedItem == null
              ? <String>[]
              : _sortTags(widget.viewModel.tagsForItem(selectedItem).toList());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("Tags"),
            const SizedBox(height: 12),
            if (selectedItem == null)
              const Expanded(
                child: Center(child: Text("Select a file to manage tags.")),
              )
            else ...<Widget>[
              Text(
                selectedItem.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: selectedTags
                    .map(
                      (String tag) => InputChip(
                        label: Text(tag),
                        backgroundColor: _tagChipColor(context, tag),
                        onDeleted: () => unawaited(
                          widget.viewModel.removeTagFromSelectedMedia(tag),
                        ),
                        onPressed: () =>
                            widget.viewModel.toggleTagFilter(tag),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        return widget.viewModel.tagSuggestionsFor(
                          textEditingValue.text,
                        );
                      },
                      onSelected: (String value) {
                        _handledAutocompleteSelection = true;
                        unawaited(widget.viewModel.addTagToSelectedMedia(value));
                        _activeTagInputController?.clear();
                      },
                      fieldViewBuilder:
                          (
                            BuildContext context,
                            TextEditingController textEditingController,
                            FocusNode focusNode,
                            VoidCallback onFieldSubmitted,
                          ) {
                            _activeTagInputController = textEditingController;
                            return TextField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: "Add Tag",
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) {
                                onFieldSubmitted();
                                if (_handledAutocompleteSelection) {
                                  _handledAutocompleteSelection = false;
                                  return;
                                }
                                _submitTag(textEditingController);
                              },
                            );
                          },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final TextEditingController? controller =
                          _activeTagInputController;
                      if (controller == null) {
                        return;
                      }
                      _submitTag(controller);
                    },
                    child: const Text("Add"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(),
              Row(
                children: <Widget>[
                  const Text("Saved Tags"),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: OutlinedButton.icon(
                      onPressed: widget.viewModel.savedTags.isEmpty
                          ? null
                          : () => unawaited(
                                widget.viewModel
                                    .applyAllSavedTagsToSelectedMedia(),
                              ),
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text("Apply"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.viewModel.savedTags
                    .map(
                      (String tag) => InputChip(
                        label: Text(tag),
                        onDeleted: () =>
                            unawaited(widget.viewModel.removeSavedTag(tag)),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _savedTagController,
                      decoration: const InputDecoration(
                        labelText: "Add Saved Tag",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submitSavedTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submitSavedTag,
                    child: const Text("Add"),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _submitTag(TextEditingController controller) {
    final String tag = controller.text.trim();
    if (tag.isEmpty) {
      return;
    }
    unawaited(widget.viewModel.addTagToSelectedMedia(tag));
    controller.clear();
  }

  void _submitSavedTag() {
    final String tag = _savedTagController.text.trim();
    if (tag.isEmpty) {
      return;
    }
    unawaited(widget.viewModel.addSavedTag(tag));
    _savedTagController.clear();
  }
}

class _PreviewMarkInIntent extends Intent {
  const _PreviewMarkInIntent();
}

class _PreviewMarkOutIntent extends Intent {
  const _PreviewMarkOutIntent();
}

class _PreviewSaveClipIntent extends Intent {
  const _PreviewSaveClipIntent();
}

class _PreviewSeekBackwardIntent extends Intent {
  const _PreviewSeekBackwardIntent();
}

class _PreviewSeekForwardIntent extends Intent {
  const _PreviewSeekForwardIntent();
}

class _PreviewSeekShortBackwardIntent extends Intent {
  const _PreviewSeekShortBackwardIntent();
}

class _PreviewSeekShortForwardIntent extends Intent {
  const _PreviewSeekShortForwardIntent();
}

class _PreviewSeekLongBackwardIntent extends Intent {
  const _PreviewSeekLongBackwardIntent();
}

class _PreviewSeekLongForwardIntent extends Intent {
  const _PreviewSeekLongForwardIntent();
}

class _PreviewHotkeysLayer extends StatelessWidget {
  const _PreviewHotkeysLayer({
    required this.child,
    required this.controller,
    this.onMarkInRequested,
    this.onMarkOutRequested,
    this.onSaveClipRequested,
  });

  final Widget child;
  final ClipPlayerController controller;
  final VoidCallback? onMarkInRequested;
  final VoidCallback? onMarkOutRequested;
  final VoidCallback? onSaveClipRequested;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _PreviewSeekBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _PreviewSeekForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            const _PreviewSeekShortBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            const _PreviewSeekShortForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            const _PreviewSeekLongBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            const _PreviewSeekLongForwardIntent(),
        if (onMarkInRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyI):
              const _PreviewMarkInIntent(),
        if (onMarkOutRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyO):
              const _PreviewMarkOutIntent(),
        if (onSaveClipRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyS):
              const _PreviewSaveClipIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              controller.togglePlayPause();
              return null;
            },
          ),
          _PreviewSeekBackwardIntent: CallbackAction<_PreviewSeekBackwardIntent>(
            onInvoke: (_) {
              controller.seekBy(const Duration(seconds: -5));
              return null;
            },
          ),
          _PreviewSeekForwardIntent: CallbackAction<_PreviewSeekForwardIntent>(
            onInvoke: (_) {
              controller.seekBy(const Duration(seconds: 5));
              return null;
            },
          ),
          _PreviewSeekShortBackwardIntent:
              CallbackAction<_PreviewSeekShortBackwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: -1));
                  return null;
                },
              ),
          _PreviewSeekShortForwardIntent:
              CallbackAction<_PreviewSeekShortForwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: 1));
                  return null;
                },
              ),
          _PreviewSeekLongBackwardIntent:
              CallbackAction<_PreviewSeekLongBackwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: -15));
                  return null;
                },
              ),
          _PreviewSeekLongForwardIntent:
              CallbackAction<_PreviewSeekLongForwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: 15));
                  return null;
                },
              ),
          _PreviewMarkInIntent: CallbackAction<_PreviewMarkInIntent>(
            onInvoke: (_) {
              onMarkInRequested?.call();
              return null;
            },
          ),
          _PreviewMarkOutIntent: CallbackAction<_PreviewMarkOutIntent>(
            onInvoke: (_) {
              onMarkOutRequested?.call();
              return null;
            },
          ),
          _PreviewSaveClipIntent: CallbackAction<_PreviewSaveClipIntent>(
            onInvoke: (_) {
              onSaveClipRequested?.call();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

List<String> _sortTags(List<String> tags) {
  tags.sort((String a, String b) {
    final bool aSystem = _isSystemTag(a);
    final bool bSystem = _isSystemTag(b);
    if (aSystem && !bSystem) {
      return -1;
    }
    if (!aSystem && bSystem) {
      return 1;
    }
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return tags;
}

bool _isSystemTag(String tag) => tag == "Master" || tag == "Clip";

Color? _tagChipColor(BuildContext context, String tag) {
  if (!_isSystemTag(tag)) {
    return null;
  }
  final Color base = Theme.of(context).colorScheme.surfaceContainerHighest;
  return base.withValues(alpha: 0.5);
}

class _ThumbnailPreview extends StatelessWidget {
  const _ThumbnailPreview({required this.videoPath, required this.issue});

  final String videoPath;
  final MediaIssue issue;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 72,
        height: 40,
        child: issue != MediaIssue.none
            ? _issueThumbPlaceholder(issue, scheme)
            : _thumbnailOrFallback(videoPath),
      ),
    );
  }

  Widget _thumbnailOrFallback(String videoPath) {
    final String thumbnailPath = "$videoPath.thumb.jpg";
    final File thumbFile = File(thumbnailPath);

    return thumbFile.existsSync()
        ? Image.file(
            thumbFile,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _neutralFallback(),
          )
        : _neutralFallback();
  }

  Widget _issueThumbPlaceholder(MediaIssue issue, ColorScheme scheme) {
    final Color bg = issue == MediaIssue.empty
        ? scheme.surfaceContainerHighest
        : scheme.errorContainer;
    final Color fg = issue == MediaIssue.empty
        ? scheme.onSurfaceVariant
        : scheme.onErrorContainer;
    final IconData icon = issue == MediaIssue.empty
        ? Icons.horizontal_rule
        : Icons.close;

    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Icon(icon, size: 22, color: fg),
    );
  }

  Widget _neutralFallback() {
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.movie, size: 18),
    );
  }
}
