import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";

import "clip_player_view.dart";
import "playout_clip.dart";

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
  bool _isExiting = false;
  bool _showEscapeHint = true;
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

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ClipPlayerView(
        filePath: widget.clip.filePath,
        startTimeMs: widget.clip.startTimeMs,
        endTimeMs: widget.clip.endTimeMs,
        autoPlay: true,
        onEscapePressed: _requestExit,
        overlay: _showEscapeHint
            ? const Positioned(
                right: 16,
                bottom: 16,
                child: Text(
                  "Press Escape to return",
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : null,
      ),
    );
  }
}
