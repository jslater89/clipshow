import "dart:io";

import "package:path/path.dart" as p;

/// Opens the system file manager for [absolutePath].
///
/// When [absolutePath] is a file, selects/highlights it where the platform
/// supports that (macOS Finder `-R`, Windows Explorer `/select`); on Linux
/// opens the containing folder. When it is a directory, opens that folder.
Future<void> revealFileInFolder(String absolutePath) async {
  final String path = p.normalize(p.absolute(absolutePath));
  final File file = File(path);
  final Directory directory = Directory(path);
  final bool isFile = await file.exists();
  final bool isDirectory = await directory.exists();
  if (!isFile && !isDirectory) {
    throw FileSystemException("Path not found", path);
  }

  if (Platform.isMacOS) {
    final List<String> args = isFile
        ? <String>["-R", path]
        : <String>[path];
    final ProcessResult r = await Process.run("/usr/bin/open", args);
    if (r.exitCode != 0) {
      throw StateError("Could not reveal path in Finder.");
    }
    return;
  }

  if (Platform.isWindows) {
    final List<String> args = isFile
        ? <String>["/select,", path]
        : <String>[path];
    final ProcessResult r = await Process.run("explorer.exe", args);
    if (r.exitCode != 0) {
      throw StateError("Could not reveal path in Explorer.");
    }
    return;
  }

  if (Platform.isLinux) {
    final String toOpen = isFile ? p.dirname(path) : path;
    final ProcessResult r = await Process.run("xdg-open", <String>[toOpen]);
    if (r.exitCode == 0) {
      return;
    }
    throw StateError("Could not open folder with xdg-open.");
  }

  throw UnsupportedError(
    "Reveal in folder is not implemented for ${Platform.operatingSystem}.",
  );
}
