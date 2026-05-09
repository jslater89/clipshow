import "package:logging/logging.dart";
import "package:obs_websocket/obs_websocket.dart";

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
