import "package:flutter/material.dart";
import "package:path/path.dart" as p;

import "../../media/master_media_file.dart";
import "dashboard_view_model.dart";

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.viewModel,
  });

  final DashboardViewModel viewModel;

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
                    isLoading: viewModel.isLoading,
                    workspacePath: viewModel.workspacePath,
                    mediaFiles: viewModel.mediaFiles,
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
    required this.isLoading,
    required this.workspacePath,
    required this.mediaFiles,
  });

  final bool isLoading;
  final String? workspacePath;
  final List<MasterMediaFile> mediaFiles;

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
    if (mediaFiles.isEmpty) {
      return const Center(
        child: Text("No supported media files found in this workspace."),
      );
    }
    return ListView.separated(
      itemCount: mediaFiles.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final MasterMediaFile item = mediaFiles[index];
        final String relativePath = p.relative(item.filePath, from: workspacePath!);
        final DateTime modifiedAt =
            DateTime.fromMillisecondsSinceEpoch(item.modifiedAtMs);

        return ListTile(
          title: Text(item.fileName),
          subtitle: Text(relativePath),
          trailing: Text(
            "${modifiedAt.year}-${modifiedAt.month.toString().padLeft(2, "0")}-${modifiedAt.day.toString().padLeft(2, "0")}",
          ),
        );
      },
    );
  }
}
