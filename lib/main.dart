import "dart:io";

import "package:flutter/material.dart";
import "package:fvp/fvp.dart" as fvp;
import "package:logging/logging.dart";
import "package:window_manager/window_manager.dart";

import "package:obs_clipshow/src/app/app.dart";
import "package:obs_clipshow/src/data/app_database.dart";
import "package:obs_clipshow/src/media/workspace.dart";
import "package:obs_clipshow/src/media_player/clip_media_player_factory.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/workspace/workspace_preferences.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // fvp uses Logger("fvp") at Level.FINE only; cap it here (no registerWith hook).
  hierarchicalLoggingEnabled = true;
  await windowManager.ensureInitialized();
  final _StartupVideoSettings startupSettings =
      await _loadStartupVideoSettings();
  // Playback-engine selector is parked; always use FVP for now. Media Kit
  // adapter remains in-tree for later compositor A/B.
  ClipMediaPlayerFactory.configure(
    PlayerBackend.fvp,
    textureCap: startupSettings.playoutOutputSize,
  );
  final PlayoutOutputSize textureCap = startupSettings.playoutOutputSize;
  fvp.registerWith(
    options: <String, Object>{
      "platforms": <String>["windows", "linux", "macos"],
      "video.decoders": startupSettings.decoderOptions,
      // Cap native GL textures to the playout canvas so 4K+ sources do not
      // allocate full-frame surfaces for Manage preview / playout (fvp scales
      // with aspect preserved when fitMaxSize is true).
      "maxWidth": textureCap.width,
      "maxHeight": textureCap.height,
      "fitMaxSize": true,
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
  final pathExists = workspacePath != null && workspacePath.isNotEmpty && await Directory(workspacePath).exists();
  if (!pathExists) {
    final fallbackSettings = DecoderConfig.platformFallback();
    return _StartupVideoSettings(
      decoderOptions: fallbackSettings.enabledProfiles.map((DecoderProfile profile) => profile.fvpArgument).toList(),
      logVerbosity: MdkLogVerbosity.warning,
      fvpLogVerbosity: FvpLogVerbosity.warning,
      playoutOutputSize: PlayoutOutputSize.fallback,
      playerBackend: PlayerBackend.fvp,
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
    List<DecoderProfile> decoderProfiles = (decoderListRaw ?? "")
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
    if(decoderProfiles.isEmpty) {
      decoderProfiles = <DecoderProfile>[profile];
    }

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
    final List<Map<String, Object?>> widthRows = await database.query(
      "workspace_settings",
      columns: <String>["value"],
      where: "key = ?",
      whereArgs: <Object?>["playout.outputWidth"],
      limit: 1,
    );
    final List<Map<String, Object?>> heightRows = await database.query(
      "workspace_settings",
      columns: <String>["value"],
      where: "key = ?",
      whereArgs: <Object?>["playout.outputHeight"],
      limit: 1,
    );
    final int? width = widthRows.isEmpty
        ? null
        : int.tryParse(widthRows.single["value"]! as String);
    final int? height = heightRows.isEmpty
        ? null
        : int.tryParse(heightRows.single["value"]! as String);
    final PlayoutOutputSize playoutOutputSize =
        width != null && height != null && width > 0 && height > 0
        ? PlayoutOutputSize(width: width, height: height)
        : PlayoutOutputSize.fallback;
    final List<Map<String, Object?>> backendRows = await database.query(
      "workspace_settings",
      columns: <String>["value"],
      where: "key = ?",
      whereArgs: <Object?>["player.backend"],
      limit: 1,
    );
    final String backendName = backendRows.isEmpty
        ? PlayerBackend.fvp.name
        : backendRows.single["value"]! as String;
    final PlayerBackend playerBackend = PlayerBackend.values.firstWhere(
      (PlayerBackend item) => item.name == backendName,
      orElse: () => PlayerBackend.fvp,
    );
    return _StartupVideoSettings(
      decoderOptions: decoderProfiles.map((DecoderProfile profile) => profile.fvpArgument).toList(),
      logVerbosity: verbosity,
      fvpLogVerbosity: fvpVerbosity,
      playoutOutputSize: playoutOutputSize,
      playerBackend: playerBackend,
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

class _StartupVideoSettings {
  const _StartupVideoSettings({
    required this.decoderOptions,
    required this.logVerbosity,
    required this.fvpLogVerbosity,
    required this.playoutOutputSize,
    required this.playerBackend,
  });

  final List<String> decoderOptions;
  final MdkLogVerbosity logVerbosity;
  final FvpLogVerbosity fvpLogVerbosity;
  final PlayoutOutputSize playoutOutputSize;
  final PlayerBackend playerBackend;
}
