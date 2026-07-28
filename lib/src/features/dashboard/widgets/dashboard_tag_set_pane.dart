import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_osg_preset_hotkeys_layer.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_tag_panel.dart";
import "package:obs_clipshow/src/features/osg_mode/osg_mode_session.dart";
import "package:obs_clipshow/src/features/playout/osg_playout_layer.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/media/tag_set.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/widgets/transient_hud_banner.dart";

/// Right-side content for the dashboard's "Tag Sets" tab. Splits the
/// workspace-global OSG Mode quick slots (which tag set is bound to each of
/// hotkeys 1-5) from the per-tag-set OSG preview and tag/annotation editing
/// for whichever tag set is currently selected in the file list, so global
/// and per-item settings no longer share one cramped card.
class DashboardTagSetPane extends StatelessWidget {
  const DashboardTagSetPane({
    super.key,
    required this.onEnterOsgMode,
    required this.onPreviewFocusRequested,
    required this.previewFocusNode,
  });

  final void Function(OsgModeSession session) onEnterOsgMode;
  final VoidCallback onPreviewFocusRequested;
  final FocusNode previewFocusNode;

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final String? workspaceRoot = viewModel.workspacePath;
    final MediaListItem? selectedItem = viewModel.selectedItem;
    final TagSet? selectedTagSet =
        selectedItem != null && selectedItem.type == MediaListItemType.tagSet
        ? selectedItem.tagSet
        : null;
    final double gap12 = scaleDimension(context, 12);

