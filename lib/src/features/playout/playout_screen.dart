import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/playout/clip_player_view.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/features/playout/playout_hotkeys_layer.dart";
import "package:obs_clipshow/src/features/playout/telestrator_canvas.dart";
import "package:obs_clipshow/src/features/playout/telestrator_model.dart";

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
  final TelestratorController _telestratorController = TelestratorController();
  static const Color _colorOne = Color(0xFFFF3B30);
  static const Color _colorTwo = Color(0xFFFFCC00);
  static const Color _colorThree = Color(0xFF34C759);
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
    _telestratorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double edgeInset = scaleDimension(context, 16);
    return Scaffold(
      backgroundColor: Colors.black,
      body: PlayoutHotkeysLayer(
        controller: _playerController,
        onExitRequested: _requestExit,
        onHelpToggleRequested: _toggleHelpOverlay,
        onTelestratorToggleRequested: _telestratorController.toggleEnabled,
        onTelestratorClearRequested: _telestratorController.clear,
        onTelestratorUndoRequested: _telestratorController.undo,
        onSetTelestratorColor1Requested: () =>
            _telestratorController.setColor(_colorOne),
        onSetTelestratorColor2Requested: () =>
            _telestratorController.setColor(_colorTwo),
        onSetTelestratorColor3Requested: () =>
            _telestratorController.setColor(_colorThree),
        onDecreaseBrushRequested: _telestratorController.decreaseBrush,
        onIncreaseBrushRequested: _telestratorController.increaseBrush,
        child: Stack(
          children: <Widget>[
            ClipPlayerView(
              controller: _playerController,
              filePath: widget.clip.filePath,
              startTimeMs: widget.clip.startTimeMs,
              endTimeMs: widget.clip.endTimeMs,
              initialPositionMs: widget.clip.initialPositionMs,
              autoPlay: true,
            ),
            Positioned.fill(
              child: TelestratorCanvas(controller: _telestratorController),
            ),
            Positioned(
              left: edgeInset,
              bottom: edgeInset,
              child: _TelestratorStatusHud(controller: _telestratorController),
            ),
            if (_showEscapeHint && !_showHelpOverlay)
              Positioned(
                right: edgeInset,
                bottom: edgeInset,
                child: const Text(
                  "Press Escape to return",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            if (_showHelpOverlay) const _PlayoutHelpOverlay(),
          ],
        ),
      ),
    );
  }
}

class _TelestratorStatusHud extends StatefulWidget {
  const _TelestratorStatusHud({required this.controller});

  final TelestratorController controller;

  @override
  State<_TelestratorStatusHud> createState() => _TelestratorStatusHudState();
}

class _TelestratorStatusHudState extends State<_TelestratorStatusHud> {
  static const Duration _autoHideDelay = Duration(seconds: 1);
  static const Duration _fadeDuration = Duration(milliseconds: 220);

  Timer? _hideTimer;
  bool _isVisible = true;
  bool _lastEnabled = true;
  double _lastBrushSize = 0;
  Color _lastColor = const Color(0x00000000);

  @override
  void initState() {
    super.initState();
    _snapshotCurrentValues();
    widget.controller.addListener(_onControllerChanged);
    _restartHideTimer();
  }

  @override
  void didUpdateWidget(covariant _TelestratorStatusHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _snapshotCurrentValues();
      widget.controller.addListener(_onControllerChanged);
      _showAndScheduleHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _snapshotCurrentValues() {
    _lastEnabled = widget.controller.isEnabled;
    _lastBrushSize = widget.controller.brushSize;
    _lastColor = widget.controller.activeColor;
  }

  void _onControllerChanged() {
    final bool enabled = widget.controller.isEnabled;
    final double brushSize = widget.controller.brushSize;
    final Color color = widget.controller.activeColor;
    final bool statusChanged =
        enabled != _lastEnabled ||
        brushSize != _lastBrushSize ||
        color != _lastColor;
    _snapshotCurrentValues();
    if (!statusChanged) {
      return;
    }
    setState(() {
      _isVisible = true;
    });
    _restartHideTimer();
  }

  void _showAndScheduleHide() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isVisible = true;
    });
    _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _isVisible = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final double hudPadH = scaleDimension(context, 10);
    final double hudPadV = scaleDimension(context, 8);
    final double hudRadius = scaleDimension(context, 8);
    final double hudGap = scaleDimension(context, 8);
    final double swatchSize = scaleDimension(context, 12);
    return AnimatedOpacity(
      opacity: _isVisible ? 1 : 0,
      duration: _fadeDuration,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(hudRadius),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hudPadH, vertical: hudPadV),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                "Telestrator ${widget.controller.isEnabled ? "On" : "Off"}",
                style: const TextStyle(color: Colors.white70),
              ),
              SizedBox(width: hudGap),
              Container(
                width: swatchSize,
                height: swatchSize,
                decoration: BoxDecoration(
                  color: widget.controller.activeColor,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: hudGap),
              Text(
                "Brush ${widget.controller.brushSize.toStringAsFixed(0)}",
                style: const TextStyle(color: Colors.white70),
              ),
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
    final double pad20 = scaleDimension(context, 20);
    final double gap12 = scaleDimension(context, 12);
    final double gap10 = scaleDimension(context, 10);
    final double maxHelpWidth = scaleDimension(context, 720);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxHelpWidth),
          child: Card(
            color: colorScheme.surface.withValues(alpha: 0.95),
            child: Padding(
              padding: EdgeInsets.all(pad20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Playout Hotkeys",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: gap12),
                  _hotkeySection("Playback", <String, String>{
                    "Space": "Play/Pause",
                  }),
                  SizedBox(height: gap10),
                  _hotkeySection("Seek", <String, String>{
                    "Left / Right": "Seek 1s",
                    "Ctrl + Left / Right": "Seek 5s",
                    "Shift + Left / Right": "Seek 15s",
                    "Alt + Left / Right": "Seek 0.1s",
                  }),
                  SizedBox(height: gap10),
                  _hotkeySection("Telestrator", <String, String>{
                    "T": "Toggle Telestrator",
                    "C": "Clear",
                    "Z": "Undo",
                    "1 / 2 / 3": "Set Color",
                    "[ / ]": "Brush Size Down/Up",
                  }),
                  SizedBox(height: gap10),
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
        final double gap6 = scaleDimension(context, 6);
        final double rowVertPad = scaleDimension(context, 2);
        final double keyColWidth = scaleDimension(context, 210);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            SizedBox(height: gap6),
            ...entries.entries.map(
              (MapEntry<String, String> item) => Padding(
                padding: EdgeInsets.symmetric(vertical: rowVertPad),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: keyColWidth,
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
