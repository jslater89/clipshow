import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/bake/osg_bake_queue_models.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/obs/playout_record_path_utils.dart";
import "package:obs_clipshow/src/util/reveal_file_in_folder.dart";

/// Bake Queue tab: start/pause the runner, the currently running task, and
/// the pending and finished task lists.
class DashboardBakeQueuePanel extends StatelessWidget {
  const DashboardBakeQueuePanel({super.key});

  String _timeLabel(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, "0");
    return "${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}";
  }

  Future<void> _openExportFolder(
    BuildContext context,
    DashboardViewModel viewModel,
  ) async {
    final String? workspacePath = viewModel.workspacePath;
    if (workspacePath == null) {
      return;
    }
    final String exportDir = PlayoutRecordPathUtils.normalizedOutputDir(
      workspaceAbsolute: workspacePath,
      settings: viewModel.playoutRecordPathsSettings,
    );
    try {
      await Directory(exportDir).create(recursive: true);
      await revealFileInFolder(exportDir);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not open export folder: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final ThemeData theme = Theme.of(context);
    final double pad12 = scaleDimension(context, 12);
    final double gap8 = scaleDimension(context, 8);
    final double gap16 = scaleDimension(context, 16);

    final OsgBakeQueueTask? running = viewModel.bakeQueueRunningTask;
    final List<OsgBakeQueueTask> pending = viewModel.bakeQueuePending;
    final List<OsgBakeQueueTask> finished = viewModel.bakeQueueFinished;
    final bool paused = viewModel.bakeQueuePaused;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(pad12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text("Bake Queue", style: theme.textTheme.titleMedium),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(
                      _openExportFolder(context, viewModel),
                    ),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text("Export Folder"),
                  ),
                  SizedBox(width: gap8),
                  FilledButton.tonalIcon(
                    onPressed: paused
                        ? viewModel.startBakeQueue
                        : viewModel.pauseBakeQueue,
                    icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                    label: Text(paused ? "Start" : "Pause"),
                  ),
                ],
              ),
              SizedBox(height: gap16),
              Text("Running", style: theme.textTheme.titleSmall),
              SizedBox(height: gap8),
              if (running == null)
                _emptyLabel(theme, "Nothing baking right now.")
              else
                _runningBakeRow(theme, viewModel, running, gap8),
              SizedBox(height: gap16),
              Text(
                "Pending (${pending.length})",
                style: theme.textTheme.titleSmall,
              ),
              SizedBox(height: gap8),
              if (pending.isEmpty)
                _emptyLabel(theme, "No pending bakes.")
              else
                Column(
                  children: pending
                      .map(
                        (OsgBakeQueueTask task) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(task.mediaDisplayName),
                          subtitle: Text(
                            "${task.recipeName} \u00b7 queued ${_timeLabel(task.enqueuedAt)}",
                          ),
                          trailing: IconButton(
                            tooltip: "Remove",
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                viewModel.removePendingBakeTask(task.id),
                          ),
                        ),
                      )
                      .toList(),
                ),
              SizedBox(height: gap16),
              Row(
                children: <Widget>[
                  Text("Finished", style: theme.textTheme.titleSmall),
                  const Spacer(),
                  if (finished.isNotEmpty)
                    TextButton(
                      onPressed: viewModel.clearAllFinishedBakeTasks,
                      child: const Text("Clear All"),
                    ),
                ],
              ),
              SizedBox(height: gap8),
              if (finished.isEmpty)
                _emptyLabel(theme, "No finished bakes yet.")
              else
                Column(
                  children: finished
                      .map(
                        (OsgBakeQueueTask task) =>
                            _finishedRow(context, viewModel, theme, task),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyLabel(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ),
  );

  Widget _runningBakeRow(
    ThemeData theme,
    DashboardViewModel viewModel,
    OsgBakeQueueTask running,
    double gap8,
  ) {
    final double? progress = viewModel.bakeQueueProgress;
    final String pctLabel = progress == null
        ? "Starting\u2026"
        : "${(progress * 100).floor()}%";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(running.mediaDisplayName),
          subtitle: Text("${running.recipeName} \u00b7 $pctLabel"),
          trailing: TextButton(
            onPressed: viewModel.requestBakeCancel,
            child: const Text("Cancel"),
          ),
        ),
        LinearProgressIndicator(
          value: progress,
          minHeight: 4,
        ),
        SizedBox(height: gap8),
      ],
    );
  }

  Widget _finishedRow(
    BuildContext context,
    DashboardViewModel viewModel,
    ThemeData theme,
    OsgBakeQueueTask task,
  ) {
    final String statusLabel = switch (task.status) {
      OsgBakeQueueTaskStatus.completed => "Done",
      OsgBakeQueueTaskStatus.failed => "Failed",
      OsgBakeQueueTaskStatus.cancelled => "Cancelled",
      OsgBakeQueueTaskStatus.pending || OsgBakeQueueTaskStatus.running => "",
    };
    final String subtitle = task.status == OsgBakeQueueTaskStatus.completed
        ? "${task.recipeName} \u00b7 $statusLabel"
        : "${task.recipeName} \u00b7 $statusLabel"
              "${task.errorMessage == null ? "" : ": ${task.errorMessage}"}";
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(task.mediaDisplayName),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (task.status == OsgBakeQueueTaskStatus.completed &&
              task.destPath != null)
            IconButton(
              tooltip: "Reveal",
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () {
                final String destPath = task.destPath!;
                unawaited(() async {
                  try {
                    await revealFileInFolder(destPath);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Could not open file manager: $e"),
                        ),
                      );
                    }
                  }
                }());
              },
            ),
          IconButton(
            tooltip: "Clear",
            icon: const Icon(Icons.close),
            onPressed: () => viewModel.clearFinishedBakeTask(task.id),
          ),
        ],
      ),
    );
  }
}
