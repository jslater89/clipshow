import "dart:io";

import "package:path/path.dart" as p;

/// In-workspace folder used when system trash is unavailable.
class WorkspaceTrash {
  WorkspaceTrash._();

  static const String relativeFolder = ".obs_clipshow_trash";
}

/// Moves a file into [WorkspaceTrash.relativeFolder] under [workspaceRoot], with
/// a numeric suffix if the basename already exists. Uses rename, or copy+delete
/// if rename fails (e.g. cross-device).
Future<void> moveFileToWorkspaceTrash({
  required String absoluteSourcePath,
  required String workspaceRoot,
}) async {
  final String sourcePath = p.normalize(p.absolute(absoluteSourcePath));
  final File sourceFile = File(sourcePath);
  if (!await sourceFile.exists()) {
    throw FileSystemException("File not found", sourcePath);
  }
  final String trashDirPath = p.join(
    p.normalize(workspaceRoot),
    WorkspaceTrash.relativeFolder,
  );
  await Directory(trashDirPath).create(recursive: true);
  final String baseName = p.basename(sourcePath);
  String destPath = p.join(trashDirPath, baseName);
  int suffix = 0;
  while (await File(destPath).exists()) {
    suffix++;
    final String name = p.basenameWithoutExtension(baseName);
    final String ext = p.extension(baseName);
    destPath = p.join(trashDirPath, "${name}_$suffix$ext");
  }
  try {
    await sourceFile.rename(destPath);
  } on FileSystemException {
    await sourceFile.copy(destPath);
    await sourceFile.delete();
  }
}
