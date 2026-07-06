import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_osg_preset_hotkeys_layer.dart";
import "package:obs_clipshow/src/features/playout/clip_player_view.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

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

class PreviewSeekToStartIntent extends Intent {
  const PreviewSeekToStartIntent();
}

class PreviewSeekToEndIntent extends Intent {
  const PreviewSeekToEndIntent();
}

class PreviewToggleHelpIntent extends Intent {
  const PreviewToggleHelpIntent();
}

class PreviewOsgPresetSlotIntent extends Intent {
  const PreviewOsgPresetSlotIntent(this.slot);
  final OsgPresetSlot slot;
}

class PreviewVolumeUpIntent extends Intent {
  const PreviewVolumeUpIntent();
}

class PreviewVolumeDownIntent extends Intent {
  const PreviewVolumeDownIntent();
}

class PreviewToggleMuteIntent extends Intent {
  const PreviewToggleMuteIntent();
}

class DashboardPreviewHotkeysLayer extends StatelessWidget {
  const DashboardPreviewHotkeysLayer({
    super.key,
    required this.child,
    required this.controller,
    required this.focusNode,
    required this.onHelpToggleRequested,
    this.onMarkInRequested,
    this.onMarkOutRequested,
    this.onSaveClipRequested,
    this.onOsgPresetSlotToggle,
    this.onVolumeUpRequested,
    this.onVolumeDownRequested,
    this.onMuteToggleRequested,
  });

  final Widget child;
  final ClipPlayerController controller;
  final FocusNode focusNode;
  final VoidCallback onHelpToggleRequested;
  final VoidCallback? onMarkInRequested;
  final VoidCallback? onMarkOutRequested;
  final VoidCallback? onSaveClipRequested;
  final ValueChanged<OsgPresetSlot>? onOsgPresetSlotToggle;
  final VoidCallback? onVolumeUpRequested;
  final VoidCallback? onVolumeDownRequested;
  final VoidCallback? onMuteToggleRequested;

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
        const SingleActivator(LogicalKeyboardKey.home):
            const PreviewSeekToStartIntent(),
        const SingleActivator(LogicalKeyboardKey.end):
            const PreviewSeekToEndIntent(),
        const SingleActivator(LogicalKeyboardKey.keyH):
            const PreviewToggleHelpIntent(),
        if (onMarkInRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyI):
              const PreviewMarkInIntent(),
        if (onMarkOutRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyO):
              const PreviewMarkOutIntent(),
        if (onSaveClipRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyS):
              const PreviewSaveClipIntent(),
        if (onOsgPresetSlotToggle != null) ...osgPresetSlotShortcutMap(),
        if (onVolumeUpRequested != null)
          const SingleActivator(LogicalKeyboardKey.arrowUp):
              const PreviewVolumeUpIntent(),
        if (onVolumeDownRequested != null)
          const SingleActivator(LogicalKeyboardKey.arrowDown):
              const PreviewVolumeDownIntent(),
        if (onMuteToggleRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyM):
              const PreviewToggleMuteIntent(),
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
          PreviewSeekToStartIntent: CallbackAction<PreviewSeekToStartIntent>(
            onInvoke: (_) {
              controller.seekToStart();
              return null;
            },
          ),
          PreviewSeekToEndIntent: CallbackAction<PreviewSeekToEndIntent>(
            onInvoke: (_) {
              controller.seekToEnd();
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
          PreviewToggleHelpIntent: CallbackAction<PreviewToggleHelpIntent>(
            onInvoke: (_) {
              onHelpToggleRequested();
              return null;
            },
          ),
          PreviewOsgPresetSlotIntent:
              CallbackAction<PreviewOsgPresetSlotIntent>(
                onInvoke: (PreviewOsgPresetSlotIntent intent) {
                  onOsgPresetSlotToggle?.call(intent.slot);
                  return null;
                },
              ),
          PreviewVolumeUpIntent: CallbackAction<PreviewVolumeUpIntent>(
            onInvoke: (_) {
              onVolumeUpRequested?.call();
              return null;
            },
          ),
          PreviewVolumeDownIntent: CallbackAction<PreviewVolumeDownIntent>(
            onInvoke: (_) {
              onVolumeDownRequested?.call();
              return null;
            },
          ),
          PreviewToggleMuteIntent: CallbackAction<PreviewToggleMuteIntent>(
            onInvoke: (_) {
              onMuteToggleRequested?.call();
              return null;
            },
          ),
        },
        child: Focus(focusNode: focusNode, autofocus: true, child: child),
      ),
    );
  }
}