    return DashboardOsgPresetHotkeysLayer(
      focusNode: previewFocusNode,
      autofocus: true,
      onOsgPresetSlotToggle: viewModel.togglePreviewOsgPresetSlot,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _QuickSlotsCard(onEnterOsgMode: onEnterOsgMode),
          SizedBox(height: gap12),
          Expanded(
            child: selectedTagSet == null || workspaceRoot == null
                ? const Card(
                    child: Center(child: Text("Select or create a tag set.")),
                  )
                : Column(
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: TagSetPreviewCard(
                          tagSet: selectedTagSet,
                          workspaceRoot: workspaceRoot,
                          previewFocusNode: previewFocusNode,
                          onEnterOsgMode: onEnterOsgMode,
                        ),
                      ),
                      SizedBox(height: gap12),
                      Expanded(
                        flex: 2,
                        child: DashboardTagPanel(
                          onPreviewFocusRequested: onPreviewFocusRequested,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Global (not per-tag-set) card showing all five OSG Mode quick slots and
/// the primary "Enter OSG Mode" action.
class _QuickSlotsCard extends StatelessWidget {
  const _QuickSlotsCard({required this.onEnterOsgMode});

  final void Function(OsgModeSession session) onEnterOsgMode;

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final double pad12 = scaleDimension(context, 12);
    final double gap8 = scaleDimension(context, 8);
    final double gap12 = scaleDimension(context, 12);
    final double slotWidth = scaleDimension(context, 200);
    final OsgModeSession? initialSession = viewModel.canEnterOsgMode
        ? viewModel.buildInitialOsgModeSession()
        : null;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(pad12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              "Quick Slots",
              style: Theme.of(context).textTheme.labelLarge,
            ),
            SizedBox(width: gap12),
            Expanded(
              child: Wrap(
                spacing: gap8,
                runSpacing: gap8,
                children: <Widget>[
                  for (int i = 0; i < 5; i++)
                    SizedBox(
                      width: slotWidth,
                      child: _QuickSlotPicker(
                        slotLabel: "${i + 1}",
                        selectedTagSetId: viewModel.osgModeQuickSlotTagSetIds[i],
                        onChanged: (int? tagSetId) => unawaited(
                          viewModel.setOsgModeQuickSlotTagSetId(i, tagSetId),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: gap12),
            FilledButton.icon(
              onPressed: initialSession == null
                  ? null
                  : () => onEnterOsgMode(initialSession),
              icon: const Icon(Icons.fullscreen),
              label: const Text("Enter OSG Mode"),
            ),
          ],
        ),
      ),
    );
  }
}

/// Type-to-filter picker for one OSG Mode quick slot. Mirrors the Add Tag
/// autocomplete pattern: suggestions filter by substring of tag set name;
/// selecting assigns the slot, clearing empties it.
class _QuickSlotPicker extends StatefulWidget {
  const _QuickSlotPicker({
    required this.slotLabel,
    required this.selectedTagSetId,
    required this.onChanged,
  });

  final String slotLabel;
  final int? selectedTagSetId;
  final ValueChanged<int?> onChanged;

  @override
  State<_QuickSlotPicker> createState() => _QuickSlotPickerState();
}

class _QuickSlotPickerState extends State<_QuickSlotPicker> {
  TextEditingController? _controller;
  FocusNode? _focusNode;
  bool _handledAutocompleteSelection = false;

  String? _selectedName(DashboardViewModel viewModel) {
    final int? id = widget.selectedTagSetId;
    if (id == null) {
      return null;
    }
    for (final TagSet tagSet in viewModel.tagSets) {
      if (tagSet.id == id) {
        return tagSet.name;
      }
    }
    return null;
  }

  void _syncControllerText(DashboardViewModel viewModel) {
    final TextEditingController? controller = _controller;
    final FocusNode? focusNode = _focusNode;
    if (controller == null) {
      return;
    }
    if (focusNode != null && focusNode.hasFocus) {
      return;
    }
    final String display = _selectedName(viewModel) ?? "";
    if (controller.text != display) {
      controller.text = display;
    }
  }

  void _assignFromText(DashboardViewModel viewModel, String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      widget.onChanged(null);
      _controller?.clear();
      return;
    }
    final int? id = viewModel.tagSetIdForName(trimmed);
    if (id == null) {
      _syncControllerText(viewModel);
      return;
    }
    String canonicalName = trimmed;
    for (final TagSet tagSet in viewModel.tagSets) {
      if (tagSet.id == id) {
        canonicalName = tagSet.name;
        break;
      }
    }
    widget.onChanged(id);
    _controller?.text = canonicalName;
  }

  @override
  void didUpdateWidget(covariant _QuickSlotPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTagSetId != widget.selectedTagSetId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _syncControllerText(context.read<DashboardViewModel>());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final String? selectedName = _selectedName(viewModel);
    final double clearIconSize = scaleDimension(context, 16);

    return Row(
      children: <Widget>[
        SizedBox(width: scaleDimension(context, 20), child: Text(widget.slotLabel)),
        Expanded(
          child: AdaptiveAutocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              return viewModel.tagSetNameSuggestionsFor(textEditingValue.text);
            },
            onSelected: (String value) {
              _handledAutocompleteSelection = true;
              _assignFromText(viewModel, value);
            },
            fieldViewBuilder:
                (
                  BuildContext context,
                  TextEditingController textEditingController,
                  FocusNode focusNode,
                  VoidCallback onFieldSubmitted,
                ) {
                  _controller = textEditingController;
                  _focusNode = focusNode;
                  _syncControllerText(viewModel);
                  return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: "Empty",
                      border: const OutlineInputBorder(),
                      suffixIcon: selectedName == null
                          ? null
                          : IconButton(
                              tooltip: "Clear Slot",
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(
                                minWidth: scaleDimension(context, 28),
                                minHeight: scaleDimension(context, 28),
                              ),
                              icon: Icon(Icons.clear, size: clearIconSize),
                              onPressed: () {
                                widget.onChanged(null);
                                textEditingController.clear();
                              },
                            ),
                      suffixIconConstraints: selectedName == null
                          ? null
                          : BoxConstraints(
                              minWidth: scaleDimension(context, 28),
                              minHeight: scaleDimension(context, 28),
                            ),
                    ),
                    onSubmitted: (_) {
                      onFieldSubmitted();
                      if (_handledAutocompleteSelection) {
                        _handledAutocompleteSelection = false;
                        return;
                      }
                      _assignFromText(viewModel, textEditingController.text);
                    },
                  );
                },
          ),
        ),
      ],
    );
  }
}

