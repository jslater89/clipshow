import "package:flutter/material.dart";

import "package:obs_clipshow/src/features/osg/widgets/osg_semantic_type_icon_catalog.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/media/media_clip.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/workspace/workspace_media_paths.dart";

/// An [Autocomplete] that opens upward when it detects insufficient vertical
/// space below it (< 250 px to the bottom of the screen).
class AdaptiveAutocomplete<T extends Object> extends StatefulWidget {
  const AdaptiveAutocomplete({
    super.key,
    required this.optionsBuilder,
    required this.onSelected,
    required this.fieldViewBuilder,
  });

  final AutocompleteOptionsBuilder<T> optionsBuilder;
  final AutocompleteOnSelected<T> onSelected;
  final AutocompleteFieldViewBuilder fieldViewBuilder;

  @override
  State<AdaptiveAutocomplete<T>> createState() =>
      _AdaptiveAutocompleteState<T>();
}

class _AdaptiveAutocompleteState<T extends Object>
    extends State<AdaptiveAutocomplete<T>> {
  final GlobalKey _wrapperKey = GlobalKey();
  OptionsViewOpenDirection _direction = OptionsViewOpenDirection.down;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateDirection());
  }

  void _updateDirection() {
    if (!mounted) return;
    final RenderObject? ro = _wrapperKey.currentContext?.findRenderObject();
    if (ro is RenderBox) {
      final double widgetBottom =
          ro.localToGlobal(Offset.zero).dy + ro.size.height;
      final double screenHeight = MediaQuery.of(context).size.height;
      final OptionsViewOpenDirection next = (screenHeight - widgetBottom) < 150
          ? OptionsViewOpenDirection.up
          : OptionsViewOpenDirection.down;
      if (next != _direction) setState(() => _direction = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _wrapperKey,
      child: Autocomplete<T>(
        optionsBuilder: widget.optionsBuilder,
        onSelected: widget.onSelected,
        fieldViewBuilder: widget.fieldViewBuilder,
        optionsViewOpenDirection: _direction,
      ),
    );
  }
}

