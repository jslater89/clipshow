import "package:flutter/material.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_tag_value_edit_dialog.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

List<MediaTagAttachment> sortMediaTagAttachments(List<MediaTagAttachment> raw) {
  final List<MediaTagAttachment> list = List<MediaTagAttachment>.from(raw);
  list.sort((MediaTagAttachment a, MediaTagAttachment b) {
    final bool aSys = a.tagName == "Master" || a.tagName == "Clip";
    final bool bSys = b.tagName == "Master" || b.tagName == "Clip";
    if (aSys && !bSys) {
      return -1;
    }
    if (!aSys && bSys) {
      return 1;
    }
    return a.tagName.toLowerCase().compareTo(b.tagName.toLowerCase());
  });
  return list;
}

RelativeRect _menuPosition(BuildContext context, Offset globalPosition) {
  final RenderBox overlay =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final Offset o = overlay.localToGlobal(Offset.zero);
  return RelativeRect.fromRect(
    Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
    Rect.fromLTWH(o.dx, o.dy, overlay.size.width, overlay.size.height),
  );
}

PopupMenuItem<String> _semanticTypeMenuRow({
  required BuildContext context,
  required TagSemanticType type,
  required bool selected,
  required String value,
}) {
  final Color checkColor = Theme.of(context).colorScheme.primary;
  return PopupMenuItem<String>(
    value: value,
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 24,
          child: selected
              ? Icon(Icons.check, size: 18, color: checkColor)
              : const SizedBox.shrink(),
        ),
        Expanded(child: Text(type.name)),
      ],
    ),
  );
}

Future<void> showMediaTagContextMenu({
  required BuildContext context,
  required DashboardViewModel viewModel,
  required MediaTagAttachment attachment,
  required Offset globalPosition,
}) async {
  final String? choice = await showMenu<String>(
    context: context,
    position: _menuPosition(context, globalPosition),
    items: <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: "edit",
        child: Text("Edit tag value…"),
      ),
      const PopupMenuDivider(),
      ...viewModel.tagSemanticTypes.map(
        (TagSemanticType t) => _semanticTypeMenuRow(
          context: context,
          type: t,
          selected: attachment.semanticTypeId == t.id,
          value: "type:${t.id}",
        ),
      ),
      const PopupMenuItem<String>(
        value: "clear_type",
        child: Text("Clear semantic type"),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: "bulk",
        child: Text(
          "Bulk assign semantic type for “${attachment.tagName}”…",
        ),
      ),
    ],
  );
  if (choice == null || !context.mounted) {
    return;
  }
  if (choice == "edit") {
    final String? next = await showTagValueEditDialog(
      context: context,
      viewModel: viewModel,
      initialTagText: attachment.tagName,
    );
    if (next == null || !context.mounted) {
      return;
    }
    await viewModel.swapTagValueOnMediaTag(
      mediaTagId: attachment.mediaTagId,
      newTagName: next,
    );
    return;
  }
  if (choice == "clear_type") {
    await viewModel.setMediaTagSemanticType(
      mediaTagId: attachment.mediaTagId,
      semanticTypeId: null,
    );
    return;
  }
  if (choice == "bulk") {
    await _showBulkSemanticDialog(
      context: context,
      viewModel: viewModel,
      tagId: attachment.tagId,
      tagName: attachment.tagName,
      initialSemanticTypeId: attachment.semanticTypeId,
    );
    return;
  }
  if (choice.startsWith("type:")) {
    final int? id = int.tryParse(choice.substring(5));
    if (id != null) {
      await viewModel.setMediaTagSemanticType(
        mediaTagId: attachment.mediaTagId,
        semanticTypeId: id,
      );
    }
  }
}

