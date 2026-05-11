import "package:flutter/material.dart";
import "package:flutter/services.dart";

import 'package:obs_clipshow/src/features/playout/clip_player_view.dart';

class PlayoutSeekBackwardIntent extends Intent {
  const PlayoutSeekBackwardIntent();
}

class PlayoutSeekForwardIntent extends Intent {
  const PlayoutSeekForwardIntent();
}

class PlayoutSeekShortBackwardIntent extends Intent {
  const PlayoutSeekShortBackwardIntent();
}

class PlayoutSeekShortForwardIntent extends Intent {
  const PlayoutSeekShortForwardIntent();
}

class PlayoutSeekLongBackwardIntent extends Intent {
  const PlayoutSeekLongBackwardIntent();
}

class PlayoutSeekLongForwardIntent extends Intent {
  const PlayoutSeekLongForwardIntent();
}

class PlayoutSeekMicroBackwardIntent extends Intent {
  const PlayoutSeekMicroBackwardIntent();
}

class PlayoutSeekMicroForwardIntent extends Intent {
  const PlayoutSeekMicroForwardIntent();
}

class PlayoutSeekToStartIntent extends Intent {
  const PlayoutSeekToStartIntent();
}

class PlayoutSeekToEndIntent extends Intent {
  const PlayoutSeekToEndIntent();
}

class PlayoutToggleHelpIntent extends Intent {
  const PlayoutToggleHelpIntent();
}

class PlayoutToggleTelestratorIntent extends Intent {
  const PlayoutToggleTelestratorIntent();
}

class PlayoutClearTelestratorIntent extends Intent {
  const PlayoutClearTelestratorIntent();
}

class PlayoutUndoTelestratorIntent extends Intent {
  const PlayoutUndoTelestratorIntent();
}

class PlayoutSetTelestratorColor1Intent extends Intent {
  const PlayoutSetTelestratorColor1Intent();
}

class PlayoutSetTelestratorColor2Intent extends Intent {
  const PlayoutSetTelestratorColor2Intent();
}

class PlayoutSetTelestratorColor3Intent extends Intent {
  const PlayoutSetTelestratorColor3Intent();
}

class PlayoutDecreaseBrushIntent extends Intent {
  const PlayoutDecreaseBrushIntent();
}

class PlayoutIncreaseBrushIntent extends Intent {
  const PlayoutIncreaseBrushIntent();
}

class PlayoutOsgPresetDigit8Intent extends Intent {
  const PlayoutOsgPresetDigit8Intent();
}

class PlayoutOsgPresetDigit9Intent extends Intent {
  const PlayoutOsgPresetDigit9Intent();
}

class PlayoutOsgPresetDigit0Intent extends Intent {
  const PlayoutOsgPresetDigit0Intent();
}

class PlayoutHotkeysLayer extends StatelessWidget {
  const PlayoutHotkeysLayer({
    super.key,
    required this.controller,
    required this.child,
    required this.onExitRequested,
    required this.onHelpToggleRequested,
    this.onTelestratorToggleRequested,
    this.onTelestratorClearRequested,
    this.onTelestratorUndoRequested,
    this.onSetTelestratorColor1Requested,
    this.onSetTelestratorColor2Requested,
    this.onSetTelestratorColor3Requested,
    this.onDecreaseBrushRequested,
    this.onIncreaseBrushRequested,
    this.onOsgPresetDigit8Requested,
    this.onOsgPresetDigit9Requested,
    this.onOsgPresetDigit0Requested,
  });

