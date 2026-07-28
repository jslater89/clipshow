import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/util/reveal_file_in_folder.dart";

class DashboardWorkspaceHeader extends StatelessWidget {
  const DashboardWorkspaceHeader({
    super.key,
    required this.onWorkspaceSettingsRequested,
    required this.obsConnectionHealthy,
    required this.obsLastSuccessfulPingHms,
  });

  final VoidCallback onWorkspaceSettingsRequested;
  final bool? obsConnectionHealthy;
  final String? obsLastSuccessfulPingHms;

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final double gap8 = scaleDimension(context, 8);
    final double gap12 = scaleDimension(context, 12);
    final double antennaIconSize = scaleDimension(context, 20);
    final String? workspacePath = viewModel.workspacePath;
    return Row(
      children: <Widget>[
        Tooltip(
          message: "Open workspace",
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            child: IconButton(
              onPressed: viewModel.isLoading
                  ? null
                  : viewModel.pickAndSetWorkspace,
              icon: const Icon(Icons.folder_open),
            ),
          ),
        ),
        SizedBox(width: gap8),
        Expanded(
          child: Text(
            workspacePath == null
                ? "No workspace selected."
                : "Workspace: $workspacePath",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (workspacePath != null) ...<Widget>[
          SizedBox(width: gap8),
          Tooltip(
            message: "Reveal on filesystem",
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              child: IconButton(
                onPressed: viewModel.isLoading
                    ? null
                    : () {
                        unawaited(
                          _revealWorkspaceOnFilesystem(context, workspacePath),
                        );
                      },
                icon: const Icon(Icons.folder_open_outlined),
              ),
            ),
          ),
        ],
        SizedBox(width: gap12),
        if (obsConnectionHealthy != null)
          Tooltip(
            message: obsConnectionHealthy!
                ? "OBS: connected${obsLastSuccessfulPingHms == null ? "" : " (last success ${obsLastSuccessfulPingHms!})"}"
                : "OBS: disconnected (retrying)${obsLastSuccessfulPingHms == null ? "" : " (last success ${obsLastSuccessfulPingHms!})"}",
            child: Icon(
              Icons.settings_input_antenna,
              size: antennaIconSize,
              color: obsConnectionHealthy! ? Colors.green : Colors.red,
            ),
          ),
        if (obsConnectionHealthy != null) SizedBox(width: gap8),
        Tooltip(
          message: "Workspace settings",
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            child: IconButton(
              onPressed: onWorkspaceSettingsRequested,
              icon: const Icon(Icons.settings),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _revealWorkspaceOnFilesystem(
  BuildContext context,
  String workspacePath,
) async {
  try {
    await revealFileInFolder(workspacePath);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not reveal on filesystem: $e")),
      );
    }
  }
}
