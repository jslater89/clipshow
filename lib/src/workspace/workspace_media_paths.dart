import "package:path/path.dart" as p;

/// Helpers for [MasterMediaFile.filePath]: workspace-root-relative paths stored in SQLite.
///
/// Stored form uses forward slashes and no leading slash so the same DB row is valid
/// when the workspace folder moves between disks or machines.
class WorkspaceMediaPaths {
  WorkspaceMediaPaths._();

  /// Normalizes a workspace-relative path for storage or comparison (POSIX-style).
  static String normalizeStored(String relativePath) {
    return relativePath.replaceAll("\\", "/");
  }

  /// Workspace-relative path for persisting in [master_media_files.file_path].
  static String storedMasterPath(String workspaceRoot, String absolutePath) {
    final String ws = p.normalize(p.absolute(workspaceRoot));
    final String abs = p.normalize(p.absolute(absolutePath));
    final String rel = p.relative(abs, from: ws);
    if (rel.startsWith("..")) {
      throw ArgumentError(
        "Video path is outside the workspace: $absolutePath",
      );
    }
    return normalizeStored(rel);
  }

  /// Resolves a stored master path (or legacy absolute path) for filesystem IO.
  static String absoluteMasterPath(String workspaceRoot, String storedPath) {
    final String trimmed = storedPath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError("Stored master path is empty");
    }
    if (p.isAbsolute(trimmed)) {
      return p.normalize(trimmed);
    }
    final String ws = p.normalize(p.absolute(workspaceRoot));
    final String withNativeSeparators = trimmed.replaceAll("/", p.separator);
    return p.normalize(p.join(ws, withNativeSeparators));
  }

  /// Subtitle / export: path relative to workspace for UI lists.
  static String displayRelativeToWorkspace(
    String workspaceRoot,
    String storedOrLegacyAbsolutePath,
  ) {
    final String trimmed = storedOrLegacyAbsolutePath.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    if (p.isAbsolute(trimmed)) {
      final String ws = p.normalize(p.absolute(workspaceRoot));
      return normalizeStored(p.relative(p.normalize(trimmed), from: ws));
    }
    return normalizeStored(trimmed);
  }
}
