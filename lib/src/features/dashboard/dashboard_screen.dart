import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_widgets.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.viewModel,
    required this.onPlayClip,
    required this.onRecordClip,
    required this.onWorkspaceSettingsRequested,
    required this.obsConnectionHealthy,
    required this.obsLastSuccessfulPingHms,
    this.scrollController,
  });

  final DashboardViewModel viewModel;
  final void Function(PlayoutClip clip) onPlayClip;
  final void Function(PlayoutClip clip) onRecordClip;
  final VoidCallback onWorkspaceSettingsRequested;
  final bool? obsConnectionHealthy;
  final String? obsLastSuccessfulPingHms;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final double shellPad = scaleDimension(context, 16);
    final double headerBodyGap = scaleDimension(context, 16);
    return ChangeNotifierProvider<DashboardViewModel>.value(
      value: viewModel,
      child: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(shellPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DashboardWorkspaceHeader(
                onWorkspaceSettingsRequested: onWorkspaceSettingsRequested,
                obsConnectionHealthy: obsConnectionHealthy,
                obsLastSuccessfulPingHms: obsLastSuccessfulPingHms,
              ),
              SizedBox(height: headerBodyGap),
              Expanded(
                child: DashboardBody(
                  onPlayClip: onPlayClip,
                  onRecordClip: onRecordClip,
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
