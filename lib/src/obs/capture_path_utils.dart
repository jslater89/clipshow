import "package:path/path.dart" as p;

import "package:obs_clipshow/src/workspace/workspace_settings.dart";

/// Resolves workspace-relative capture paths and validates staging vs output layout.
class CapturePathUtils {
  CapturePathUtils._();

  static String normalizedRecordingDir({
    required String workspaceAbsolute,
    required CapturePathsSettings settings,
  }) {
    final String rel = settings.recordingRelativeDir.trim().isEmpty
        ? CapturePathsSettings.defaultRecordingRelativeDir
        : settings.recordingRelativeDir.trim();
    return p.normalize(p.join(workspaceAbsolute, rel.replaceAll("\\", "/")));
  }

  static String normalizedOutputDir({
    required String workspaceAbsolute,
    required CapturePathsSettings settings,
  }) {
    final String rel = settings.outputRelativeDir.trim();
    if (rel.isEmpty) {
      return p.normalize(workspaceAbsolute);
    }
    return p.normalize(p.join(workspaceAbsolute, rel.replaceAll("\\", "/")));
  }

  /// True when [outputDir] is the recording dir or nested inside it (invalid for ingest-after-copy).
  static bool isOutputInsideRecordingTree({
    required String recordingDirAbsolute,
    required String outputDirAbsolute,
  }) {
    final String rec = p.normalize(recordingDirAbsolute);
    final String out = p.normalize(outputDirAbsolute);
    if (out == rec) {
      return true;
    }
    final String sep = p.separator;
    final String prefix = rec.endsWith(sep) ? rec : "$rec$sep";
    return out.startsWith(prefix);
  }
}
