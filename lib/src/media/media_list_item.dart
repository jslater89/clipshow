import "master_media_file.dart";
import "media_clip.dart";

enum MediaListItemType { master, clip }

class MediaListItem {
  const MediaListItem.master(this.master)
    : clip = null,
      type = MediaListItemType.master;

  const MediaListItem.clip(this.clip)
    : master = null,
      type = MediaListItemType.clip;

  final MediaListItemType type;
  final MasterMediaFile? master;
  final MediaClip? clip;

  int get id => type == MediaListItemType.master ? master!.id : clip!.id;

  String get stableKey => type == MediaListItemType.master ? "m:$id" : "c:$id";

  String get filePath =>
      type == MediaListItemType.master ? master!.filePath : clip!.filePath;

  String get fileName =>
      type == MediaListItemType.master ? master!.fileName : clip!.fileName;

  MediaIssue get mediaIssue =>
      type == MediaListItemType.master ? master!.mediaIssue : MediaIssue.none;

  String? get mediaIssueDetail =>
      type == MediaListItemType.master ? master!.mediaIssueDetail : null;
}
