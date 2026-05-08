import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/data/app_database.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/ingestion/ingestion_service.dart";
import "package:obs_clipshow/src/ingestion/workspace_watcher.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/workspace/workspace_preferences.dart";
import "package:obs_clipshow/src/workspace/workspace_service.dart";

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

  MediaListItem masterItem({required int id, required String name}) {
    return MediaListItem.master(
      MasterMediaFile(
        id: id,
        filePath: "/tmp/$name.mp4",
        fileName: "$name.mp4",
        fileSizeBytes: 1024,
        modifiedAtMs: 1000 + id,
        createdAtMs: 1000 + id,
      ),
    );
  }

  group("DashboardViewModel filters", () {
    test("applies AND semantics for active tag filters", () {
      final DashboardViewModel viewModel = createViewModel();
      addTearDown(viewModel.dispose);

      final MediaListItem first = masterItem(id: 1, name: "first");
      final MediaListItem second = masterItem(id: 2, name: "second");

      viewModel.setItemsForTest(
        items: <MediaListItem>[first, second],
        tagsByItemKey: <String, Set<String>>{
          first.stableKey: <String>{"Day 3", "Stage 5"},
          second.stableKey: <String>{"Day 3"},
        },
      );
      viewModel.toggleTagFilter("Day 3");
      viewModel.toggleTagFilter("Stage 5");

      expect(viewModel.visibleItems, hasLength(1));
      expect(viewModel.visibleItems.single.stableKey, first.stableKey);
    });

    test("shows only untagged items when untagged filter is enabled", () {
      final DashboardViewModel viewModel = createViewModel();
      addTearDown(viewModel.dispose);

      final MediaListItem tagged = masterItem(id: 1, name: "tagged");
      final MediaListItem untagged = masterItem(id: 2, name: "untagged");
      viewModel.setItemsForTest(
        items: <MediaListItem>[tagged, untagged],
        tagsByItemKey: <String, Set<String>>{
          tagged.stableKey: <String>{"Match Day"},
        },
      );
      viewModel.setShowUntaggedOnly(true);

      expect(viewModel.visibleItems, hasLength(1));
      expect(viewModel.visibleItems.single.stableKey, untagged.stableKey);
    });

    test("keeps list unchanged while tag search query is being typed", () {
      final DashboardViewModel viewModel = createViewModel();
      addTearDown(viewModel.dispose);

      final MediaListItem stage = masterItem(id: 1, name: "stage");
      final MediaListItem broll = masterItem(id: 2, name: "broll");
      viewModel.setItemsForTest(
        items: <MediaListItem>[stage, broll],
        tagsByItemKey: <String, Set<String>>{
          stage.stableKey: <String>{"Stage 5"},
          broll.stableKey: <String>{"B Roll"},
        },
      );
      viewModel.setTagSearchQuery("stage");

      expect(viewModel.visibleItems, hasLength(2));
    });
  });
}
