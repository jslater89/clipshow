import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_file_list_panel.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_preview_panel.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_tag_panel.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";

class DashboardBody extends StatefulWidget {
  const DashboardBody({
    super.key,
    this.scrollController,
    required this.onPlayClip,
  });

  final ScrollController? scrollController;
  final void Function(PlayoutClip clip) onPlayClip;

  @override
  State<DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<DashboardBody> {
  static const double _minPreviewToTagRatio = 0.5; // 1:2
  static const double _maxPreviewToTagRatio = 2.0; // 2:1
  static const int _tagFlexBase = 100;
  static const double _dragSensitivity = 300.0;

  double _previewToTagRatio = 2.0;

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    if (viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.workspacePath == null) {
      return const Center(
        child: Text("Select a workspace to start ingesting media."),
      );
    }
    final List<MediaListItem> visibleMediaItems = viewModel.visibleItems;
    if (viewModel.mediaFiles.isEmpty) {
      return const Center(
        child: Text("No supported media files found in this workspace."),
      );
    }
    final int previewFlex = (_previewToTagRatio * _tagFlexBase).round();
    final int tagFlex = _tagFlexBase;

    return Row(
      children: <Widget>[
        Expanded(
          flex: 4,
          child: DashboardFileListPanel(
            workspacePath: viewModel.workspacePath!,
            mediaItems: visibleMediaItems,
            scrollController: widget.scrollController,
            onPlayClip: widget.onPlayClip,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 6,
          child: Column(
            children: <Widget>[
              Expanded(
                flex: previewFlex,
                child: DashboardPreviewPanel(onPlayClip: widget.onPlayClip),
              ),
              _buildResizeHandle(context),
              Expanded(flex: tagFlex, child: DashboardTagPanel()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResizeHandle(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (DragUpdateDetails details) {
          setState(() {
            final double nextRatio =
                _previewToTagRatio + (details.delta.dy / _dragSensitivity);
            _previewToTagRatio = nextRatio.clamp(
              _minPreviewToTagRatio,
              _maxPreviewToTagRatio,
            );
          });
        },
        child: SizedBox(
          height: 20,
          child: Center(
            child: Icon(
              Icons.drag_handle,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
