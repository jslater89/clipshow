import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_screen.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/ingestion/ingestion_service.dart";
import "package:obs_clipshow/src/ingestion/workspace_watcher.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/workspace/workspace_preferences.dart";
import "package:obs_clipshow/src/workspace/workspace_service.dart";
import "package:obs_clipshow/src/data/app_database.dart";

void main() {
  DashboardViewModel createViewModel() {
    return DashboardViewModel(
      workspaceService: WorkspaceService(
        appDatabase: AppDatabase(),
        workspacePreferences: WorkspacePreferences(),
      ),
      ingestionService: IngestionService(workspaceWatcher: WorkspaceWatcher()),
    );
  }

  testWidgets("shows empty state when no workspace is selected", (
    WidgetTester tester,
  ) async {
    final DashboardViewModel viewModel = createViewModel();
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          viewModel: viewModel,
          onPlayClip: (_) {},
          onWorkspaceSettingsRequested: () {},
          obsConnectionHealthy: true,
          obsLastSuccessfulPingHms: "15:00:00",
        ),
      ),
    );

    expect(
      find.text("Select a workspace to start ingesting media."),
      findsOneWidget,
    );
  });

  testWidgets("shows media list when files are available", (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final DashboardViewModel viewModel = createViewModel();
    addTearDown(viewModel.dispose);
    viewModel.setStateForTest(
      workspacePath: "/tmp/workspace",
      mediaFiles: const <MasterMediaFile>[
        MasterMediaFile(
          id: 1,
          filePath: "round1/highlight.mp4",
          fileName: "highlight.mp4",
          fileSizeBytes: 1024,
          modifiedAtMs: 1000,
          createdAtMs: 1000,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          viewModel: viewModel,
          onPlayClip: (_) {},
          onWorkspaceSettingsRequested: () {},
          obsConnectionHealthy: true,
          obsLastSuccessfulPingHms: "15:00:00",
        ),
      ),
    );

    expect(find.text("highlight.mp4"), findsOneWidget);
    expect(find.text("round1/highlight.mp4"), findsOneWidget);
  });
}
