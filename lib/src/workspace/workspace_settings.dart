import "dart:io";
import "dart:ui";

import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

/// Defaults and bounds for directory-scan ffprobe batching and thumbnail [ffmpeg] jobs.
abstract final class IngestionConcurrencyDefaults {
  static const int probeMin = 1;
  static const int probeMax = 32;
  static const int thumbnailMin = 1;
  static const int thumbnailMax = 16;

  static const int probeDefault = 8;
  static const int thumbnailDefault = 3;

  static int clampProbe(int value) =>
      value < probeMin
          ? probeMin
          : (value > probeMax ? probeMax : value);

  static int clampThumbnail(int value) =>
      value < thumbnailMin
          ? thumbnailMin
          : (value > thumbnailMax ? thumbnailMax : value);
}

/// Bounds for clip volume (0.0–1.0). Nudge step is the increment used by the
/// Up/Down volume hotkeys.
abstract final class PlaybackVolumeDefaults {
  static const double min = 0.0;
  static const double max = 1.0;
  static const double step = 0.1;
  static const double defaultVolume = 1.0;

  static double clamp(double value) {
    if (value.isNaN) {
      return defaultVolume;
    }
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }
}

enum DecoderPlatform {
  linux, windows, macos;

  static DecoderPlatform get() {
    if (Platform.isLinux) {
      return DecoderPlatform.linux;
    }
    else if (Platform.isWindows) {
      return DecoderPlatform.windows;
    }
    else if (Platform.isMacOS) {
      return DecoderPlatform.macos;
    }
    else {
      throw UnimplementedError("Unsupported platform: ${Platform.operatingSystem}");
    }
  }
}

enum DecoderProfile {
  // multiplatform decoders
  vaapi,
  vaapiVpp,
  vdpau,
  ffmpegThreads0,
  dav1d,
  cuda,
  nvdec,

  // windows only
  mft,
  d3d12,
  d3d11,

