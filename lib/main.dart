import "dart:io";

import "package:flutter/material.dart";
import "package:fvp/fvp.dart" as fvp;
import "package:logging/logging.dart";
import "package:window_manager/window_manager.dart";

import "package:obs_clipshow/src/app/app.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  fvp.registerWith(
    options: <String, Object>{
      "platforms": <String>["windows", "linux"],
      if (Platform.isLinux)
        "video.decoders": <String>["VAAPI", "VAAPI:vpp=1", "FFmpeg:threads=0", "dav1d"],
    },
  );
  _configureLogging();
  runApp(const ObsClipshowApp());
}

void _configureLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord record) {
    // Keep format simple for terminal and IDE logs.
    debugPrint(
      "${record.time.toIso8601String()} [${record.level.name}] "
      "${record.loggerName}: ${record.message}",
    );
  });
}
