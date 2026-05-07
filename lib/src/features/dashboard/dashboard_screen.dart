import "dart:io";

import "package:flutter/material.dart";
import "package:path/path.dart" as p;

import "../../media/master_media_file.dart";
import "../playout/clip_player_view.dart";
import "dashboard_view_model.dart";

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.viewModel,
    required this.onPlayMedia,
    this.scrollController,
  });

  final DashboardViewModel viewModel;
  final void Function(MasterMediaFile mediaFile) onPlayMedia;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("dashboard"),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _WorkspaceHeader(viewModel: viewModel),
                const SizedBox(height: 16),
                Expanded(
                  child: _BodyState(
                    viewModel: viewModel,
                    isLoading: viewModel.isLoading,
                    workspacePath: viewModel.workspacePath,
                    mediaFiles: viewModel.mediaFiles,
                    onPlayMedia: onPlayMedia,
                    scrollController: scrollController,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            viewModel.workspacePath == null
                ? "No workspace selected."
                : "Workspace: ${viewModel.workspacePath}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: viewModel.isLoading ? null : viewModel.pickAndSetWorkspace,
          child: Text(
            viewModel.workspacePath == null ? "Select Workspace" : "Change Workspace",
          ),
        ),
      ],
    );
  }
}

class _BodyState extends StatelessWidget {
  const _BodyState({
    required this.viewModel,
    required this.isLoading,
    required this.workspacePath,
    required this.mediaFiles,
    required this.onPlayMedia,
    this.scrollController,
  });

  final DashboardViewModel viewModel;
  final bool isLoading;
  final String? workspacePath;
  final List<MasterMediaFile> mediaFiles;
  final void Function(MasterMediaFile mediaFile) onPlayMedia;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (workspacePath == null) {
      return const Center(
        child: Text("Select a workspace to start ingesting media."),
      );
    }
    final List<MasterMediaFile> visibleMediaFiles = viewModel.visibleMediaFiles;
    if (mediaFiles.isEmpty) {
      return const Center(
        child: Text("No supported media files found in this workspace."),
      );
    }
    return Row(
      children: <Widget>[
        Expanded(
          flex: 4,
          child: _FileListPanel(
            viewModel: viewModel,
            workspacePath: workspacePath!,
            mediaFiles: visibleMediaFiles,
            scrollController: scrollController,
            onPlayMedia: onPlayMedia,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 6,
          child: Column(
            children: <Widget>[
              Expanded(
                child: _PreviewPanel(
                  selectedMedia: viewModel.selectedMedia,
                  onPlayMedia: onPlayMedia,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _TagPanel(
                  viewModel: viewModel,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileListPanel extends StatelessWidget {
  const _FileListPanel({
    required this.viewModel,
    required this.workspacePath,
    required this.mediaFiles,
    required this.onPlayMedia,
    this.scrollController,
  });

  final DashboardViewModel viewModel;
  final String workspacePath;
  final List<MasterMediaFile> mediaFiles;
  final void Function(MasterMediaFile mediaFile) onPlayMedia;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: <Widget>[
                const Text("Files"),
                const SizedBox(width: 8),
                if (viewModel.activeTagFilter != null)
                  InputChip(
                    label: Text("Filter: ${viewModel.activeTagFilter}"),
                    onDeleted: () => viewModel.toggleTagFilter(viewModel.activeTagFilter!),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              itemCount: mediaFiles.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final MasterMediaFile item = mediaFiles[index];
                final String relativePath = p.relative(item.filePath, from: workspacePath);
                final bool isSelected = viewModel.selectedMediaId == item.id;
                final List<String> tags = viewModel.tagsForMedia(item.id).toList()
                  ..sort((String a, String b) => a.compareTo(b));

                return ListTile(
                  selected: isSelected,
                  selectedTileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  leading: _ThumbnailPreview(videoPath: item.filePath),
                  title: Text(item.fileName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(relativePath, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: tags.isEmpty
                            ? <Widget>[const Text("No tags")]
                            : tags
                                .map(
                                  (String tag) => ActionChip(
                                    label: Text(tag),
                                    onPressed: () => viewModel.toggleTagFilter(tag),
                                  ),
                                )
                                .toList(),
                      ),
                    ],
                  ),
                  onTap: () => viewModel.selectMedia(item.id),
                  trailing: IconButton(
                    tooltip: "Play",
                    onPressed: () => onPlayMedia(item),
                    icon: const Icon(Icons.play_arrow),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.selectedMedia,
    required this.onPlayMedia,
  });

  final MasterMediaFile? selectedMedia;
  final void Function(MasterMediaFile mediaFile) onPlayMedia;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("Preview"),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.black,
                  child: selectedMedia == null
                      ? const Center(
                          child: Text(
                            "Select a file from the list.",
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ClipPlayerView(
                          filePath: selectedMedia!.filePath,
                          autoPlay: false,
                          showControls: true,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                OutlinedButton(onPressed: () {}, child: const Text("Mark In")),
                OutlinedButton(onPressed: () {}, child: const Text("Mark Out")),
                OutlinedButton(onPressed: () {}, child: const Text("Save Clip")),
                FilledButton.icon(
                  onPressed: selectedMedia == null ? null : () => onPlayMedia(selectedMedia!),
                  icon: const Icon(Icons.fullscreen),
                  label: const Text("Playout"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TagPanel extends StatefulWidget {
  const _TagPanel({
    required this.viewModel,
  });

  final DashboardViewModel viewModel;

  @override
  State<_TagPanel> createState() => _TagPanelState();
}

class _TagPanelState extends State<_TagPanel> {
  late final TextEditingController _tagController;

  @override
  void initState() {
    super.initState();
    _tagController = TextEditingController();
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MasterMediaFile? selectedMedia = widget.viewModel.selectedMedia;
    final List<String> selectedTags = selectedMedia == null
        ? <String>[]
        : widget.viewModel.tagsForMedia(selectedMedia.id).toList()
          ..sort((String a, String b) => a.compareTo(b));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("Tags"),
            const SizedBox(height: 12),
            if (selectedMedia == null)
              const Expanded(
                child: Center(
                  child: Text("Select a file to manage tags."),
                ),
              )
            else ...<Widget>[
              Text(
                selectedMedia.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      decoration: const InputDecoration(
                        labelText: "Add Tag",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submitTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submitTag,
                    child: const Text("Add"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selectedTags
                        .map(
                          (String tag) => InputChip(
                            label: Text(tag),
                            onDeleted: () => widget.viewModel.removeTagFromSelectedMedia(tag),
                            onPressed: () => widget.viewModel.toggleTagFilter(tag),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _submitTag() {
    final String tag = _tagController.text.trim();
    if (tag.isEmpty) {
      return;
    }
    widget.viewModel.addTagToSelectedMedia(tag);
    _tagController.clear();
  }
}

class _ThumbnailPreview extends StatelessWidget {
  const _ThumbnailPreview({
    required this.videoPath,
  });

  final String videoPath;

  @override
  Widget build(BuildContext context) {
    final String thumbnailPath = "$videoPath.thumb.jpg";
    final File thumbFile = File(thumbnailPath);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 72,
        height: 40,
        child: thumbFile.existsSync()
            ? Image.file(
                thumbFile,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.movie, size: 18),
    );
  }
}
