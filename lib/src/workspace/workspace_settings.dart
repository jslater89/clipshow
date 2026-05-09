import "dart:ui";

enum DecoderProfile {
  vaapi,
  vaapiVpp,
  vdpau,
  ffmpegThreads0,
  dav1d;

  String get label {
    switch (this) {
      case DecoderProfile.vaapi:
        return "VAAPI";
      case DecoderProfile.vaapiVpp:
        return "VAAPI:vpp=1";
      case DecoderProfile.vdpau:
        return "VDPAU (nvidia only)";
      case DecoderProfile.ffmpegThreads0:
        return "FFmpeg:threads=0";
      case DecoderProfile.dav1d:
        return "dav1d";
    }
  }
}

enum MdkLogVerbosity { off, error, warning, info, debug, all }

/// Minimum level for `package:logging` [Logger] `"fvp"` (Dart-side plugin traces).
enum FvpLogVerbosity { off, error, warning, info, debug, all }

class TelestratorDefaults {
  const TelestratorDefaults({
    required this.colorOneArgb,
    required this.colorTwoArgb,
    required this.colorThreeArgb,
    required this.brushSize,
    required this.enabledByDefault,
  });

  factory TelestratorDefaults.fallback() {
    return const TelestratorDefaults(
      colorOneArgb: 0xFFFFCC00,
      colorTwoArgb: 0xFFFF3B30,
      colorThreeArgb: 0xFF34C759,
      brushSize: 6,
      enabledByDefault: false,
    );
  }

  final int colorOneArgb;
  final int colorTwoArgb;
  final int colorThreeArgb;
  final double brushSize;
  final bool enabledByDefault;

  Color get colorOne => Color(colorOneArgb);
  Color get colorTwo => Color(colorTwoArgb);
  Color get colorThree => Color(colorThreeArgb);
}

class DecoderConfig {
  const DecoderConfig({required this.enabledProfiles});

  const DecoderConfig.fallbackLinux()
    : enabledProfiles = const <DecoderProfile>[
      DecoderProfile.vaapi,
      DecoderProfile.vaapiVpp,
      DecoderProfile.ffmpegThreads0,
      DecoderProfile.dav1d,
    ];

  final List<DecoderProfile> enabledProfiles;
}

class ObsSceneSwitchConfig {
  const ObsSceneSwitchConfig({
    required this.enabled,
    required this.serverAddress,
    required this.port,
    required this.password,
    required this.videoScene,
    required this.faceScene,
    required this.captureScene,
  });

  factory ObsSceneSwitchConfig.fallback() {
    return const ObsSceneSwitchConfig(
      enabled: false,
      serverAddress: "127.0.0.1",
      port: 4455,
      password: "",
      videoScene: "Video Scene",
      faceScene: "Face Scene",
      captureScene: "",
    );
  }

  final bool enabled;
  final String serverAddress;
  final int port;
  final String password;
  final String videoScene;
  final String faceScene;

  /// Empty string disables switching before capture.
  final String captureScene;
}

/// Paths relative to workspace root (POSIX-style segments). Used for OBS staging copy workflow.
class CapturePathsSettings {
  static const String defaultRecordingRelativeDir = "recordings";

  const CapturePathsSettings({
    required this.recordingRelativeDir,
    required this.outputRelativeDir,
  });

  factory CapturePathsSettings.fallback() {
    return const CapturePathsSettings(
      recordingRelativeDir: defaultRecordingRelativeDir,
      outputRelativeDir: "",
    );
  }

  /// Where OBS writes growing files (ignored by ingest when under workspace).
  final String recordingRelativeDir;

  /// Empty = copy finished recordings to workspace root for ingest.
  final String outputRelativeDir;
}

enum WebhookMethod { get, post }

enum WebhookPostBodyType { form, json }

class WebhookSceneSwitchConfig {
  const WebhookSceneSwitchConfig({
    required this.id,
    required this.name,
    required this.enabled,
    required this.url,
    required this.method,
    required this.getQueryParamName,
    required this.postBodyType,
    required this.sceneKey,
  });

  final int id;
  final String name;
  final bool enabled;
  final String url;
  final WebhookMethod method;
  final String getQueryParamName;
  final WebhookPostBodyType postBodyType;
  final String sceneKey;
}

class WorkspaceSettingsBundle {
  const WorkspaceSettingsBundle({
    required this.telestratorDefaults,
    required this.decoderConfig,
    required this.mdkLogVerbosity,
    required this.fvpLogVerbosity,
    required this.obsSceneSwitchConfig,
    required this.webhookSceneSwitchConfigs,
    required this.ignoredFolders,
    required this.capturePathsSettings,
  });

  final TelestratorDefaults telestratorDefaults;
  final DecoderConfig decoderConfig;
  final MdkLogVerbosity mdkLogVerbosity;
  final FvpLogVerbosity fvpLogVerbosity;
  final ObsSceneSwitchConfig? obsSceneSwitchConfig;
  final List<WebhookSceneSwitchConfig> webhookSceneSwitchConfigs;
  final List<String> ignoredFolders;
  final CapturePathsSettings capturePathsSettings;
}
