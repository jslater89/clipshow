import 'package:obs_clipshow/src/media/master_media_file.dart';
import 'package:obs_clipshow/src/media/media_clip.dart';
import 'package:obs_clipshow/src/media/tag_set.dart';

enum MediaListItemType { master, clip, tagSet }

class MediaListItem {
  const MediaListItem.master(this.master)
    : clip = null,
      tagSet = null,
      type = MediaListItemType.master;

  const MediaListItem.clip(this.clip)
    : master = null,
      tagSet = null,
      type = MediaListItemType.clip;

  const MediaListItem.tagSet(this.tagSet)
    : master = null,
      clip = null,
      type = MediaListItemType.tagSet;

  final MediaListItemType type;
  final MasterMediaFile? master;
  final MediaClip? clip;
  final TagSet? tagSet;

  int get id => switch (type) {
    MediaListItemType.master => master!.id,
    MediaListItemType.clip => clip!.id,
    MediaListItemType.tagSet => tagSet!.id,
  };

  String get stableKey => switch (type) {
    MediaListItemType.master => "m:$id",
    MediaListItemType.clip => "c:$id",
    MediaListItemType.tagSet => "ts:$id",
  };

  /// Workspace-relative file path. Empty for tag sets, which have no backing
  /// video file.
  String get filePath => switch (type) {
    MediaListItemType.master => master!.filePath,
    MediaListItemType.clip => clip!.filePath,
    MediaListItemType.tagSet => "",
  };

  String get fileName => switch (type) {
    MediaListItemType.master => master!.fileName,
    MediaListItemType.clip => clip!.fileName,
    MediaListItemType.tagSet => tagSet!.name,
  };

  String get displayName {
    if (type == MediaListItemType.tagSet) {
      return tagSet!.name;
    }
    final String? override = type == MediaListItemType.master
        ? master!.displayNameOverride
        : clip!.displayNameOverride;
    if (override == null || override.trim().isEmpty) {
      return fileName;
    }
    return override;
  }

  MediaIssue get mediaIssue =>
      type == MediaListItemType.master ? master!.mediaIssue : MediaIssue.none;

  String? get mediaIssueDetail =>
      type == MediaListItemType.master ? master!.mediaIssueDetail : null;

  String? get annotations => switch (type) {
    MediaListItemType.master => master!.annotations,
    MediaListItemType.clip => clip!.annotations,
    MediaListItemType.tagSet => tagSet!.annotations,
  };
}
