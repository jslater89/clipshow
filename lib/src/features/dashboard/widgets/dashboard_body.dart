import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_file_list_panel.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_capture_panel.dart";
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
  static const double _resizeHandleHeight = 20.0;

  final GlobalKey _splitPaneKey = GlobalKey();
  final FocusNode _previewFocusNode = FocusNode(
    debugLabel: "DashboardPreviewFocus",
  );
  double _previewToTagRatio = 2.0;

  @override
  void dispose() {
    _previewFocusNode.dispose();
    super.dispose();
  }

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
            onPreviewFocusRequested: _previewFocusNode.requestFocus,
            onMediaItemSelected: (MediaListItem item) {
              viewModel.setMediaPaneTab(DashboardMediaPaneTab.manage);
              viewModel.selectItem(item);
              _previewFocusNode.requestFocus();
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 6,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Column(
                key: _splitPaneKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SegmentedButton<DashboardMediaPaneTab>(
                      segments: const <ButtonSegment<DashboardMediaPaneTab>>[
                        ButtonSegment<DashboardMediaPaneTab>(
                          value: DashboardMediaPaneTab.manage,
                          label: Text("Manage"),
                          icon: Icon(Icons.movie_outlined),
                        ),
                        ButtonSegment<DashboardMediaPaneTab>(
                          value: DashboardMediaPaneTab.capture,
                          label: Text("Capture"),
                          icon: Icon(Icons.videocam_outlined),
                        ),
                      ],
                      selected: <DashboardMediaPaneTab>{viewModel.mediaPaneTab},
                      onSelectionChanged:
                          (Set<DashboardMediaPaneTab> selected) {
                            if (selected.isEmpty) {
                              return;
                            }
                            viewModel.setMediaPaneTab(selected.first);
                          },
                    ),
                  ),
                  Expanded(
                    child:
                        viewModel.mediaPaneTab == DashboardMediaPaneTab.capture
                        ? const DashboardCapturePanel()
                        : Column(
                            children: <Widget>[
                              Expanded(
                                flex: previewFlex,
                                child: DashboardPreviewPanel(
                                  onPlayClip: widget.onPlayClip,
                                  focusNode: _previewFocusNode,
                                ),
                              ),
                              _buildResizeHandle(context),
                              Expanded(
                                flex: tagFlex,
                                child: DashboardTagPanel(
                                  onPreviewFocusRequested:
                                      _previewFocusNode.requestFocus,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              );
            },
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
          final BuildContext? splitPaneContext = _splitPaneKey.currentContext;
          if (splitPaneContext == null) {
            return;
          }
          final RenderObject? renderObject = splitPaneContext
              .findRenderObject();
          if (renderObject is! RenderBox) {
            return;
          }
          final double availableHeight =
              renderObject.size.height - _resizeHandleHeight;
          if (availableHeight <= 1) {
            return;
          }
          final double localY = renderObject
              .globalToLocal(details.globalPosition)
              .dy;
          final double nextPreviewHeight = (localY - (_resizeHandleHeight / 2))
              .clamp(0.0, availableHeight);
          final double nextTagHeight = (availableHeight - nextPreviewHeight)
              .clamp(1.0, availableHeight);
          setState(() {
            _previewToTagRatio = (nextPreviewHeight / nextTagHeight).clamp(
              _minPreviewToTagRatio,
              _maxPreviewToTagRatio,
            );
          });
        },
        child: SizedBox(
          height: _resizeHandleHeight,
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
