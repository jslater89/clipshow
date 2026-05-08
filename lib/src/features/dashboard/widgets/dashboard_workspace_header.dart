import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";

class DashboardWorkspaceHeader extends StatelessWidget {
  const DashboardWorkspaceHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
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
            viewModel.workspacePath == null
                ? "Select Workspace"
                : "Change Workspace",
          ),
        ),
      ],
    );
  }
}
