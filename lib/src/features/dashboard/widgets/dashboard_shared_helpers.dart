import "package:flutter/material.dart";

import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/media/media_clip.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
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
      final OptionsViewOpenDirection next =
          (screenHeight - widgetBottom) < 150
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

bool isSystemTag(String tag) => tag == "Master" || tag == "Clip";

Color? tagChipColor(BuildContext context, String tag) {
  if (!isSystemTag(tag)) {
    return null;
  }
  final Color base = Theme.of(context).colorScheme.surfaceContainerHighest;
  return base.withValues(alpha: 0.5);
}

String clipRangeLabel(MediaClip clip) {
  final int start = clip.inMs;
  final int? end = clip.outMs;
  if (end == null) {
    return "${formatMs(start)} - End";
  }
  return "${formatMs(start)} - ${formatMs(end)}";
}

String formatMs(int value) {
  final Duration duration = Duration(milliseconds: value);
  final int minutes = duration.inMinutes;
  final int seconds = duration.inSeconds % 60;
  return "${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
}

PlayoutClip toPlayoutClip(
  MediaListItem item, {
  required String workspaceRoot,
  int? initialOffsetMs,
}) {
  final String absolute = WorkspaceMediaPaths.absoluteMasterPath(
    workspaceRoot,
    item.filePath,
  );
  if (item.type == MediaListItemType.master) {
    final int startTimeMs = initialOffsetMs == null
        ? 0
        : initialOffsetMs < 0
        ? 0
        : initialOffsetMs;
    return PlayoutClip(
      filePath: absolute,
      startTimeMs: startTimeMs,
      endTimeMs: null,
    );
  }
  final int clipInMs = item.clip!.inMs;
  final int? clipOutMs = item.clip!.outMs;
  final int startTimeMs;
  if (initialOffsetMs == null || initialOffsetMs < clipInMs) {
    startTimeMs = clipInMs;
  } else if (clipOutMs != null && initialOffsetMs > clipOutMs) {
    startTimeMs = clipOutMs;
  } else {
    startTimeMs = initialOffsetMs;
  }
  return PlayoutClip(
    filePath: absolute,
    startTimeMs: startTimeMs,
    endTimeMs: clipOutMs,
  );
}
