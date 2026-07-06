import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_bake_queue_panel.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_file_list_panel.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_capture_panel.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_preview_panel.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_tag_panel.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_tag_set_pane.dart";
import "package:obs_clipshow/src/features/osg_mode/osg_mode_session.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";

class DashboardBody extends StatefulWidget {
  const DashboardBody({
    super.key,
    this.scrollController,
    required this.onPlayClip,
    required this.onRecordClip,
    required this.onEnterOsgMode,
  });

  final ScrollController? scrollController;
  final void Function(PlayoutClip clip) onPlayClip;
  final void Function(PlayoutClip clip) onRecordClip;
  final void Function(OsgModeSession session) onEnterOsgMode;

  @override
  State<DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<DashboardBody> {
  static const double _minPreviewToTagRatio = 0.5; // 1:2
  static const double _maxPreviewToTagRatio = 2.0; // 2:1
  /// Default preview:tags proportion before the user drags (preview height ratio).
  static const double _initialPreviewToTagRatio = 2.0;
  static const double _resizeHandleLogicalHeight = 20;
  static const double _resizeHandleIconLogicalSize = 18;

  final GlobalKey _splitPaneKey = GlobalKey();
  final FocusNode _previewFocusNode = FocusNode(debugLabel: "DashboardPreviewFocus");
  final FocusNode _tagSetPreviewFocusNode = FocusNode(debugLabel: "TagSetPreviewFocus");

  /// Drag-set preview pane height; null means use [_defaultPreviewHeight].
  double? _previewPanelHeightPx;
  double? _splitDragStartGlobalY;
  double? _splitDragStartPreviewHeight;

  double _previewHeightMin(double panelBudget) => panelBudget * _minPreviewToTagRatio / (_minPreviewToTagRatio + 1);

  double _previewHeightMax(double panelBudget) => panelBudget * _maxPreviewToTagRatio / (_maxPreviewToTagRatio + 1);

  double _defaultPreviewHeight(double panelBudget) =>
      panelBudget * _initialPreviewToTagRatio / (_initialPreviewToTagRatio + 1);

  double _resolvedPreviewHeight(double panelBudget) {
    final double raw = _previewPanelHeightPx ?? _defaultPreviewHeight(panelBudget);
    return raw.clamp(_previewHeightMin(panelBudget), _previewHeightMax(panelBudget));
  }

  @override
  void dispose() {
    _previewFocusNode.dispose();
    _tagSetPreviewFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    if (viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.workspacePath == null) {
      return const Center(child: Text("Select a workspace to start ingesting media."));
    }
    final List<MediaListItem> visibleMediaItems = viewModel.visibleItems;
    final double paneGap = scaleDimension(context, 16);
    final double tabBarBottomPad = scaleDimension(context, 8);
    final bool hasBakeRecipes = viewModel.osgBakeRecipes.isNotEmpty;
    final DashboardMediaPaneTab effectiveTab =
        viewModel.mediaPaneTab == DashboardMediaPaneTab.bakeQueue && !hasBakeRecipes
        ? DashboardMediaPaneTab.manage
        : viewModel.mediaPaneTab;
    if (effectiveTab != viewModel.mediaPaneTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) => viewModel.setMediaPaneTab(DashboardMediaPaneTab.manage));
    }

