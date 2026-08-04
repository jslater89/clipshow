import "package:logging/logging.dart";
import "package:obs_websocket/obs_websocket.dart";

/// Scene item resolved for OSG overlay automation.
class OsgOverlayTarget {
  const OsgOverlayTarget({
    required this.sceneName,
    required this.sceneItemId,
    required this.sourceName,
  });

  final String sceneName;
  final int sceneItemId;
  final String sourceName;
}

/// Thrown when the configured OSG overlay source is missing from the target
/// scene (or OBS refuses the lookup).
class OsgOverlaySourceNotFoundException implements Exception {
  OsgOverlaySourceNotFoundException({
    required this.sourceName,
    required this.sceneName,
    this.searchedCurrentProgram = false,
    this.cause,
  });

  final String sourceName;
  final String sceneName;
  final bool searchedCurrentProgram;
  final Object? cause;

  @override
  String toString() {
    final String sceneClause = searchedCurrentProgram
        ? "the current OBS program scene \"$sceneName\""
        : "OBS scene \"$sceneName\"";
    final String base =
        "OSG overlay source \"$sourceName\" was not found in $sceneClause.";
    if (cause == null) {
      return base;
    }
    return "$base ($cause)";
  }
}

class ObsService {
  ObsService({
    this.url = "ws://127.0.0.1:4455",
    this.password,
    this.videoSceneName = "Video Scene",
    this.faceSceneName = "Face Scene",
  });

  final String url;
  final String? password;
  final String videoSceneName;
  final String faceSceneName;
  final Logger _logger = Logger("ObsService");
  ObsWebSocket? _client;

  bool get isConnected => _client != null;

  Future<void> ensureConnected() async {
    if (_client != null) {
      return;
    }
    _logger.info("Connecting to OBS at $url");
    _client = await ObsWebSocket.connect(url, password: password);
    _logger.info("Connected to OBS websocket.");
  }

  Future<void> switchToVideoScene() async {
    final ObsWebSocket client = await _requireClient();
    _logger.info("Switching OBS program scene to $videoSceneName");
    await client.scenes.setCurrentProgramScene(videoSceneName);
  }

  Future<void> switchToFaceScene() async {
    final ObsWebSocket client = await _requireClient();
    _logger.info("Switching OBS program scene to $faceSceneName");
    await client.scenes.setCurrentProgramScene(faceSceneName);
  }

  /// Resolves [sourceName] as a scene item on [sceneName].
  ///
  /// Throws [OsgOverlaySourceNotFoundException] when the item is missing.
  Future<OsgOverlayTarget> resolveOsgOverlay({
    required String sceneName,
    required String sourceName,
    bool searchedCurrentProgram = false,
  }) async {
    final String trimmedSource = sourceName.trim();
    final String trimmedScene = sceneName.trim();
    if (trimmedSource.isEmpty) {
      throw ArgumentError("OSG overlay source name must not be empty.");
    }
    if (trimmedScene.isEmpty) {
      throw ArgumentError("OSG overlay scene name must not be empty.");
    }
    final ObsWebSocket client = await _requireClient();
    try {
      final int sceneItemId = await client.sceneItems.getSceneItemId(
        sceneName: trimmedScene,
        sourceName: trimmedSource,
      );
      _logger.info(
        "Resolved OSG overlay \"$trimmedSource\" in scene "
        "\"$trimmedScene\" (item $sceneItemId).",
      );
      return OsgOverlayTarget(
        sceneName: trimmedScene,
        sceneItemId: sceneItemId,
        sourceName: trimmedSource,
      );
    } catch (error) {
      throw OsgOverlaySourceNotFoundException(
        sourceName: trimmedSource,
        sceneName: trimmedScene,
        searchedCurrentProgram: searchedCurrentProgram,
        cause: error,
      );
    }
  }

  /// Resolves [sourceName] as a scene item on the current program scene.
  ///
  /// Throws [OsgOverlaySourceNotFoundException] when the item is missing.
  Future<OsgOverlayTarget> resolveOsgOverlayInCurrentProgram(
    String sourceName,
  ) async {
    final ObsWebSocket client = await _requireClient();
    final String programScene = await client.scenes.getCurrentProgramScene();
    return resolveOsgOverlay(
      sceneName: programScene,
      sourceName: sourceName,
      searchedCurrentProgram: true,
    );
  }

  /// Resolves the OSG overlay using [osgOverlayScene] when set, otherwise the
  /// current program scene.
  Future<OsgOverlayTarget> resolveOsgOverlayForConfig({
    required String osgOverlayScene,
    required String osgOverlaySource,
  }) async {
    final String homeScene = osgOverlayScene.trim();
    if (homeScene.isNotEmpty) {
      return resolveOsgOverlay(
        sceneName: homeScene,
        sourceName: osgOverlaySource,
      );
    }
    return resolveOsgOverlayInCurrentProgram(osgOverlaySource);
  }

  Future<void> setSceneItemEnabled({
    required String sceneName,
    required int sceneItemId,
    required bool enabled,
  }) async {
    final ObsWebSocket client = await _requireClient();
    _logger.info(
      "SetSceneItemEnabled scene=\"$sceneName\" id=$sceneItemId "
      "enabled=$enabled",
    );
    // SceneItemEnableStateChanged is not exported by obs_websocket; send the
    // OBS WebSocket 5 request payload directly.
    await client.sendRequest(
      Request(
        "SetSceneItemEnabled",
        requestData: <String, Object?>{
          "sceneName": sceneName,
          "sceneItemId": sceneItemId,
          "sceneItemEnabled": enabled,
        },
      ),
    );
  }

  Future<void> setOsgOverlayEnabled(
    OsgOverlayTarget target, {
    required bool enabled,
  }) async {
    await setSceneItemEnabled(
      sceneName: target.sceneName,
      sceneItemId: target.sceneItemId,
      enabled: enabled,
    );
  }

  Future<void> close() async {
    if (_client == null) {
      return;
    }
    await _client!.close();
    _client = null;
    _logger.info("OBS websocket closed.");
  }

  Future<ObsWebSocket> _requireClient() async {
    await ensureConnected();
    return _client!;
  }
}
