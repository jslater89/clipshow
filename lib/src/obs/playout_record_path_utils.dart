import "package:path/path.dart" as p;

import "package:obs_clipshow/src/workspace/workspace_settings.dart";

/// Resolves workspace-relative playout record paths and validates layout.
class PlayoutRecordPathUtils {
  PlayoutRecordPathUtils._();

  static String normalizedStagingDir({
    required String workspaceAbsolute,
    required PlayoutRecordPathsSettings settings,
  }) {
    final String rel = settings.stagingRelativeDir.trim().isEmpty
        ? PlayoutRecordPathsSettings.defaultStagingRelativeDir
        : settings.stagingRelativeDir.trim();
    return p.normalize(p.join(workspaceAbsolute, rel.replaceAll("\\", "/")));
  }

  static String normalizedOutputDir({
    required String workspaceAbsolute,
    required PlayoutRecordPathsSettings settings,
  }) {
    final String rel = settings.outputRelativeDir.trim().isEmpty
        ? PlayoutRecordPathsSettings.defaultOutputRelativeDir
        : settings.outputRelativeDir.trim();
    return p.normalize(p.join(workspaceAbsolute, rel.replaceAll("\\", "/")));
  }

  /// True when [outputDir] is the staging dir or nested inside it.
  static bool isOutputInsideStagingTree({
    required String stagingDirAbsolute,
    required String outputDirAbsolute,
  }) {
    final String staging = p.normalize(stagingDirAbsolute);
    final String out = p.normalize(outputDirAbsolute);
    if (out == staging) {
      return true;
    }
    final String sep = p.separator;
    final String prefix = staging.endsWith(sep) ? staging : "$staging$sep";
    return out.startsWith(prefix);
  }
}
