import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/data/media_repository.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
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

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final MediaListItem? selectedItem = viewModel.selectedItem;
    final List<String> selectedTags = selectedItem == null
        ? <String>[]
        : sortTags(viewModel.tagsForItem(selectedItem).toList());
    final bool selectedHasUserTags =
        selectedTags.any((String t) => !isSystemTag(t));
    final double pad12 = scaleDimension(context, 12);
    final double gap12 = scaleDimension(context, 12);
    final double gap10 = scaleDimension(context, 10);
    final double gap8 = scaleDimension(context, 8);
    final double emptyStateVertPad = scaleDimension(context, 24);
    final double editIconSize = scaleDimension(context, 16);
    final double fieldMaxWidth = scaleDimension(context, 400);

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
                    child: TextButton.icon(
                      onPressed: () =>
                          viewModel.selectMasterForClip(selectedItem),
                      icon: const Icon(Icons.link),
                      label: const Text("Go to Source Master"),
                    ),
                  ),
                if (selectedItem.type == MediaListItemType.master &&
                    viewModel.clipCountForMaster(selectedItem.master!.id) > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => viewModel.toggleClipsOfMasterFilter(
                        selectedItem.master!.id,
                      ),
                      icon: Icon(
                        viewModel.clipsOfMasterFilterMediaId ==
                                selectedItem.master!.id
                            ? Icons.filter_alt
                            : Icons.filter_list_outlined,
                      ),
                      label: Text(
                        viewModel.clipsOfMasterFilterMediaId ==
                                selectedItem.master!.id
                            ? "Clear Clip Filter"
                            : "Show Clips",
                      ),
                    ),
                  ),
                if (selectedItem.type == MediaListItemType.clip ||
                    (selectedItem.type == MediaListItemType.master &&
                        viewModel.clipCountForMaster(
                              selectedItem.master!.id,
                            ) >
                            0))
                  SizedBox(height: gap10),
                Wrap(
                  spacing: gap8,
                  runSpacing: gap8,
                  children: selectedTags.map((String tag) {
                    final bool isSystemTag =
                        tag == MediaRepository.masterTag ||
                        tag == MediaRepository.clipTag;
                    return InputChip(
                      label: Text(tag),
                      backgroundColor: tagChipColor(context, tag),
                      onDeleted: isSystemTag
                          ? null
                          : () => unawaited(
                              viewModel.removeTagFromSelectedMedia(tag),
                            ),
                      onPressed: () => viewModel.toggleTagFilter(tag),
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
                  children: viewModel.savedTags
                      .map(
                        (String tag) => InputChip(
                          label: Text(tag),
                          onDeleted: () =>
                              unawaited(viewModel.removeSavedTag(tag)),
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
                                  await _showApplySavedTagsToManyConfirmDialog(
                                    context,
                                    fileCount: count,
                                    tags: viewModel.savedTags,
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

Future<bool?> _showApplySavedTagsToManyConfirmDialog(
  BuildContext context, {
  required int fileCount,
  required List<String> tags,
}) async {
  final List<String> sorted = sortTags(List<String>.from(tags));
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text("Apply saved tags"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Add tags to $fileCount file${fileCount == 1 ? "" : "s"}?",
              ),
              SizedBox(height: scaleDimension(context, 12)),
              Wrap(
                spacing: scaleDimension(context, 8),
                runSpacing: scaleDimension(context, 8),
                children: sorted
                    .map(
                      (String tag) => Chip(
                        label: Text(tag),
                        backgroundColor: tagChipColor(context, tag),
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