  // macos only
  mdkVT,
  videoToolbox;

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
      case DecoderProfile.cuda:
        return "CUDA (nvidia only)";
      case DecoderProfile.nvdec:
        return "NVDEC (nvidia only)";
      case DecoderProfile.videoToolbox:
        return "VideoToolbox";
      case DecoderProfile.mft:
        return "MFT";
      case DecoderProfile.d3d12:
        return "D3D12";
      case DecoderProfile.d3d11:
        return "D3D11";
      case DecoderProfile.mdkVT:
        return "VT";
    }
  }

  String get fvpArgument {
    switch (this) {
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
      case DecoderProfile.cuda:
        return "CUDA";
      case DecoderProfile.nvdec:
        return "NVDEC";
      case DecoderProfile.videoToolbox:
        return "VideoToolbox";
      case DecoderProfile.mft:
        return "MFT";
      case DecoderProfile.d3d12:
        return "D3D12";
      case DecoderProfile.d3d11:
        return "D3D11";
      case DecoderProfile.mdkVT:
        return "VT";
    }
  }

  List<DecoderPlatform> get supportedPlatforms {
    switch (this) {
      case DecoderProfile.vaapi:
        return <DecoderPlatform>[DecoderPlatform.linux, DecoderPlatform.windows];
      case DecoderProfile.vaapiVpp:
        return <DecoderPlatform>[DecoderPlatform.linux, DecoderPlatform.windows];
      case DecoderProfile.vdpau:
        return <DecoderPlatform>[DecoderPlatform.linux];
      case DecoderProfile.ffmpegThreads0:
        return <DecoderPlatform>[DecoderPlatform.linux, DecoderPlatform.windows, DecoderPlatform.macos];
      case DecoderProfile.dav1d:
        return <DecoderPlatform>[DecoderPlatform.linux, DecoderPlatform.windows, DecoderPlatform.macos];
      case DecoderProfile.mft:
        return <DecoderPlatform>[DecoderPlatform.windows];
      case DecoderProfile.cuda:
        return <DecoderPlatform>[DecoderPlatform.linux, DecoderPlatform.windows];
      case DecoderProfile.nvdec:
        return <DecoderPlatform>[DecoderPlatform.linux, DecoderPlatform.windows];
      case DecoderProfile.videoToolbox:
        return <DecoderPlatform>[DecoderPlatform.macos];
      case DecoderProfile.d3d12:
        return <DecoderPlatform>[DecoderPlatform.windows];
      case DecoderProfile.d3d11:
        return <DecoderPlatform>[DecoderPlatform.windows];
      case DecoderProfile.mdkVT:
        return <DecoderPlatform>[DecoderPlatform.macos];
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
  const DecoderConfig({required this.enabledProfiles, required this.platform});

  final DecoderPlatform platform;

  factory DecoderConfig.platformFallback() {
    if (Platform.isLinux) {
      return const DecoderConfig.fallbackLinux();
    }
    else if (Platform.isWindows) {
      return const DecoderConfig.fallbackWindows();
    }
    else if (Platform.isMacOS) {
      return const DecoderConfig.fallbackMacOS();
    }
    else {
      throw UnimplementedError("Unsupported platform: ${Platform.operatingSystem}");
    }
  }

   const DecoderConfig.fallbackLinux()
    : platform = DecoderPlatform.linux, enabledProfiles = const <DecoderProfile>[
      DecoderProfile.vaapi,
      DecoderProfile.vaapiVpp,
      DecoderProfile.ffmpegThreads0,
      DecoderProfile.dav1d,
    ];

  const DecoderConfig.fallbackWindows()
    : platform = DecoderPlatform.windows, enabledProfiles = const <DecoderProfile>[
      DecoderProfile.mft,
      DecoderProfile.d3d12,
      DecoderProfile.d3d11,
      DecoderProfile.ffmpegThreads0,
    ];

  const DecoderConfig.fallbackMacOS()
    : platform = DecoderPlatform.macos, enabledProfiles = const <DecoderProfile>[
      DecoderProfile.mdkVT,
      DecoderProfile.videoToolbox,
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
    required this.osgScene,
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
      osgScene: "OSG Scene",
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

  /// Empty string disables OSG Mode scene switching.
  final String osgScene;
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

/// OBS record-during-playout staging and copy destination (workspace-relative).
class PlayoutRecordPathsSettings {
  static const String defaultStagingRelativeDir = "recordings/export";
  static const String defaultOutputRelativeDir = "export";

  const PlayoutRecordPathsSettings({
    required this.stagingRelativeDir,
    required this.outputRelativeDir,
  });

  factory PlayoutRecordPathsSettings.fallback() {
    return const PlayoutRecordPathsSettings(
      stagingRelativeDir: defaultStagingRelativeDir,
      outputRelativeDir: defaultOutputRelativeDir,
    );
  }

  /// Where OBS writes the in-progress file during Record playout.
  final String stagingRelativeDir;

  /// Finished file is copied here on exit (not ingested when ignored).
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
    required this.playoutRecordPathsSettings,
    required this.pauseIngestScanDuringPreview,
    required this.ingestProbeConcurrency,
    required this.ingestThumbnailConcurrency,
    required this.playoutOutputSize,
    required this.osgWorkspaceConfig,
    required this.tagSemanticTypes,
    required this.osgBakeRecipes,
    required this.defaultClipVolume,
    required this.osgModeKeyColorArgb,
  });

  final TelestratorDefaults telestratorDefaults;
  final DecoderConfig decoderConfig;
  final MdkLogVerbosity mdkLogVerbosity;
  final FvpLogVerbosity fvpLogVerbosity;
  final ObsSceneSwitchConfig? obsSceneSwitchConfig;
  final List<WebhookSceneSwitchConfig> webhookSceneSwitchConfigs;
  final List<String> ignoredFolders;
  final CapturePathsSettings capturePathsSettings;
  final PlayoutRecordPathsSettings playoutRecordPathsSettings;

  /// When true (default), background ingest scanning pauses while a clip plays
  /// in the dashboard preview. Full-screen playout always pauses ingest regardless.
  final bool pauseIngestScanDuringPreview;

  /// Parallel ffprobe + stat passes per batch during the initial workspace directory scan.
  final int ingestProbeConcurrency;

  /// Parallel thumbnail [ffmpeg] jobs (each file may still run one probe if duration unknown).
  final int ingestThumbnailConcurrency;

  /// Logical canvas for playout window sizing and OSG normalized coordinates.
  final PlayoutOutputSize playoutOutputSize;

  /// Three on-screen graphic presets (indices 0, 1, 2 map to hotkeys later).
  final OsgWorkspaceConfig osgWorkspaceConfig;

  /// Workspace-defined semantic tag types (for OSG slots and typed media tags).
  final List<TagSemanticType> tagSemanticTypes;

  /// Named OSG timing recipes for bake export.
  final List<OsgBakeRecipe> osgBakeRecipes;

  /// Initial clip volume (0.0–1.0) used when the workspace loads, before the
  /// user adjusts via the volume hotkeys. Session adjustments are not persisted.
  final double defaultClipVolume;

  /// Opaque fill behind OSG Mode graphics for OBS Color Key window capture.
  final int osgModeKeyColorArgb;
}
