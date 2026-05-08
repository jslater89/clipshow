import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "package:obs_clipshow/src/features/playout/clip_player_view.dart";

class PreviewMarkInIntent extends Intent {
  const PreviewMarkInIntent();
}

class PreviewMarkOutIntent extends Intent {
  const PreviewMarkOutIntent();
}

class PreviewSaveClipIntent extends Intent {
  const PreviewSaveClipIntent();
}

class PreviewSeekBackwardIntent extends Intent {
  const PreviewSeekBackwardIntent();
}

class PreviewSeekForwardIntent extends Intent {
  const PreviewSeekForwardIntent();
}

class PreviewSeekShortBackwardIntent extends Intent {
  const PreviewSeekShortBackwardIntent();
}

class PreviewSeekShortForwardIntent extends Intent {
  const PreviewSeekShortForwardIntent();
}

class PreviewSeekLongBackwardIntent extends Intent {
  const PreviewSeekLongBackwardIntent();
}

class PreviewSeekLongForwardIntent extends Intent {
  const PreviewSeekLongForwardIntent();
}

class PreviewSeekMicroBackwardIntent extends Intent {
  const PreviewSeekMicroBackwardIntent();
}

class PreviewSeekMicroForwardIntent extends Intent {
  const PreviewSeekMicroForwardIntent();
}

class DashboardPreviewHotkeysLayer extends StatelessWidget {
  const DashboardPreviewHotkeysLayer({
    super.key,
    required this.child,
    required this.controller,
    this.onMarkInRequested,
    this.onMarkOutRequested,
    this.onSaveClipRequested,
  });

  final Widget child;
  final ClipPlayerController controller;
  final VoidCallback? onMarkInRequested;
  final VoidCallback? onMarkOutRequested;
  final VoidCallback? onSaveClipRequested;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const PreviewSeekBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const PreviewSeekForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            const PreviewSeekShortBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            const PreviewSeekShortForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            const PreviewSeekLongBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            const PreviewSeekLongForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            const PreviewSeekMicroBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            const PreviewSeekMicroForwardIntent(),
        if (onMarkInRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyI):
              const PreviewMarkInIntent(),
        if (onMarkOutRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyO):
              const PreviewMarkOutIntent(),
        if (onSaveClipRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyS):
              const PreviewSaveClipIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              controller.togglePlayPause();
              return null;
            },
          ),
          PreviewSeekBackwardIntent: CallbackAction<PreviewSeekBackwardIntent>(
            onInvoke: (_) {
              controller.seekBy(const Duration(seconds: -1));
              return null;
            },
          ),
          PreviewSeekForwardIntent: CallbackAction<PreviewSeekForwardIntent>(
            onInvoke: (_) {
              controller.seekBy(const Duration(seconds: 1));
              return null;
            },
          ),
          PreviewSeekShortBackwardIntent:
              CallbackAction<PreviewSeekShortBackwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: -15));
                  return null;
                },
              ),
          PreviewSeekShortForwardIntent:
              CallbackAction<PreviewSeekShortForwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: 15));
                  return null;
                },
              ),
          PreviewSeekLongBackwardIntent:
              CallbackAction<PreviewSeekLongBackwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: -5));
                  return null;
                },
              ),
          PreviewSeekLongForwardIntent:
              CallbackAction<PreviewSeekLongForwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(seconds: 5));
                  return null;
                },
              ),
          PreviewSeekMicroBackwardIntent:
              CallbackAction<PreviewSeekMicroBackwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(milliseconds: -100));
                  return null;
                },
              ),
          PreviewSeekMicroForwardIntent:
              CallbackAction<PreviewSeekMicroForwardIntent>(
                onInvoke: (_) {
                  controller.seekBy(const Duration(milliseconds: 100));
                  return null;
                },
              ),
          PreviewMarkInIntent: CallbackAction<PreviewMarkInIntent>(
            onInvoke: (_) {
              onMarkInRequested?.call();
              return null;
            },
          ),
          PreviewMarkOutIntent: CallbackAction<PreviewMarkOutIntent>(
            onInvoke: (_) {
              onMarkOutRequested?.call();
              return null;
            },
          ),
          PreviewSaveClipIntent: CallbackAction<PreviewSaveClipIntent>(
            onInvoke: (_) {
              onSaveClipRequested?.call();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