/// Right-click menu for a saved-tag or capture-queue chip.
Future<void> showShelfTagContextMenu({
  required BuildContext context,
  required DashboardViewModel viewModel,
  required ShelfTagEntry entry,
  required DashboardShelfTagMenuTarget target,
  required Offset globalPosition,
}) async {
  final String? choice = await showMenu<String>(
    context: context,
    position: _menuPosition(context, globalPosition),
    items: <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: "edit",
        child: Text("Edit tag value…"),
      ),
      const PopupMenuDivider(),
      ...viewModel.tagSemanticTypes.map(
        (TagSemanticType t) => _semanticTypeMenuRow(
          context: context,
          type: t,
          selected: entry.semanticTypeId == t.id,
          value: "type:${t.id}",
        ),
      ),
      const PopupMenuItem<String>(
        value: "clear_type",
        child: Text("Clear semantic type"),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: "bulk",
        child: Text(
          "Bulk assign semantic type for “${entry.name}”…",
        ),
      ),
    ],
  );
  if (choice == null || !context.mounted) {
    return;
  }
  if (choice == "edit") {
    final String? next = await showTagValueEditDialog(
      context: context,
      viewModel: viewModel,
      initialTagText: entry.name,
    );
    if (next == null || !context.mounted) {
      return;
    }
    if (next.isEmpty) {
      return;
    }
    if (target == DashboardShelfTagMenuTarget.saved) {
      await viewModel.renameSavedTagOnShelf(
        oldName: entry.name,
        newName: next,
      );
    } else {
      viewModel.renameCaptureTagEntry(
        oldName: entry.name,
        newName: next,
      );
    }
    return;
  }
  if (choice == "bulk") {
    final int? tagId = await viewModel.lookupTagIdForLibraryTagName(entry.name);
    if (!context.mounted) {
      return;
    }
    if (tagId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "No media in the library uses the tag “${entry.name}” yet.",
          ),
        ),
      );
      return;
    }
    await _showBulkSemanticDialog(
      context: context,
      viewModel: viewModel,
      tagId: tagId,
      tagName: entry.name,
      initialSemanticTypeId: entry.semanticTypeId,
    );
    return;
  }
  if (choice == "clear_type") {
    if (target == DashboardShelfTagMenuTarget.saved) {
      await viewModel.setSavedTagSemanticType(
        tagName: entry.name,
        semanticTypeId: null,
      );
    } else {
      viewModel.setCaptureTagSemanticType(
        tagName: entry.name,
        semanticTypeId: null,
      );
    }
    return;
  }
  if (choice.startsWith("type:")) {
    final int? id = int.tryParse(choice.substring(5));
    if (id == null) {
      return;
    }
    if (target == DashboardShelfTagMenuTarget.saved) {
      await viewModel.setSavedTagSemanticType(
        tagName: entry.name,
        semanticTypeId: id,
      );
    } else {
      viewModel.setCaptureTagSemanticType(
        tagName: entry.name,
        semanticTypeId: id,
      );
    }
  }
}

enum DashboardShelfTagMenuTarget { saved, capture }

Future<void> _showBulkSemanticDialog({
  required BuildContext context,
  required DashboardViewModel viewModel,
  required int tagId,
  required String tagName,
  int? initialSemanticTypeId,
}) async {
  if (viewModel.tagSemanticTypes.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Define semantic types in the OSG editor first."),
        ),
      );
    }
    return;
  }
  final List<TagSemanticType> types = viewModel.tagSemanticTypes;
  int selectedId = types.first.id;
  if (initialSemanticTypeId != null &&
      types.any((TagSemanticType t) => t.id == initialSemanticTypeId)) {
    selectedId = initialSemanticTypeId;
  }
  final int? picked = await showDialog<int>(
    context: context,
    builder: (BuildContext ctx) {
      return StatefulBuilder(
        builder: (BuildContext ctx2, void Function(void Function()) setLocal) {
          return AlertDialog(
            title: Text("Bulk assign for “$tagName”"),
            content: InputDecorator(
              decoration: const InputDecoration(
                labelText: "Semantic type",
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: selectedId,
                  items: types
                      .map(
                        (TagSemanticType t) => DropdownMenuItem<int>(
                          value: t.id,
                          child: Text(t.name),
                        ),
                      )
                      .toList(),
                  onChanged: (int? v) {
                    if (v != null) {
                      setLocal(() => selectedId = v);
                    }
                  },
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selectedId),
                child: const Text("Apply to all"),
              ),
            ],
          );
        },
      );
    },
  );
  if (picked != null && context.mounted) {
    await viewModel.bulkSetSemanticTypeForTagId(
      tagId: tagId,
      semanticTypeId: picked,
    );
  }
}
