import "package:flutter/material.dart";

import "../features/dashboard/dashboard_screen.dart";
import "../features/dashboard/dashboard_view_model.dart";

class ObsClipshowApp extends StatefulWidget {
  const ObsClipshowApp({super.key});

  @override
  State<ObsClipshowApp> createState() => _ObsClipshowAppState();
}

class _ObsClipshowAppState extends State<ObsClipshowApp> {
  late final DashboardViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel.create();
    _viewModel.initialize();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Vanalyst Playout",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: DashboardScreen(viewModel: _viewModel),
    );
  }
}
