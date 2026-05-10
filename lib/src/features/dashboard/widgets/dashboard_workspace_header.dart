import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";

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
            viewModel.workspacePath == null
                ? "No workspace selected."
                : "Workspace: ${viewModel.workspacePath}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
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
