import "dart:io";

import "package:path/path.dart" as p;

/// Opens the file manager for [absoluteFilePath] (selected on macOS/Windows;
/// containing folder via `xdg-open` on Linux).
Future<void> revealFileInFolder(String absoluteFilePath) async {
  final String path = p.normalize(p.absolute(absoluteFilePath));
  final File file = File(path);
  if (!await file.exists()) {
    throw FileSystemException("File not found", path);
  }

  if (Platform.isMacOS) {
    final ProcessResult r = await Process.run("/usr/bin/open", <String>[
      "-R",
      path,
    ]);
    if (r.exitCode != 0) {
      throw StateError("Could not reveal file in Finder.");
    }
    return;
  }

  if (Platform.isWindows) {
    final ProcessResult r = await Process.run("explorer.exe", <String>[
      "/select,",
      path,
    ]);
    if (r.exitCode != 0) {
      throw StateError("Could not reveal file in Explorer.");
    }
    return;
  }

  if (Platform.isLinux) {
    final String directory = p.dirname(path);
    final ProcessResult r = await Process.run("xdg-open", <String>[directory]);
    if (r.exitCode == 0) {
      return;
    }
    throw StateError("Could not open export folder with xdg-open.");
  }

  throw UnsupportedError(
    "Reveal in folder is not implemented for ${Platform.operatingSystem}.",
  );
}
