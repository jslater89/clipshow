/// Workspace-relative ignored-folder matching (prefix semantics).
class IgnoredPathUtils {
  IgnoredPathUtils._();

  static String normalizeRelative(String raw) {
    String path = raw.trim().replaceAll("\\", "/");
    while (path.startsWith("/")) {
      path = path.substring(1);
    }
    if (path.endsWith("/") && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  /// True when [relativePath] equals [ignoredFolder] or is nested under it.
  static bool isPathCoveredByIgnoredFolder({
    required String relativePath,
    required String ignoredFolder,
  }) {
    final String path = normalizeRelative(relativePath);
    final String ignored = normalizeRelative(ignoredFolder);
    if (path.isEmpty || ignored.isEmpty) {
      return false;
    }
    if (path == ignored) {
      return true;
    }
    return path.startsWith("$ignored/");
  }

  /// True when [relativePath] is covered by any entry in [ignoredFolders].
  static bool isPathCoveredByAnyIgnoredFolder({
    required String relativePath,
    required Iterable<String> ignoredFolders,
  }) {
    for (final String ignored in ignoredFolders) {
      if (isPathCoveredByIgnoredFolder(
        relativePath: relativePath,
        ignoredFolder: ignored,
      )) {
        return true;
      }
    }
    return false;
  }
}