/// Preview for a selected bare tag set: an OSG-only render (no video) plus
/// the tag set's own housekeeping actions. Tag/annotation editing itself
/// lives in [DashboardTagPanel], shared with masters and clips.
class TagSetPreviewCard extends StatefulWidget {
  const TagSetPreviewCard({
    super.key,
    required this.tagSet,
    required this.workspaceRoot,
    required this.previewFocusNode,
    required this.onEnterOsgMode,
  });

  final TagSet tagSet;
  final String workspaceRoot;
  final FocusNode previewFocusNode;
  final void Function(OsgModeSession session) onEnterOsgMode;

  @override
  State<TagSetPreviewCard> createState() => _TagSetPreviewCardState();
}

class _TagSetPreviewCardState extends State<TagSetPreviewCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.previewFocusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TagSetPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tagSet.id != widget.tagSet.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.previewFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final TagSet tagSet = widget.tagSet;
    final String workspaceRoot = widget.workspaceRoot;
    final MediaListItem item = MediaListItem.tagSet(tagSet);
    final double pad12 = scaleDimension(context, 12);
    final double gap12 = scaleDimension(context, 12);
    final double gap8 = scaleDimension(context, 8);
    final double radius8 = scaleDimension(context, 8);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(pad12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    tagSet.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: "Rename Tag Set",
                  onPressed: () async {
                    final String? name = await showNamePromptDialog(
                      context,
                      title: "Rename Tag Set",
                      initialValue: tagSet.name,
                    );
                    if (name == null || name.trim().isEmpty) {
                      return;
                    }
                    await viewModel.renameTagSet(tagSet, name.trim());
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: "Delete Tag Set",
                  onPressed: () async {
                    final bool confirmed = await _confirmDeleteTagSet(context);
                    if (!confirmed) {
                      return;
                    }
                    await viewModel.deleteTagSet(tagSet);
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            SizedBox(height: gap12),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.previewFocusNode.requestFocus(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius8),
                  child: Container(
                    color: Colors.black,
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints c) {
                      // Letterbox/pillarbox to the real playout canvas aspect
                      // ratio so presets (authored against that canvas) don't
                      // stretch or clip when this card's own box is a very
                      // different shape (e.g. near-square or ultra-wide).
                      final PlayoutOutputSize outputSize =
                          viewModel.playoutOutputSize;
                      final double aspect = outputSize.isValid
                          ? outputSize.aspectRatio
                          : 16 / 9;
                      double w = c.maxWidth;
                      double h = w / aspect;
                      if (h > c.maxHeight) {
                        h = c.maxHeight;
                        w = h * aspect;
                      }
                      return Center(
                        child: SizedBox(
                          width: w,
                          height: h,
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              OsgPlayoutLayer(
                                key: ValueKey<String>(
                                  "${item.stableKey}-${viewModel.semanticTagSnapshotForItem(item)}",
                                ),
                                mediaType: MediaListItemType.tagSet,
                                mediaId: tagSet.id,
                                annotationsText: tagSet.annotations ?? "",
                                semanticTagSnapshotVersion:
                                    viewModel.semanticTagSnapshotForItem(item),
                                config: viewModel.osgWorkspaceConfig,
                                workspaceRoot: workspaceRoot,
                                resolveSemantic: (int semanticTypeId) =>
                                    viewModel.resolveSemanticTagTextForMedia(
                                      mediaType: MediaListItemType.tagSet,
                                      mediaId: tagSet.id,
                                      semanticTypeId: semanticTypeId,
                                    ),
                                visible: viewModel.previewOsgPresetVisibility,
                              ),
                              if (viewModel.previewOsgRequirementFlashToken >
                                  0)
                                Positioned(
                                  left: pad12,
                                  top: pad12,
                                  child: TransientHudBanner(
                                    key: ValueKey<int>(
                                      viewModel.previewOsgRequirementFlashToken,
                                    ),
                                    text: viewModel
                                        .previewOsgRequirementFlashText,
                                    onDismissed: () => viewModel
                                        .clearPreviewOsgRequirementFlash(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
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
                Text("OSG", style: Theme.of(context).textTheme.labelLarge),
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
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteTagSet(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text("Delete Tag Set"),
          content: const Text("Remove this tag set and its tag attachments?"),
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
}
