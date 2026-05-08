import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_widgets.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.viewModel,
    required this.onPlayClip,
    required this.onWorkspaceSettingsRequested,
    required this.obsConnectionHealthy,
    required this.obsLastSuccessfulPingHms,
    this.scrollController,
  });

  final DashboardViewModel viewModel;
  final void Function(PlayoutClip clip) onPlayClip;
  final VoidCallback onWorkspaceSettingsRequested;
  final bool? obsConnectionHealthy;
  final String? obsLastSuccessfulPingHms;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DashboardViewModel>.value(
      value: viewModel,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DashboardWorkspaceHeader(
                onWorkspaceSettingsRequested: onWorkspaceSettingsRequested,
                obsConnectionHealthy: obsConnectionHealthy,
                obsLastSuccessfulPingHms: obsLastSuccessfulPingHms,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: DashboardBody(
                  onPlayClip: onPlayClip,
                  scrollController: scrollController,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
