import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/data/media_repository.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_media_tag_menu.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";

class DashboardTagPanel extends StatefulWidget {
  const DashboardTagPanel({super.key, required this.onPreviewFocusRequested});

  final VoidCallback onPreviewFocusRequested;

  @override
  State<DashboardTagPanel> createState() => _DashboardTagPanelState();
}

class _DashboardTagPanelState extends State<DashboardTagPanel> {
  TextEditingController? _activeTagInputController;
  TextEditingController? _activeSavedTagInputController;
  bool _handledAutocompleteSelection = false;
  bool _handledSavedAutocompleteSelection = false;
  final TextEditingController _annotationsController = TextEditingController();
  final FocusNode _annotationsFocus = FocusNode();
  String? _lastAnnotationsItemKey;

  @override
  void dispose() {
    _annotationsController.dispose();
    _annotationsFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final MediaListItem? selectedItem = viewModel.selectedItem;
    final String? selectedKey = selectedItem?.stableKey;
    if (selectedKey != null && _lastAnnotationsItemKey != selectedKey) {
      _lastAnnotationsItemKey = selectedKey;
      final String next = selectedItem?.annotations ?? "";
      _annotationsController.text = next;
    } else if (selectedItem == null && _lastAnnotationsItemKey != null) {
      _lastAnnotationsItemKey = null;
      _annotationsController.text = "";
    } else if (selectedItem != null && !_annotationsFocus.hasFocus) {
      final String next = selectedItem.annotations ?? "";
      if (next != _annotationsController.text) {
        _annotationsController.text = next;
      }
    }
    final List<MediaTagAttachment> selectedTagAttachments = selectedItem == null
        ? <MediaTagAttachment>[]
        : sortMediaTagAttachments(
            viewModel.tagAttachmentsForItem(selectedItem),
          );
    final bool selectedHasUserTags = selectedTagAttachments.any(
      (MediaTagAttachment a) => !isSystemTag(a.tagName),
    );
    final double pad12 = scaleDimension(context, 12);
    final double gap12 = scaleDimension(context, 12);
    final double gap10 = scaleDimension(context, 10);
    final double gap8 = scaleDimension(context, 8);
    final double emptyStateVertPad = scaleDimension(context, 24);
    final double editIconSize = scaleDimension(context, 16);
    final double fieldMaxWidth = scaleDimension(context, 400);
    final String storedAnnotations = selectedItem?.annotations ?? "";
    final bool annotationsDirty =
        selectedItem != null && _annotationsController.text != storedAnnotations;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(pad12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text("Tags"),
              SizedBox(height: gap12),
              if (selectedItem == null)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: emptyStateVertPad),
                  child: const Center(
                    child: Text("Select a file to manage tags."),
                  ),
                )
              else ...<Widget>[
                if (selectedItem.type == MediaListItemType.tagSet)
                  // Tag sets are renamed from their preview card (see
                  // DashboardTagSetPane); displayName always equals the
                  // real tag_sets.name, there's no override to edit here.
                  Text(
                    selectedItem.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          selectedItem.displayName == selectedItem.fileName
                              ? selectedItem.fileName
                              : "${selectedItem.displayName} (${selectedItem.fileName})",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: gap8),
                      TextButton.icon(
                        onPressed: () async {
                          final String? updated =
                              await _showRenameDisplayNameDialog(
                                context,
                                initialValue: selectedItem.displayName,
                              );
                          if (updated == null) {
                            return;
                          }
                          final String? override =
                              updated.trim().isEmpty ||
                                  updated.trim() == selectedItem.fileName
                              ? null
                              : updated.trim();
                          await viewModel.setDisplayNameOverride(
                            selectedItem,
                            override,
                          );
                        },
                        icon: Icon(Icons.edit, size: editIconSize),
                        label: const Text("Edit"),
                      ),
                      TextButton(
                        onPressed:
                            selectedItem.displayName == selectedItem.fileName
                            ? null
                            : () => unawaited(
                                viewModel.setDisplayNameOverride(
                                  selectedItem,
                                  null,
                                ),
                              ),
                        child: const Text("Clear"),
                      ),
                    ],
                  ),
                SizedBox(height: gap10),
                if (selectedItem.type == MediaListItemType.clip)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        final String? error =
                            viewModel.selectMasterForClip(selectedItem);
                        if (error != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error)),
                          );
                        }
                      },
                      child: const Text("Go to Source Master"),
                    ),
                  ),
                if (selectedItem.type == MediaListItemType.master &&
                    viewModel.clipCountForMaster(selectedItem.master!.id) > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => viewModel.toggleClipsOfMasterFilter(
                        selectedItem.master!.id,
                      ),
                      child: Text(
                        viewModel.clipsOfMasterFilterMediaId ==
                                selectedItem.master!.id
                            ? "Clear Clip Filter"
                            : "Show Clips",
                      ),
                    ),
                  ),
                if (selectedItem.type == MediaListItemType.clip ||
                    (selectedItem.type == MediaListItemType.master &&
                        viewModel.clipCountForMaster(selectedItem.master!.id) >
                            0))
                  SizedBox(height: gap10),
                Wrap(
                  spacing: gap8,
                  runSpacing: gap8,
                  children: selectedTagAttachments.map((
                    MediaTagAttachment att,
                  ) {
                    final bool isSystemTag =
                        att.tagName == MediaRepository.masterTag ||
                        att.tagName == MediaRepository.clipTag;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        GestureDetector(
                          onSecondaryTapUp: (TapUpDetails d) {
                            unawaited(
                              showMediaTagContextMenu(
                                context: context,
                                viewModel: viewModel,
                                attachment: att,
                                globalPosition: d.globalPosition,
                              ),
                            );
                          },
                          child: InputChip(
                            label: mediaTagAttachmentChipLabel(att),
                            backgroundColor: tagChipColor(context, att.tagName),
                            onDeleted: isSystemTag
                                ? null
                                : () => unawaited(
                                    viewModel.removeTagFromSelectedMedia(
                                      att.tagName,
                                    ),
                                  ),
                            onPressed: () =>
                                viewModel.toggleTagFilter(att.tagName),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
                SizedBox(height: gap10),
                Row(
                  children: <Widget>[
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: fieldMaxWidth),
                      child: AdaptiveAutocomplete<String>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          return viewModel.tagSuggestionsFor(
                            textEditingValue.text,
                          );
                        },
                        onSelected: (String value) {
                          _handledAutocompleteSelection = true;
                          unawaited(viewModel.addTagToSelectedMedia(value));
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
                                onTapOutside: (_) {
                                  focusNode.unfocus();
                                  widget.onPreviewFocusRequested();
                                },
                                onSubmitted: (_) {
                                  onFieldSubmitted();
                                  if (_handledAutocompleteSelection) {
                                    _handledAutocompleteSelection = false;
                                    return;
                                  }
                                  _submitTag(viewModel, textEditingController);
                                },
                              );
                            },
                      ),
                    ),
                    SizedBox(width: gap8),
                    FilledButton(
                      onPressed: () {
                        final TextEditingController? controller =
                            _activeTagInputController;
                        if (controller == null) {
                          return;
                        }
                        _submitTag(viewModel, controller);
                      },
                      child: const Text("Add"),
                    ),
                    SizedBox(width: gap8),
                    OutlinedButton.icon(
                      onPressed: !selectedHasUserTags
                          ? null
                          : () => unawaited(
                              viewModel.mergeSelectedItemTagsIntoSaved(),
                            ),
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text("saved"),
                    ),
                    SizedBox(width: gap8),
                    OutlinedButton.icon(
                      onPressed: !selectedHasUserTags
                          ? null
                          : () async {
                              final bool filteredOnly =
                                  viewModel.hasActiveItemFilters;
                              final int count = viewModel
                                  .countItemsNeedingSelectedTagsApply(
                                    filteredOnly: filteredOnly,
                                  );
                              if (!context.mounted) {
                                return;
                              }
                              final String targetLabel = filteredOnly
                                  ? "filtered"
                                  : "all";
                              if (count == 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "No $targetLabel items changed.",
                                    ),
                                  ),
                                );
                                return;
                              }
                              final bool? confirmed =
                                  await _showApplyTagsToManyConfirmDialog(
                                    context,
                                    fileCount: count,
                                    tags: sortShelfTagEntries(
                                      viewModel.selectedItemUserShelfTags,
                                    ),
                                    semanticTypes: viewModel.tagSemanticTypes,
                                  );
                              if (confirmed != true || !context.mounted) {
                                return;
                              }
                              final int changedItems = await viewModel
                                  .applySelectedItemTagsToItems(
                                    filteredOnly: filteredOnly,
                                  );
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    changedItems == 0
                                        ? "No $targetLabel items changed."
                                        : "Applied tags to $changedItems $targetLabel item${changedItems == 1 ? "" : "s"}.",
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        viewModel.hasActiveItemFilters ? "filtered" : "all",
                      ),
                    ),
                    SizedBox(width: gap8),
                    OutlinedButton.icon(
                      onPressed: !selectedHasUserTags
                          ? null
                          : () => viewModel.mergeSelectedItemTagsIntoCapture(),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text("capture"),
                    ),
                  ],
                ),
                SizedBox(height: gap12),
                const Divider(),
                Row(children: <Widget>[const Text("Saved Tags")]),
                SizedBox(height: gap8),
                Wrap(
                  spacing: gap8,
                  runSpacing: gap8,
                  children: sortShelfTagEntries(viewModel.savedTags)
                      .map(
                        (ShelfTagEntry e) => Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            GestureDetector(
                              onSecondaryTapUp: (TapUpDetails d) {
                                unawaited(
                                  showShelfTagContextMenu(
                                    context: context,
                                    viewModel: viewModel,
                                    entry: e,
                                    target: DashboardShelfTagMenuTarget.saved,
                                    globalPosition: d.globalPosition,
                                  ),
                                );
                              },
                              child: InputChip(
                                label: shelfTagChipLabel(
                                  e,
                                  viewModel.tagSemanticTypes,
                                ),
                                backgroundColor: tagChipColor(context, e.name),
                                onDeleted: () =>
                                    unawaited(viewModel.removeSavedTag(e.name)),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
                SizedBox(height: gap10),
                Row(
                  children: <Widget>[
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: fieldMaxWidth),
                      child: AdaptiveAutocomplete<String>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          return viewModel.tagSuggestionsFor(
                            textEditingValue.text,
                          );
                        },
                        onSelected: (String value) {
                          _handledSavedAutocompleteSelection = true;
                          unawaited(viewModel.addSavedTag(value));
                          _activeSavedTagInputController?.clear();
                        },
                        fieldViewBuilder:
                            (
                              BuildContext context,
                              TextEditingController textEditingController,
                              FocusNode focusNode,
                              VoidCallback onFieldSubmitted,
                            ) {
                              _activeSavedTagInputController =
                                  textEditingController;
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: "Add Saved Tag",
                                  border: OutlineInputBorder(),
                                ),
                                onTapOutside: (_) {
                                  focusNode.unfocus();
                                  widget.onPreviewFocusRequested();
                                },
                                onSubmitted: (_) {
                                  onFieldSubmitted();
                                  if (_handledSavedAutocompleteSelection) {
                                    _handledSavedAutocompleteSelection = false;
                                    return;
                                  }
                                  _submitSavedTag(
                                    viewModel,
                                    textEditingController,
                                  );
                                },
                              );
                            },
                      ),
                    ),
                    SizedBox(width: gap8),
                    FilledButton(
                      onPressed: () {
                        final TextEditingController? controller =
                            _activeSavedTagInputController;
                        if (controller == null) {
                          return;
                        }
                        _submitSavedTag(viewModel, controller);
                      },
                      child: const Text("Add"),
                    ),
                    SizedBox(width: gap8),
                    OutlinedButton.icon(
                      onPressed: viewModel.savedTags.isEmpty
                          ? null
                          : () async {
                              final bool filteredOnly =
                                  viewModel.hasActiveItemFilters;
                              final int count = viewModel
                                  .countItemsNeedingSavedTagsApply(
                                    filteredOnly: filteredOnly,
                                  );
                              if (!context.mounted) {
                                return;
                              }
                              final String targetLabel = filteredOnly
                                  ? "filtered"
                                  : "all";
                              if (count == 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "No $targetLabel items changed.",
                                    ),
                                  ),
                                );
                                return;
                              }
                              final bool? confirmed =
                                  await _showApplyTagsToManyConfirmDialog(
                                    context,
                                    fileCount: count,
                                    tags: sortShelfTagEntries(
                                      viewModel.savedTags,
                                    ),
                                    semanticTypes: viewModel.tagSemanticTypes,
                                  );
                              if (confirmed != true || !context.mounted) {
                                return;
                              }
                              final int changedItems = await viewModel
                                  .applyAllSavedTagsToItems(
                                    filteredOnly: filteredOnly,
                                  );
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    changedItems == 0
                                        ? "No $targetLabel items changed."
                                        : "Applied saved tags to $changedItems $targetLabel item${changedItems == 1 ? "" : "s"}.",
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        viewModel.hasActiveItemFilters ? "filtered" : "all",
                      ),
                    ),
                    SizedBox(width: gap8),
                    OutlinedButton.icon(
                      onPressed: viewModel.savedTags.isEmpty
                          ? null
                          : () => unawaited(
                              viewModel.applyAllSavedTagsToSelectedMedia(),
                            ),
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text("current"),
                    ),
                    SizedBox(width: gap8),
                    OutlinedButton.icon(
                      onPressed: viewModel.savedTags.isEmpty
                          ? null
                          : () => viewModel.mergeSavedTagsIntoCapture(),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text("capture"),
                    ),
                  ],
                ),
                SizedBox(height: gap10),
                const Divider(),
                Text(
                  "Annotations",
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SizedBox(height: scaleDimension(context, 6)),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: fieldMaxWidth),
                  child: TextField(
                    controller: _annotationsController,
                    focusNode: _annotationsFocus,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: "Notes for this item (not searchable)",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    onTapOutside: (_) {
                      widget.onPreviewFocusRequested();
                      _annotationsFocus.unfocus();
                    },
                  ),
                ),
                SizedBox(height: scaleDimension(context, 8)),
                Wrap(
                  spacing: gap8,
                  runSpacing: gap8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: !annotationsDirty
                          ? null
                          : () async {
                              final MediaListItem? item =
                                  viewModel.selectedItem;
                              if (item == null) {
                                return;
                              }
                              final String text =
                                  _annotationsController.text;
                              await viewModel.setAnnotations(item, text);
                              if (!mounted) {
                                return;
                              }
                              setState(() {});
                              _annotationsFocus.unfocus();
                            },
                      icon: const Icon(Icons.save),
                      label: const Text("Save"),
                    ),
                    OutlinedButton.icon(
                      onPressed: !annotationsDirty
                          ? null
                          : () {
                              _annotationsController.text =
                                  storedAnnotations;
                              _annotationsFocus.unfocus();
                              setState(() {});
                            },
                      icon: const Icon(Icons.undo),
                      label: const Text("Revert"),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _submitTag(
    DashboardViewModel viewModel,
    TextEditingController controller,
  ) {
    final String tag = controller.text.trim();
    if (tag.isEmpty) {
      return;
    }
    unawaited(viewModel.addTagToSelectedMedia(tag));
    controller.clear();
  }

  void _submitSavedTag(
    DashboardViewModel viewModel,
    TextEditingController controller,
  ) {
    final String tag = controller.text.trim();
    if (tag.isEmpty) {
      return;
    }
    unawaited(viewModel.addSavedTag(tag));
    controller.clear();
  }
}

Future<bool?> _showApplyTagsToManyConfirmDialog(
  BuildContext context, {
  required int fileCount,
  required List<ShelfTagEntry> tags,
  required List<TagSemanticType> semanticTypes,
}) async {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text("Apply Tags"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text("Add tags to $fileCount file${fileCount == 1 ? "" : "s"}?"),
              SizedBox(height: scaleDimension(context, 12)),
              Wrap(
                spacing: scaleDimension(context, 8),
                runSpacing: scaleDimension(context, 8),
                children: tags
                    .map(
                      (ShelfTagEntry e) => Chip(
                        label: shelfTagChipLabel(e, semanticTypes),
                        backgroundColor: tagChipColor(context, e.name),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Apply"),
          ),
        ],
      );
    },
  );
}

Future<String?> _showRenameDisplayNameDialog(
  BuildContext context, {
  required String initialValue,
}) async {
  String draft = initialValue;
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text("Rename Display Name"),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Display name",
            border: OutlineInputBorder(),
          ),
          onChanged: (String value) {
            draft = value;
          },
          onFieldSubmitted: (_) {
            Navigator.of(context).pop(draft);
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(draft),
            child: const Text("Save"),
          ),
        ],
      );
    },
  );
}