List<ShelfTagEntry> sortShelfTagEntries(List<ShelfTagEntry> tags) {
  final List<ShelfTagEntry> list = List<ShelfTagEntry>.from(tags);
  list.sort(
    (ShelfTagEntry a, ShelfTagEntry b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
  return list;
}

List<String> sortTags(List<String> tags) {
  tags.sort((String a, String b) {
    final bool aSystem = isSystemTag(a);
    final bool bSystem = isSystemTag(b);
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

bool isSystemTag(String tag) =>
    tag == "Master" || tag == "Clip" || tag == "Tag Set";

Color? tagChipColor(BuildContext context, String tag) {
  if (!isSystemTag(tag)) {
    return null;
  }
  final Color base = Theme.of(context).colorScheme.surfaceContainerHighest;
  return base.withValues(alpha: 0.5);
}

/// Chip label for a saved-tag / capture-queue entry (optional semantic icon).
Widget shelfTagChipLabel(ShelfTagEntry e, List<TagSemanticType> semanticTypes) {
  int? cp;
  final int? sid = e.semanticTypeId;
  if (sid != null) {
    for (final TagSemanticType t in semanticTypes) {
      if (t.id == sid) {
        cp = t.iconCodePoint;
        break;
      }
    }
  }
  if (cp == null) {
    return Text(e.name);
  }
  return Text.rich(
    TextSpan(
      children: <InlineSpan>[
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(osgMaterialIconFromCodePoint(cp), size: 16),
        ),
        TextSpan(text: " ${e.name}"),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// Chip label: optional Material icon when the tag has a semantic type with an icon.
Widget mediaTagAttachmentChipLabel(MediaTagAttachment a) {
  final int? cp = a.semanticTypeIconCodePoint;
  if (cp == null) {
    return Text(a.tagName);
  }
  return Text.rich(
    TextSpan(
      children: <InlineSpan>[
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(osgMaterialIconFromCodePoint(cp), size: 16),
        ),
        TextSpan(text: " ${a.tagName}"),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

String clipRangeLabel(MediaClip clip) {
  final int start = clip.inMs;
  final int? end = clip.outMs;
  if (end == null) {
    return "${formatMs(start)} - End";
  }
  return "${formatMs(start)} - ${formatMs(end)}";
}

/// Prompts for a single-line name (e.g. creating/renaming a tag set).
///
/// Owns its [TextEditingController] inside a dedicated [StatefulWidget] so
/// disposal is tied to that widget leaving the tree (i.e. after the dialog's
/// exit transition finishes, including the framework's built-in Escape
/// dismissal) rather than to the caller's `await showDialog(...)` returning.
Future<String?> showNamePromptDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) {
      return _NamePromptDialog(title: title, initialValue: initialValue);
    },
  );
}

class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({required this.title, required this.initialValue});

  final String title;
  final String initialValue;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: "Name",
          border: OutlineInputBorder(),
        ),
        onSubmitted: (String value) =>
            Navigator.of(context).pop(value.trim()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text("Save"),
        ),
      ],
    );
  }
}

String formatMs(int value) {
  final Duration duration = Duration(milliseconds: value);
  final int minutes = duration.inMinutes;
  final int seconds = duration.inSeconds % 60;
  return "${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
}

/// Builds video-playout context for [item]. [item] must be a master or clip;
/// tag sets have no backing video and are driven by OSG Mode instead.
PlayoutClip toPlayoutClip(
  MediaListItem item, {
  required String workspaceRoot,
  int? initialOffsetMs,
  OsgPresetVisibility? osgPresetVisibleInitial,
  int semanticTagSnapshotVersion = 0,
  Set<int> semanticTypeIdsOnMedia = const <int>{},
}) {
  assert(
    item.type != MediaListItemType.tagSet,
    "toPlayoutClip cannot be called with a tag set; tag sets have no video.",
  );
  final String absolute = WorkspaceMediaPaths.absoluteMasterPath(
    workspaceRoot,
    item.filePath,
  );
  if (item.type == MediaListItemType.master) {
    final int startTimeMs = 0;
    final int? initialPositionMs = initialOffsetMs == null
        ? null
        : initialOffsetMs < 0
        ? 0
        : initialOffsetMs;
    final PlayoutClip clip = PlayoutClip(
      filePath: absolute,
      startTimeMs: startTimeMs,
      endTimeMs: null,
      initialPositionMs: initialPositionMs,
      mediaType: MediaListItemType.master,
      mediaId: item.id,
      osgPresetVisibleInitial: osgPresetVisibleInitial,
      semanticTagSnapshotVersion: semanticTagSnapshotVersion,
      semanticTypeIdsOnMedia: semanticTypeIdsOnMedia,
      annotationsText: item.annotations ?? "",
    );
    return clip;
  }
  final int clipInMs = item.clip!.inMs;
  final int? clipOutMs = item.clip!.outMs;
  final int startTimeMs = clipInMs;
  final int? initialPositionMs;
  if (initialOffsetMs == null || initialOffsetMs < clipInMs) {
    initialPositionMs = clipInMs;
  } else if (clipOutMs != null && initialOffsetMs > clipOutMs) {
    initialPositionMs = clipOutMs;
  } else {
    initialPositionMs = initialOffsetMs;
  }
  final PlayoutClip clip = PlayoutClip(
    filePath: absolute,
    startTimeMs: startTimeMs,
    endTimeMs: clipOutMs,
    initialPositionMs: initialPositionMs,
    mediaType: MediaListItemType.clip,
    mediaId: item.id,
    osgPresetVisibleInitial: osgPresetVisibleInitial,
    semanticTagSnapshotVersion: semanticTagSnapshotVersion,
    semanticTypeIdsOnMedia: semanticTypeIdsOnMedia,
    annotationsText: item.annotations ?? "",
  );
  return clip;
}
