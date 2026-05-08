import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";

class DashboardTagPanel extends StatefulWidget {
  const DashboardTagPanel({super.key});

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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text("Tags"),
              const SizedBox(height: 12),
              if (selectedItem == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
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
                          backgroundColor: tagChipColor(context, tag),
                          onDeleted: () => unawaited(
                            viewModel.removeTagFromSelectedMedia(tag),
                          ),
                          onPressed: () => viewModel.toggleTagFilter(tag),
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
                    const SizedBox(width: 8),
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
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                Row(
                  children: <Widget>[
                    const Text("Saved Tags"),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: viewModel.savedTags.isEmpty
                            ? null
                            : () => unawaited(
                                viewModel.applyAllSavedTagsToSelectedMedia(),
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
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Autocomplete<String>(
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
                    const SizedBox(width: 8),
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
