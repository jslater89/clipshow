import "dart:io";

import "package:flutter/material.dart";
import "package:fvp/fvp.dart" as fvp;
import "package:logging/logging.dart";
import "package:window_manager/window_manager.dart";

import "package:obs_clipshow/src/app/app.dart";
import "package:obs_clipshow/src/data/app_database.dart";
import "package:obs_clipshow/src/media/workspace.dart";
import "package:obs_clipshow/src/workspace/workspace_preferences.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // fvp uses Logger("fvp") at Level.FINE only; cap it here (no registerWith hook).
  hierarchicalLoggingEnabled = true;
  await windowManager.ensureInitialized();
  final _StartupVideoSettings startupSettings =
      await _loadStartupVideoSettings();
  fvp.registerWith(
    options: <String, Object>{
      "platforms": <String>["windows", "linux"],
      if (Platform.isLinux)
        "video.decoders": <String>[startupSettings.decoderOption],
      // MDK player buffer: min ms when low + max ms cap (reduces PulseAudio underruns).
      "player": <String, String>{"buffer": "2000+60000"},
      // Applied after fvp's internal "log":"all"; overrides MDK global log level.
      "global": <String, Object>{
        "log": _mdkGlobalLogOption(startupSettings.logVerbosity),
      },
    },
  );
  _configureLogging(startupSettings.fvpLogVerbosity);
  runApp(const ObsClipshowApp());
}

void _configureLogging(FvpLogVerbosity fvpLogVerbosity) {
  Logger("fvp").level = _packageLoggingLevelForFvp(fvpLogVerbosity);
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord record) {
    // Keep format simple for terminal and IDE logs.
    debugPrint(
      "${record.time.toIso8601String()} [${record.level.name}] "
      "${record.loggerName}: ${record.message}",
    );
  });
}

Future<_StartupVideoSettings> _loadStartupVideoSettings() async {
  final WorkspacePreferences prefs = WorkspacePreferences();
  final String? workspacePath = await prefs.loadWorkspacePath();
  if (workspacePath == null || workspacePath.isEmpty) {
    return const _StartupVideoSettings(
      decoderOption: "VAAPI",
      logVerbosity: MdkLogVerbosity.warning,
      fvpLogVerbosity: FvpLogVerbosity.warning,
    );
  }
  final Workspace workspace = Workspace(rootPath: workspacePath);
  final AppDatabase appDatabase = AppDatabase();
  final database = await appDatabase.openForWorkspace(workspace);
  try {
    final List<Map<String, Object?>> decoderRows = await database.query(
      "workspace_settings",
      columns: <String>["value"],
      where: "key = ?",
      whereArgs: <Object?>["decoder.enabledProfiles"],
      limit: 1,
    );
    final String? decoderListRaw = decoderRows.isEmpty
        ? null
        : decoderRows.single["value"]! as String;
    final List<DecoderProfile> decoderProfiles = (decoderListRaw ?? "")
        .split(",")
        .map((String raw) => raw.trim())
        .where((String raw) => raw.isNotEmpty)
        .map(
          (String name) => DecoderProfile.values.firstWhere(
            (DecoderProfile item) => item.name == name,
            orElse: () => DecoderProfile.vaapi,
          ),
        )
        .toList();
    final List<Map<String, Object?>> legacyDecoderRows = await database.query(
      "workspace_settings",
      columns: <String>["value"],
      where: "key = ?",
      whereArgs: <Object?>["decoder.profile"],
      limit: 1,
    );
    final String decoderProfileName = legacyDecoderRows.isEmpty
        ? DecoderProfile.vaapi.name
        : legacyDecoderRows.single["value"]! as String;
    final DecoderProfile profile = DecoderProfile.values.firstWhere(
      (DecoderProfile item) => item.name == decoderProfileName,
      orElse: () => DecoderProfile.vaapi,
    );
    final List<Map<String, Object?>> logRows = await database.query(
      "workspace_settings",
      columns: <String>["value"],
      where: "key = ?",
      whereArgs: <Object?>["mdk.logVerbosity"],
      limit: 1,
    );
    final String logName = logRows.isEmpty
        ? MdkLogVerbosity.warning.name
        : logRows.single["value"]! as String;
    final MdkLogVerbosity verbosity = MdkLogVerbosity.values.firstWhere(
      (MdkLogVerbosity item) => item.name == logName,
      orElse: () => MdkLogVerbosity.warning,
    );
    final List<Map<String, Object?>> fvpLogRows = await database.query(
      "workspace_settings",
      columns: <String>["value"],
      where: "key = ?",
      whereArgs: <Object?>["fvp.logVerbosity"],
      limit: 1,
    );
    final String fvpLogName = fvpLogRows.isEmpty
        ? FvpLogVerbosity.warning.name
        : fvpLogRows.single["value"]! as String;
    final FvpLogVerbosity fvpVerbosity = FvpLogVerbosity.values.firstWhere(
      (FvpLogVerbosity item) => item.name == fvpLogName,
      orElse: () => FvpLogVerbosity.warning,
    );
    return _StartupVideoSettings(
      decoderOption: _decoderOptionForProfile(
        decoderProfiles.isEmpty ? profile : decoderProfiles.first,
      ),
      logVerbosity: verbosity,
      fvpLogVerbosity: fvpVerbosity,
    );
  } finally {
    await database.close();
  }
}

/// Maps [FvpLogVerbosity] to `package:logging` [Level] for [Logger] `"fvp"`.
Level _packageLoggingLevelForFvp(FvpLogVerbosity verbosity) {
  switch (verbosity) {
    case FvpLogVerbosity.off:
      return Level.OFF;
    case FvpLogVerbosity.error:
      return Level.SEVERE;
    case FvpLogVerbosity.warning:
      return Level.WARNING;
    case FvpLogVerbosity.info:
      return Level.INFO;
    case FvpLogVerbosity.debug:
      return Level.FINE;
    case FvpLogVerbosity.all:
      return Level.ALL;
  }
}

/// Values for MDK [SetGlobalOption("log", …)](https://github.com/wang-bin/mdk-sdk/wiki/Global-Options).
String _mdkGlobalLogOption(MdkLogVerbosity verbosity) {
  switch (verbosity) {
    case MdkLogVerbosity.off:
      return "Off";
    case MdkLogVerbosity.error:
      return "Error";
    case MdkLogVerbosity.warning:
      return "Warning";
    case MdkLogVerbosity.info:
      return "Info";
    case MdkLogVerbosity.debug:
      return "Debug";
    case MdkLogVerbosity.all:
      return "All";
  }
}

String _decoderOptionForProfile(DecoderProfile profile) {
  switch (profile) {
    case DecoderProfile.vaapi:
      return "VAAPI";
    case DecoderProfile.vaapiVpp:
      return "VAAPI:vpp=1";
    case DecoderProfile.vdpau:
      return "VDPAU";
    case DecoderProfile.ffmpegThreads0:
      return "FFmpeg:threads=0";
    case DecoderProfile.dav1d:
      return "dav1d";
  }
}

class _StartupVideoSettings {
  const _StartupVideoSettings({
    required this.decoderOption,
    required this.logVerbosity,
    required this.fvpLogVerbosity,
  });

  final String decoderOption;
  final MdkLogVerbosity logVerbosity;
  final FvpLogVerbosity fvpLogVerbosity;
}
