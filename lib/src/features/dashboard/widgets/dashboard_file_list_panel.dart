import "dart:io";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/media/media_clip.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/workspace/workspace_media_paths.dart";

class DashboardFileListPanel extends StatelessWidget {
  const DashboardFileListPanel({
    super.key,
    required this.workspacePath,
    required this.mediaItems,
    required this.onPlayClip,
    required this.onMediaItemSelected,
    required this.onPreviewFocusRequested,
    this.scrollController,
  });

  final String workspacePath;
  final List<MediaListItem> mediaItems;
  final void Function(PlayoutClip clip) onPlayClip;
  final void Function(MediaListItem item) onMediaItemSelected;
  final VoidCallback onPreviewFocusRequested;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    bool handledSearchAutocompleteSelection = false;
    TextEditingController? activeSearchInputController;
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
                      child: AdaptiveAutocomplete<String>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          return viewModel.searchTagSuggestionsFor(
                            textEditingValue.text,
                          );
                        },
                        onSelected: (String value) {
                          handledSearchAutocompleteSelection = true;
                          viewModel.addTagFilter(value);
                          activeSearchInputController?.clear();
                          viewModel.setTagSearchQuery("");
                        },
                        fieldViewBuilder:
                            (
                              BuildContext context,
                              TextEditingController textEditingController,
                              FocusNode focusNode,
                              VoidCallback onFieldSubmitted,
                            ) {
                              activeSearchInputController =
                                  textEditingController;
                              if (textEditingController.text !=
                                  viewModel.tagSearchQuery) {
                                textEditingController.text =
                                    viewModel.tagSearchQuery;
                                textEditingController.selection =
                                    TextSelection.collapsed(
                                      offset: textEditingController.text.length,
                                    );
                              }
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: "Search tag to filter",
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: viewModel.setTagSearchQuery,
                                onTapOutside: (_) {
                                  focusNode.unfocus();
                                  onPreviewFocusRequested();
                                },
                                onSubmitted: (_) {
                                  onFieldSubmitted();
                                  if (handledSearchAutocompleteSelection) {
                                    handledSearchAutocompleteSelection = false;
                                    return;
                                  }
                                  viewModel.addTagFilter(
                                    textEditingController.text,
                                  );
                                  textEditingController.clear();
                                  viewModel.setTagSearchQuery("");
                                },
                              );
                            },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: viewModel.fileNameSearchQuery,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: viewModel.fileSearchUsesFullPath
                              ? "Search workspace path"
                              : "Search filename",
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: viewModel.fileSearchUsesFullPath
                                ? "Searching full workspace path (click for filename only)"
                                : "Searching filename only (click for full workspace path)",
                            icon: Icon(
                              viewModel.fileSearchUsesFullPath
                                  ? Icons.folder_open
                                  : Icons.description_outlined,
                            ),
                            onPressed: viewModel.toggleFileSearchScope,
                          ),
                        ),
                        onChanged: viewModel.setFileNameSearchQuery,
                        onTapOutside: (_) {
                          FocusScope.of(context).unfocus();
                          onPreviewFocusRequested();
                        },
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: () {
                          final List<Widget> chips = <Widget>[];
                          final String? clipFilterLabel =
                              viewModel.clipsOfMasterFilterChipLabel;
                          if (clipFilterLabel != null) {
                            chips.add(
                              InputChip(
                                label: Text(clipFilterLabel),
                                onDeleted: viewModel.clearClipsOfMasterFilter,
                              ),
                            );
                          }
                          chips.addAll(
                            viewModel.activeTagFilters.map(
                              (String tag) => InputChip(
                                label: Text("Filter: $tag"),
                                onDeleted: () =>
                                    viewModel.toggleTagFilter(tag),
                              ),
                            ),
                          );
                          if (chips.isEmpty) {
                            chips.add(const Text("No active tag filters"));
                          }
                          return chips;
                        }(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        "${mediaItems.length} ${mediaItems.length == 1 ? "file" : "files"}",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
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
                final String relativePath =
                    WorkspaceMediaPaths.displayRelativeToWorkspace(
                  workspacePath,
                  item.filePath,
                );
                final bool isSelected =
                    viewModel.selectedItemKey == item.stableKey;
                final MediaIssue mediaIssue = item.mediaIssue;
                final List<String> tags = sortTags(
                  viewModel.tagsForItem(item).toList(),
                );
                final String? durationAboveThumb = _durationLabelAboveThumbnail(
                  item,
                );

                final ThemeData theme = Theme.of(context);
                return Material(
                  color: isSelected
                      ? theme.colorScheme.surfaceContainerHighest
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      onMediaItemSelected(item);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 72,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                if (durationAboveThumb != null) ...<Widget>[
                                  Text(
                                    durationAboveThumb,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontFeatures: const <FontFeature>[
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                _ThumbnailPreview(
                                  videoPath:
                                      WorkspaceMediaPaths.absoluteMasterPath(
                                    workspacePath,
                                    item.filePath,
                                  ),
                                  issue: mediaIssue,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text.rich(
                                  TextSpan(
                                    children: <InlineSpan>[
                                      TextSpan(
                                        text:
                                            item.type ==
                                                MediaListItemType.master
                                            ? item.displayName
                                            : "${item.displayName} (${clipRangeLabel(item.clip!)})",
                                      ),
                                      if (item.displayName != item.fileName)
                                        const WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Padding(
                                            padding: EdgeInsets.only(left: 6),
                                            child: Icon(Icons.edit, size: 14),
                                          ),
                                        ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  relativePath,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
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
                                                backgroundColor: tagChipColor(
                                                  context,
                                                  tag,
                                                ),
                                                onPressed: () => viewModel
                                                    .toggleTagFilter(tag),
                                              ),
                                            )
                                            .toList(),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: mediaIssue == MediaIssue.none
                                ? "Play"
                                : mediaIssue == MediaIssue.empty
                                ? "Empty file"
                                : "Unreadable or corrupt file",
                            onPressed: mediaIssue == MediaIssue.none
                                ? () => onPlayClip(
                                    toPlayoutClip(
                                      item,
                                      workspaceRoot: workspacePath,
                                    ),
                                  )
                                : null,
                            icon: Icon(
                              mediaIssue == MediaIssue.none
                                  ? Icons.play_arrow
                                  : mediaIssue == MediaIssue.empty
                                  ? Icons.remove_circle_outline
                                  : Icons.close,
                            ),
                          ),
                        ],
                      ),
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
}

/// Master: probed file duration when present. Clip: marked segment length when out point is set.
String? _durationLabelAboveThumbnail(MediaListItem item) {
  if (item.type == MediaListItemType.master) {
    final int? ms = item.master!.durationMs;
    if (ms == null) {
      return null;
    }
    return formatMs(ms);
  }
  final MediaClip clip = item.clip!;
  if (clip.outMs == null) {
    return null;
  }
  final int lenMs = clip.outMs! - clip.inMs;
  if (lenMs <= 0) {
    return null;
  }
  return formatMs(lenMs);
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
