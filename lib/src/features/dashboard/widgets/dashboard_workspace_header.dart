import "package:flutter/material.dart";
import "package:provider/provider.dart";

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
    return Row(
      children: <Widget>[
        Tooltip(
          message: "Open workspace",
          child: IconButton(
            onPressed: viewModel.isLoading ? null : viewModel.pickAndSetWorkspace,
            icon: const Icon(Icons.folder_open),
          ),
        ),
        const SizedBox(width: 8),
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
        if (obsConnectionHealthy != null)
          Tooltip(
            message: obsConnectionHealthy!
                ? "OBS: connected${obsLastSuccessfulPingHms == null ? "" : " (last success ${obsLastSuccessfulPingHms!})"}"
                : "OBS: disconnected (retrying)${obsLastSuccessfulPingHms == null ? "" : " (last success ${obsLastSuccessfulPingHms!})"}",
            child: Icon(
              Icons.settings_input_antenna,
              size: 20,
              color: obsConnectionHealthy! ? Colors.green : Colors.red,
            ),
          ),
        if (obsConnectionHealthy != null) const SizedBox(width: 8),
        Tooltip(
          message: "Workspace settings",
          child: IconButton(
            onPressed: onWorkspaceSettingsRequested,
            icon: const Icon(Icons.settings),
          ),
        ),
      ],
    );
  }
}
