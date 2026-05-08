import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "clip_player_view.dart";

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

class PlayoutToggleHelpIntent extends Intent {
  const PlayoutToggleHelpIntent();
}

class PlayoutHotkeysLayer extends StatelessWidget {
  const PlayoutHotkeysLayer({
    super.key,
    required this.controller,
    required this.child,
    required this.onExitRequested,
    required this.onHelpToggleRequested,
  });

  final ClipPlayerController controller;
  final Widget child;
  final Future<void> Function() onExitRequested;
  final VoidCallback onHelpToggleRequested;

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
        const SingleActivator(LogicalKeyboardKey.keyH):
            const PlayoutToggleHelpIntent(),
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
              controller.seekBy(const Duration(seconds: -5));
              return null;
            },
          ),
          PlayoutSeekForwardIntent: CallbackAction<PlayoutSeekForwardIntent>(
            onInvoke: (_) {
              controller.seekBy(const Duration(seconds: 5));
              return null;
            },
          ),
          PlayoutSeekShortBackwardIntent:
              CallbackAction<PlayoutSeekShortBackwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: -1));
                  return null;
                },
              ),
          PlayoutSeekShortForwardIntent:
              CallbackAction<PlayoutSeekShortForwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: 1));
                  return null;
                },
              ),
          PlayoutSeekLongBackwardIntent:
              CallbackAction<PlayoutSeekLongBackwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: -15));
                  return null;
                },
              ),
          PlayoutSeekLongForwardIntent:
              CallbackAction<PlayoutSeekLongForwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: 15));
                  return null;
                },
              ),
          PlayoutToggleHelpIntent: CallbackAction<PlayoutToggleHelpIntent>(
            onInvoke: (_) {
              onHelpToggleRequested();
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
