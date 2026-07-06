import "package:obs_clipshow/src/osg/osg_models.dart";

/// Runtime context for an OSG Mode session (no video).
class OsgModeSession {
  const OsgModeSession({
    required this.tagSetId,
    required this.tagSetName,
    required this.annotationsText,
    required this.semanticTypeIdsOnMedia,
    this.semanticTagSnapshotVersion = 0,
    this.osgPresetVisibleInitial,
  });

  final int tagSetId;
  final String tagSetName;
  final String annotationsText;
  final Set<int> semanticTypeIdsOnMedia;
  final int semanticTagSnapshotVersion;
  final OsgPresetVisibility? osgPresetVisibleInitial;
}
