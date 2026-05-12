import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_media_tag_menu.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
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
    final double pad12 = scaleDimension(context, 12);
    final double pad8 = scaleDimension(context, 8);
    final double gap8 = scaleDimension(context, 8);
    final double gap12 = scaleDimension(context, 12);
    final double gap16 = scaleDimension(context, 16);
    final double gap6 = scaleDimension(context, 6);
    final double gap4 = scaleDimension(context, 4);
    final double chipSpacing = scaleDimension(context, 6);
    final double chipRunSpacing = scaleDimension(context, 4);
    final double headerBottomPad = scaleDimension(context, 6);
    final double thumbWidth = scaleDimension(context, 72);
    final double thumbHeight = scaleDimension(context, 40);
    final double editIconSize = scaleDimension(context, 14);
    final double rowHPad = scaleDimension(context, 16);
    final double rowVPad = scaleDimension(context, 12);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(pad12, pad12, pad12, pad8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text("Files"),
                    SizedBox(width: gap8),
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
                    SizedBox(width: gap8),
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
                    SizedBox(width: gap8),
                    FilterChip(
                      label: const Text("Untagged"),
                      selected: viewModel.showUntaggedOnly,
                      onSelected: viewModel.setShowUntaggedOnly,
                    ),
                  ],
                ),
                SizedBox(height: gap8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Wrap(
                        spacing: gap8,
                        runSpacing: gap8,
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
                                onDeleted: () => viewModel.toggleTagFilter(tag),
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
                    SizedBox(width: gap12),
                    Padding(
                      padding: EdgeInsets.only(top: headerBottomPad),
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
                final List<MediaTagAttachment> tagAttachments =
                    sortMediaTagAttachments(
                      viewModel.tagAttachmentsForItem(item),
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
                      padding: EdgeInsets.symmetric(
                        horizontal: rowHPad,
                        vertical: rowVPad,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: thumbWidth,
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
                                  SizedBox(height: gap4),
                                ],
                                _ThumbnailPreview(
                                  videoPath:
                                      WorkspaceMediaPaths.absoluteMasterPath(
                                        workspacePath,
                                        item.filePath,
                                      ),
                                  issue: mediaIssue,
                                  width: thumbWidth,
                                  height: thumbHeight,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: gap16),
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
                                        WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              left: gap6,
                                            ),
                                            child: Icon(
                                              Icons.edit,
                                              size: editIconSize,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: gap6),
                                Text(
                                  relativePath,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: gap4),
                                Wrap(
                                  spacing: chipSpacing,
                                  runSpacing: chipRunSpacing,
                                  children: tagAttachments.isEmpty
                                      ? <Widget>[const Text("No tags")]
                                      : tagAttachments
                                            .map(
                                              (
                                                MediaTagAttachment att,
                                              ) => GestureDetector(
                                                onSecondaryTapUp:
                                                    (TapUpDetails d) {
                                                      unawaited(
                                                        showMediaTagContextMenu(
                                                          context: context,
                                                          viewModel: viewModel,
                                                          attachment: att,
                                                          globalPosition:
                                                              d.globalPosition,
                                                        ),
                                                      );
                                                    },
                                                child: ActionChip(
                                                  label:
                                                      mediaTagAttachmentChipLabel(
                                                        att,
                                                      ),
                                                  backgroundColor: tagChipColor(
                                                    context,
                                                    att.tagName,
                                                  ),
                                                  onPressed: () =>
                                                      viewModel.toggleTagFilter(
                                                        att.tagName,
                                                      ),
                                                ),
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
                                      osgPresetVisibleInitial: viewModel
                                          .previewOsgPresetVisibility,
                                      semanticTagSnapshotVersion: viewModel
                                          .semanticTagSnapshotForItem(item),
                                      semanticTypeIdsOnMedia: viewModel
                                          .semanticTypeIdsOnMedia(item),
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
  const _ThumbnailPreview({
    required this.videoPath,
    required this.issue,
    required this.width,
    required this.height,
  });

  final String videoPath;
  final MediaIssue issue;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double radius = scaleDimension(context, 4);
    final double issueIconSize = scaleDimension(context, 22);
    final double neutralIconSize = scaleDimension(context, 18);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: issue != MediaIssue.none
            ? _issueThumbPlaceholder(issue, scheme, issueIconSize)
            : _thumbnailOrFallback(videoPath, neutralIconSize),
      ),
    );
  }

  Widget _thumbnailOrFallback(String videoPath, double iconSize) {
    final String thumbnailPath = "$videoPath.thumb.jpg";
    final File thumbFile = File(thumbnailPath);

    return thumbFile.existsSync()
        ? Image.file(
            thumbFile,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _neutralFallback(iconSize),
          )
        : _neutralFallback(iconSize);
  }

  Widget _issueThumbPlaceholder(
    MediaIssue issue,
    ColorScheme scheme,
    double iconSize,
  ) {
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
      child: Icon(icon, size: iconSize, color: fg),
    );
  }

  Widget _neutralFallback(double iconSize) {
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: Icon(Icons.movie, size: iconSize),
    );
  }
}
