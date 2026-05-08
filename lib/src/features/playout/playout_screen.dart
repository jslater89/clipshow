import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";

import "clip_player_view.dart";
import "playout_clip.dart";
import "playout_hotkeys_layer.dart";

class PlayoutScreen extends StatefulWidget {
  const PlayoutScreen({
    super.key,
    required this.clip,
    required this.onExitRequested,
  });

  final PlayoutClip clip;
  final Future<void> Function() onExitRequested;

  @override
  State<PlayoutScreen> createState() => _PlayoutScreenState();
}

class _PlayoutScreenState extends State<PlayoutScreen> {
  final Logger _logger = Logger("PlayoutScreen");
  final ClipPlayerController _playerController = ClipPlayerController();
  bool _isExiting = false;
  bool _showEscapeHint = true;
  bool _showHelpOverlay = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showEscapeHint = false;
      });
    });
    _logger.info("Playout started for ${widget.clip.filePath}");
  }

  Future<void> _requestExit() async {
    if (_isExiting) {
      return;
    }
    _isExiting = true;
    await widget.onExitRequested();
  }

  void _toggleHelpOverlay() {
    setState(() {
      _showHelpOverlay = !_showHelpOverlay;
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PlayoutHotkeysLayer(
        controller: _playerController,
        onExitRequested: _requestExit,
        onHelpToggleRequested: _toggleHelpOverlay,
        child: ClipPlayerView(
          controller: _playerController,
          filePath: widget.clip.filePath,
          startTimeMs: widget.clip.startTimeMs,
          endTimeMs: widget.clip.endTimeMs,
          autoPlay: true,
          overlay: Stack(
            children: <Widget>[
              if (_showEscapeHint && !_showHelpOverlay)
                const Positioned(
                  right: 16,
                  bottom: 16,
                  child: Text(
                    "Press Escape to return",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              if (_showHelpOverlay) const _PlayoutHelpOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayoutHelpOverlay extends StatelessWidget {
  const _PlayoutHelpOverlay();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            color: colorScheme.surface.withValues(alpha: 0.95),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text("Playout Hotkeys", style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _hotkeySection("Playback", <String, String>{"Space": "Play/Pause"}),
                  const SizedBox(height: 10),
                  _hotkeySection("Seek", <String, String>{
                    "Left / Right": "Seek 5s",
                    "Shift + Left / Right": "Seek 1s",
                    "Ctrl + Left / Right": "Seek 15s",
                  }),
                  const SizedBox(height: 10),
                  _hotkeySection("Telestrator", <String, String>{
                    "T": "Toggle Telestrator",
                    "C": "Clear",
                    "Z": "Undo",
                    "1 / 2 / 3": "Set Color",
                    "[ / ]": "Brush Size Down/Up",
                  }),
                  const SizedBox(height: 10),
                  _hotkeySection("Exit and Help", <String, String>{
                    "Esc": "Exit Playout",
                    "H": "Toggle This Help",
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hotkeySection(String title, Map<String, String> entries) {
    return Builder(
      builder: (BuildContext context) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            ...entries.entries.map(
              (MapEntry<String, String> item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 210,
                      child: Text(
                        item.key,
                        style: TextStyle(
                          fontFamily: "monospace",
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: Text(item.value)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
