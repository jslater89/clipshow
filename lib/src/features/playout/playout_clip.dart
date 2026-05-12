import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

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

  /// When non-null, playout starts with these OSG preset visibilities (hotkeys
  /// 6 through 0). Otherwise all presets start hidden.
  final OsgPresetVisibility? osgPresetVisibleInitial;

  /// Bumps when tag rows for this media change in a way that affects OSG
  /// semantic text (e.g. semantic type or tag value). Preview uses this so
  /// [OsgPlayoutLayer] refetches without changing [mediaId].
  final int semanticTagSnapshotVersion;

  /// Distinct semantic type ids present on tags attached to this media row.
  final Set<int> semanticTypeIdsOnMedia;

  /// Per-item notes (multiline). Used by OSG slots with annotation text source.
  final String annotationsText;
}
