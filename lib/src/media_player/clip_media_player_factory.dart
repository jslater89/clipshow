import "package:obs_clipshow/src/media_player/clip_media_player.dart";
import "package:obs_clipshow/src/media_player/fvp_clip_media_player.dart";
import "package:obs_clipshow/src/media_player/media_kit_clip_media_player.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

/// Creates [ClipMediaPlayer] instances for the backend chosen at process start.
class ClipMediaPlayerFactory {
  ClipMediaPlayerFactory._();

  static PlayerBackend _backend = PlayerBackend.fvp;
  static PlayoutOutputSize _textureCap = PlayoutOutputSize.fallback;

  static PlayerBackend get backend => _backend;

  static PlayoutOutputSize get textureCap => _textureCap;

  /// Called once from [main] after workspace startup settings are loaded.
  static void configure(
    PlayerBackend backend, {
    PlayoutOutputSize? textureCap,
  }) {
    _backend = backend;
    if (textureCap != null) {
      _textureCap = textureCap;
    }
  }

  static ClipMediaPlayer create() {
    switch (_backend) {
      case PlayerBackend.fvp:
        return FvpClipMediaPlayer();
      case PlayerBackend.mediaKit:
        return MediaKitClipMediaPlayer(textureCap: _textureCap);
    }
  }
}
