import "package:flutter/material.dart";

import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/media/media_clip.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";

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

PlayoutClip toPlayoutClip(MediaListItem item, {int? initialOffsetMs}) {
  if (item.type == MediaListItemType.master) {
    final int startTimeMs = initialOffsetMs == null ? 0 : initialOffsetMs < 0 ? 0 : initialOffsetMs;
    return PlayoutClip(
      filePath: item.filePath,
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
    filePath: item.filePath,
    startTimeMs: startTimeMs,
    endTimeMs: clipOutMs,
  );
}
