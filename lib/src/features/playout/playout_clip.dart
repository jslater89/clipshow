import "package:obs_clipshow/src/media/media_list_item.dart";

class PlayoutClip {
  PlayoutClip({
    required this.filePath,
    required this.startTimeMs,
    required this.endTimeMs,
    this.initialPositionMs,
    required this.mediaType,
    required this.mediaId,
    this.osgPresetVisibleInitial,
    this.semanticTagSnapshotVersion = 0,
    this.semanticTypeIdsOnMedia = const <int>{},
    this.annotationsText = "",
  });

  final String filePath;
  final int startTimeMs;
  final int? endTimeMs;
  final int? initialPositionMs;

  /// Media row used to resolve OSG semantic tag text (master or clip).
  final MediaListItemType mediaType;
  final int mediaId;

  /// When non-null and length is 3, playout starts with these OSG preset
  /// visibilities (hotkeys 8 / 9 / 0). Otherwise all presets start hidden.
  final List<bool>? osgPresetVisibleInitial;

  /// Bumps when tag rows for this media change in a way that affects OSG
  /// semantic text (e.g. semantic type or tag value). Preview uses this so
  /// [OsgPlayoutLayer] refetches without changing [mediaId].
  final int semanticTagSnapshotVersion;

  /// Distinct semantic type ids present on tags attached to this media row.
  final Set<int> semanticTypeIdsOnMedia;

  /// Per-item notes (multiline). Used by OSG slots with annotation text source.
  final String annotationsText;
}
