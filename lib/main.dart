import "package:flutter/material.dart";
import "package:logging/logging.dart";

import "src/app/app.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