    return Row(
      children: <Widget>[
        Expanded(
          flex: 4,
          child: DashboardFileListPanel(
            workspacePath: viewModel.workspacePath!,
            mediaItems: visibleMediaItems,
            scrollController: widget.scrollController,
            onPlayClip: widget.onPlayClip,
            onEnterOsgMode: widget.onEnterOsgMode,
            onPreviewFocusRequested: _previewFocusNode.requestFocus,
            onMediaItemSelected: (MediaListItem item) {
              final bool isTagSet = item.type == MediaListItemType.tagSet;
              viewModel.setMediaPaneTab(
                isTagSet
                    ? DashboardMediaPaneTab.tagSets
                    : DashboardMediaPaneTab.manage,
              );
              viewModel.selectItem(item);
              if (isTagSet) {
                _tagSetPreviewFocusNode.requestFocus();
              } else {
                _previewFocusNode.requestFocus();
              }
            },
          ),
        ),
        SizedBox(width: paneGap),
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.only(bottom: tabBarBottomPad),
                child: SegmentedButton<DashboardMediaPaneTab>(
                  segments: <ButtonSegment<DashboardMediaPaneTab>>[
                    const ButtonSegment<DashboardMediaPaneTab>(
                      value: DashboardMediaPaneTab.manage,
                      label: Text("Manage"),
                      icon: Icon(Icons.movie_outlined),
                    ),
                    const ButtonSegment<DashboardMediaPaneTab>(
                      value: DashboardMediaPaneTab.capture,
                      label: Text("Capture"),
                      icon: Icon(Icons.videocam_outlined),
                    ),
                    if (hasBakeRecipes)
                      const ButtonSegment<DashboardMediaPaneTab>(
                        value: DashboardMediaPaneTab.bakeQueue,
                        label: Text("Bake Queue"),
                        icon: Icon(Icons.queue_play_next_outlined),
                      ),
                    ButtonSegment<DashboardMediaPaneTab>(
                      value: DashboardMediaPaneTab.tagSets,
                      label: Text("Tag Sets"),
                      icon: Icon(Icons.layers_outlined),
                    ),
                  ],
                  selected: <DashboardMediaPaneTab>{effectiveTab},
                  onSelectionChanged: (Set<DashboardMediaPaneTab> selected) {
                    if (selected.isEmpty) {
                      return;
                    }
                    final DashboardMediaPaneTab tab = selected.first;
                    viewModel.setMediaPaneTab(tab);
                    if (tab == DashboardMediaPaneTab.tagSets) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _tagSetPreviewFocusNode.requestFocus();
                        }
                      });
                    }
                  },
                ),
              ),
              Expanded(
                child: switch (viewModel.mediaPaneTab) {
                  DashboardMediaPaneTab.capture => const DashboardCapturePanel(),
                  DashboardMediaPaneTab.bakeQueue => const DashboardBakeQueuePanel(),
                  DashboardMediaPaneTab.tagSets => DashboardTagSetPane(
                    onEnterOsgMode: widget.onEnterOsgMode,
                    onPreviewFocusRequested: _tagSetPreviewFocusNode.requestFocus,
                    previewFocusNode: _tagSetPreviewFocusNode,
                  ),
                  DashboardMediaPaneTab.manage => LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints constraints) {
                          final double handleH = scaleDimension(
                            context,
                            _resizeHandleLogicalHeight,
                          );
                          final double panelBudget =
                              constraints.maxHeight - handleH;
                          if (panelBudget <= 1) {
                            return Column(
                              key: _splitPaneKey,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                const SizedBox.shrink(),
                                _buildResizeHandle(context),
                                const Expanded(child: SizedBox.shrink()),
                              ],
                            );
                          }
                          final double previewHeight =
                              _resolvedPreviewHeight(panelBudget);
                          return Column(
                            key: _splitPaneKey,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              SizedBox(
                                height: previewHeight,
                                child: DashboardPreviewPanel(
                                  onPlayClip: widget.onPlayClip,
                                  onRecordClip: widget.onRecordClip,
                                  focusNode: _previewFocusNode,
                                ),
                              ),
                              _buildResizeHandle(context),
                              Expanded(
                                child: DashboardTagPanel(
                                  onPreviewFocusRequested:
                                      _previewFocusNode.requestFocus,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResizeHandle(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double handleHeight = scaleDimension(context, _resizeHandleLogicalHeight);
    final double iconSize = scaleDimension(context, _resizeHandleIconLogicalSize);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (DragStartDetails details) {
          final BuildContext? splitPaneContext = _splitPaneKey.currentContext;
          if (splitPaneContext == null) {
            return;
          }
          final RenderObject? renderObject = splitPaneContext.findRenderObject();
          if (renderObject is! RenderBox) {
            return;
          }
          final double handle = scaleDimension(splitPaneContext, _resizeHandleLogicalHeight);
          final double availableHeight = renderObject.size.height - handle;
          if (availableHeight <= 1) {
            return;
          }
          _splitDragStartGlobalY = details.globalPosition.dy;
          _splitDragStartPreviewHeight = _resolvedPreviewHeight(availableHeight);
        },
        onVerticalDragUpdate: (DragUpdateDetails details) {
          if (_splitDragStartGlobalY == null || _splitDragStartPreviewHeight == null) {
            return;
          }
          final BuildContext? splitPaneContext = _splitPaneKey.currentContext;
          if (splitPaneContext == null) {
            return;
          }
          final RenderObject? renderObject = splitPaneContext.findRenderObject();
          if (renderObject is! RenderBox) {
            return;
          }
          final double handle = scaleDimension(splitPaneContext, _resizeHandleLogicalHeight);
          final double availableHeight = renderObject.size.height - handle;
          if (availableHeight <= 1) {
            return;
          }
          final double deltaY = details.globalPosition.dy - _splitDragStartGlobalY!;
          final double previewMin = _previewHeightMin(availableHeight);
          final double previewMax = _previewHeightMax(availableHeight);
          final double nextPreviewHeight = (_splitDragStartPreviewHeight! + deltaY).clamp(previewMin, previewMax);
          setState(() {
            _previewPanelHeightPx = nextPreviewHeight;
          });
        },
        onVerticalDragEnd: (_) {
          _splitDragStartGlobalY = null;
          _splitDragStartPreviewHeight = null;
        },
        onVerticalDragCancel: () {
          _splitDragStartGlobalY = null;
          _splitDragStartPreviewHeight = null;
        },
        child: SizedBox(
          height: handleHeight,
          child: Center(
            child: Icon(Icons.drag_handle, size: iconSize, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