  final ClipPlayerController controller;
  final Widget child;
  final Future<void> Function() onExitRequested;
  final VoidCallback onHelpToggleRequested;
  final VoidCallback? onTelestratorToggleRequested;
  final VoidCallback? onTelestratorClearRequested;
  final VoidCallback? onTelestratorUndoRequested;
  final VoidCallback? onSetTelestratorColor1Requested;
  final VoidCallback? onSetTelestratorColor2Requested;
  final VoidCallback? onSetTelestratorColor3Requested;
  final VoidCallback? onDecreaseBrushRequested;
  final VoidCallback? onIncreaseBrushRequested;
  final VoidCallback? onOsgPresetDigit8Requested;
  final VoidCallback? onOsgPresetDigit9Requested;
  final VoidCallback? onOsgPresetDigit0Requested;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const PlayoutSeekBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const PlayoutSeekForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            const PlayoutSeekShortBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            const PlayoutSeekShortForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            const PlayoutSeekLongBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            const PlayoutSeekLongForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            const PlayoutSeekMicroBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            const PlayoutSeekMicroForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.home):
            const PlayoutSeekToStartIntent(),
        const SingleActivator(LogicalKeyboardKey.end):
            const PlayoutSeekToEndIntent(),
        const SingleActivator(LogicalKeyboardKey.keyH):
            const PlayoutToggleHelpIntent(),
        if (onTelestratorToggleRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyT):
              const PlayoutToggleTelestratorIntent(),
        if (onTelestratorClearRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyC):
              const PlayoutClearTelestratorIntent(),
        if (onTelestratorUndoRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyZ):
              const PlayoutUndoTelestratorIntent(),
        if (onSetTelestratorColor1Requested != null)
          const SingleActivator(LogicalKeyboardKey.digit1):
              const PlayoutSetTelestratorColor1Intent(),
        if (onSetTelestratorColor2Requested != null)
          const SingleActivator(LogicalKeyboardKey.digit2):
              const PlayoutSetTelestratorColor2Intent(),
        if (onSetTelestratorColor3Requested != null)
          const SingleActivator(LogicalKeyboardKey.digit3):
              const PlayoutSetTelestratorColor3Intent(),
        if (onDecreaseBrushRequested != null)
          const SingleActivator(LogicalKeyboardKey.bracketLeft):
              const PlayoutDecreaseBrushIntent(),
        if (onIncreaseBrushRequested != null)
          const SingleActivator(LogicalKeyboardKey.bracketRight):
              const PlayoutIncreaseBrushIntent(),
        if (onOsgPresetDigit8Requested != null)
          const SingleActivator(LogicalKeyboardKey.digit8):
              const PlayoutOsgPresetDigit8Intent(),
        if (onOsgPresetDigit9Requested != null)
          const SingleActivator(LogicalKeyboardKey.digit9):
              const PlayoutOsgPresetDigit9Intent(),
        if (onOsgPresetDigit0Requested != null)
          const SingleActivator(LogicalKeyboardKey.digit0):
              const PlayoutOsgPresetDigit0Intent(),
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              controller.togglePlayPause();
              return null;
            },
          ),
          PlayoutSeekBackwardIntent: CallbackAction<PlayoutSeekBackwardIntent>(
            onInvoke: (_) {
              controller.seekBy(const Duration(seconds: -1));
              return null;
            },
          ),
          PlayoutSeekForwardIntent: CallbackAction<PlayoutSeekForwardIntent>(
            onInvoke: (_) {
              controller.seekBy(const Duration(seconds: 1));
              return null;
            },
          ),
          PlayoutSeekShortBackwardIntent:
              CallbackAction<PlayoutSeekShortBackwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: -15));
                  return null;
                },
              ),
          PlayoutSeekShortForwardIntent:
              CallbackAction<PlayoutSeekShortForwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: 15));
                  return null;
                },
              ),
          PlayoutSeekLongBackwardIntent:
              CallbackAction<PlayoutSeekLongBackwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: -5));
                  return null;
                },
              ),
          PlayoutSeekLongForwardIntent:
              CallbackAction<PlayoutSeekLongForwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: 5));
                  return null;
                },
              ),
          PlayoutSeekMicroBackwardIntent:
              CallbackAction<PlayoutSeekMicroBackwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(milliseconds: -100));
                  return null;
                },
              ),
          PlayoutSeekMicroForwardIntent:
              CallbackAction<PlayoutSeekMicroForwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(milliseconds: 100));
                  return null;
                },
              ),
          PlayoutSeekToStartIntent: CallbackAction<PlayoutSeekToStartIntent>(
            onInvoke: (_) {
              controller.seekToStart();
              return null;
            },
          ),
          PlayoutSeekToEndIntent: CallbackAction<PlayoutSeekToEndIntent>(
            onInvoke: (_) {
              controller.seekToEnd();
              return null;
            },
          ),
          PlayoutToggleHelpIntent: CallbackAction<PlayoutToggleHelpIntent>(
            onInvoke: (_) {
              onHelpToggleRequested();
              return null;
            },
          ),
          PlayoutToggleTelestratorIntent:
              CallbackAction<PlayoutToggleTelestratorIntent>(
                onInvoke: (_) {
                  onTelestratorToggleRequested?.call();
                  return null;
                },
              ),
          PlayoutClearTelestratorIntent:
              CallbackAction<PlayoutClearTelestratorIntent>(
                onInvoke: (_) {
                  onTelestratorClearRequested?.call();
                  return null;
                },
              ),
          PlayoutUndoTelestratorIntent:
              CallbackAction<PlayoutUndoTelestratorIntent>(
                onInvoke: (_) {
                  onTelestratorUndoRequested?.call();
                  return null;
                },
              ),
          PlayoutSetTelestratorColor1Intent:
              CallbackAction<PlayoutSetTelestratorColor1Intent>(
                onInvoke: (_) {
                  onSetTelestratorColor1Requested?.call();
                  return null;
                },
              ),
          PlayoutSetTelestratorColor2Intent:
              CallbackAction<PlayoutSetTelestratorColor2Intent>(
                onInvoke: (_) {
                  onSetTelestratorColor2Requested?.call();
                  return null;
                },
              ),
          PlayoutSetTelestratorColor3Intent:
              CallbackAction<PlayoutSetTelestratorColor3Intent>(
                onInvoke: (_) {
                  onSetTelestratorColor3Requested?.call();
                  return null;
                },
              ),
          PlayoutDecreaseBrushIntent:
              CallbackAction<PlayoutDecreaseBrushIntent>(
                onInvoke: (_) {
                  onDecreaseBrushRequested?.call();
                  return null;
                },
              ),
          PlayoutIncreaseBrushIntent:
              CallbackAction<PlayoutIncreaseBrushIntent>(
                onInvoke: (_) {
                  onIncreaseBrushRequested?.call();
                  return null;
                },
              ),
          PlayoutOsgPresetDigit8Intent:
              CallbackAction<PlayoutOsgPresetDigit8Intent>(
                onInvoke: (_) {
                  onOsgPresetDigit8Requested?.call();
                  return null;
                },
              ),
          PlayoutOsgPresetDigit9Intent:
              CallbackAction<PlayoutOsgPresetDigit9Intent>(
                onInvoke: (_) {
                  onOsgPresetDigit9Requested?.call();
                  return null;
                },
              ),
          PlayoutOsgPresetDigit0Intent:
              CallbackAction<PlayoutOsgPresetDigit0Intent>(
                onInvoke: (_) {
                  onOsgPresetDigit0Requested?.call();
                  return null;
                },
              ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              onExitRequested();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
