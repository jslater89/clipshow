import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/bake/osg_bake_queue_models.dart";
import "package:obs_clipshow/src/bake/osg_bake_service.dart";
import "package:obs_clipshow/src/data/app_database.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/ingestion/ingestion_service.dart";
import "package:obs_clipshow/src/ingestion/workspace_watcher.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/workspace/workspace_preferences.dart";
import "package:obs_clipshow/src/workspace/workspace_service.dart";

/// Lets a chain of already-resolved bake tasks drain through the queue's
/// pump loop (each hop is a microtask/short-timer boundary, not real work,
/// since no workspace is configured in these tests).
Future<void> _drainQueue() async {
  for (int i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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
        filePath: "$name.mp4",
        fileName: "$name.mp4",
        fileSizeBytes: 1024,
        modifiedAtMs: 1000 + id,
        createdAtMs: 1000 + id,
      ),
    );
  }

  OsgBakeRecipe recipe({required int id, required String name}) {
    return OsgBakeRecipe(
      id: id,
      name: name,
      cues: const <OsgBakeCue>[
        OsgBakeCue(
          slot: OsgPresetSlot.preset1,
          start: OsgBakeAnchor.clipStart(),
          end: OsgBakeAnchor.clipEnd(),
        ),
      ],
    );
  }

  group("DashboardViewModel bake queue", () {
    // No workspace is configured in any of these tests, so every task fails
    // fast (synchronously, before any real bake I/O) with "No workspace
    // open." This exercises the queue's plumbing without shelling out to
    // ffmpeg, while still covering: FIFO order, pause/resume, "now" jumping
    // the line, and clearing finished tasks.

    test("enqueued task runs and lands in the finished list", () async {
      final DashboardViewModel viewModel = createViewModel();
      addTearDown(viewModel.dispose);
      final MediaListItem item = masterItem(id: 1, name: "clip_a");

      viewModel.enqueueBakeJob(item, recipe(id: 1, name: "Recipe A"));
      await _drainQueue();

      expect(viewModel.bakeQueuePending, isEmpty);
      expect(viewModel.bakeQueueRunningTask, isNull);
      expect(viewModel.bakeQueueFinished, hasLength(1));
      final OsgBakeQueueTask finished = viewModel.bakeQueueFinished.single;
      expect(finished.status, OsgBakeQueueTaskStatus.failed);
      expect(finished.mediaDisplayName, item.displayName);
      expect(finished.recipeName, "Recipe A");
    });

    test("multiple enqueued tasks run one at a time in FIFO order", () async {
      final DashboardViewModel viewModel = createViewModel();
      addTearDown(viewModel.dispose);
      final MediaListItem a = masterItem(id: 1, name: "clip_a");
      final MediaListItem b = masterItem(id: 2, name: "clip_b");

      viewModel.enqueueBakeJob(a, recipe(id: 1, name: "Recipe A"));
      // Enqueued while the runner is already active with task A; must wait.
      expect(viewModel.bakeQueueRunningTask, isNotNull);
      viewModel.enqueueBakeJob(b, recipe(id: 2, name: "Recipe B"));
      expect(viewModel.bakeQueuePending, hasLength(1));

      await _drainQueue();

      expect(viewModel.bakeQueueFinished, hasLength(2));
      // Finished list is newest-first, so B (which ran second) is at index 0.
      expect(viewModel.bakeQueueFinished[0].mediaDisplayName, b.displayName);
      expect(viewModel.bakeQueueFinished[1].mediaDisplayName, a.displayName);
    });

    test("pausing stops the queue after the current task finishes", () async {
      final DashboardViewModel viewModel = createViewModel();
      addTearDown(viewModel.dispose);
      final MediaListItem a = masterItem(id: 1, name: "clip_a");
      final MediaListItem b = masterItem(id: 2, name: "clip_b");

      viewModel.enqueueBakeJob(a, recipe(id: 1, name: "Recipe A"));
      viewModel.pauseBakeQueue();
      viewModel.enqueueBakeJob(b, recipe(id: 2, name: "Recipe B"));

      await _drainQueue();

      // A was already running when paused, so it completes; B stays pending.
      expect(viewModel.bakeQueueFinished, hasLength(1));
      expect(viewModel.bakeQueueFinished.single.mediaDisplayName, a.displayName);
      expect(viewModel.bakeQueuePending, hasLength(1));
      expect(viewModel.bakeQueuePending.single.mediaDisplayName, b.displayName);
      expect(viewModel.bakeQueueRunnerActive, isFalse);

      viewModel.startBakeQueue();
      await _drainQueue();

      expect(viewModel.bakeQueuePending, isEmpty);
      expect(viewModel.bakeQueueFinished, hasLength(2));
    });

    test(
      "bakeItemNow jumps ahead of pending work and resolves its own future",
      () async {
        final DashboardViewModel viewModel = createViewModel();
        addTearDown(viewModel.dispose);
        final MediaListItem a = masterItem(id: 1, name: "clip_a");
        final MediaListItem b = masterItem(id: 2, name: "clip_b");
        final MediaListItem c = masterItem(id: 3, name: "clip_c");

        // A starts running immediately; B waits behind it.
        viewModel.enqueueBakeJob(a, recipe(id: 1, name: "Recipe A"));
        viewModel.enqueueBakeJob(b, recipe(id: 2, name: "Recipe B"));
        expect(viewModel.bakeQueuePending.single.mediaDisplayName, b.displayName);

        final ({String taskId, Future<OsgBakeResult> result}) nowJob =
            viewModel.bakeItemNow(c, recipe(id: 3, name: "Recipe C"));
        // C is inserted ahead of B.
        expect(viewModel.bakeQueuePending.first.mediaDisplayName, c.displayName);
        // A is still running, not C, so the returned task id must not match yet.
        expect(viewModel.bakeQueueRunningTask?.id, isNot(nowJob.taskId));

        final OsgBakeResult nowResult = await nowJob.result;
        expect(nowResult.errorMessage, isNotNull);

        await _drainQueue();

        expect(viewModel.bakeQueuePending, isEmpty);
        expect(viewModel.bakeQueueFinished, hasLength(3));
        // Run order was A, C, B; finished list is newest-first.
        expect(viewModel.bakeQueueFinished[0].mediaDisplayName, b.displayName);
        expect(viewModel.bakeQueueFinished[1].mediaDisplayName, c.displayName);
        expect(viewModel.bakeQueueFinished[2].mediaDisplayName, a.displayName);
      },
    );

    test("removing a pending task resolves its now-waiter", () async {
      final DashboardViewModel viewModel = createViewModel();
      addTearDown(viewModel.dispose);
      final MediaListItem a = masterItem(id: 1, name: "clip_a");
      final MediaListItem b = masterItem(id: 2, name: "clip_b");

      viewModel.enqueueBakeJob(a, recipe(id: 1, name: "Recipe A"));
      final ({String taskId, Future<OsgBakeResult> result}) nowJob = viewModel
          .bakeItemNow(b, recipe(id: 2, name: "Recipe B"));
      final String pendingId = viewModel.bakeQueuePending.single.id;
      expect(pendingId, nowJob.taskId);

      viewModel.removePendingBakeTask(pendingId);
      final OsgBakeResult removedResult = await nowJob.result;

      expect(removedResult.errorMessage, "Bake removed from queue.");
      expect(viewModel.bakeQueuePending, isEmpty);

      await _drainQueue();
      // Only A ran; B was removed before the runner reached it.
      expect(viewModel.bakeQueueFinished, hasLength(1));
      expect(viewModel.bakeQueueFinished.single.mediaDisplayName, a.displayName);
    });

    test("clearFinishedBakeTask and clearAllFinishedBakeTasks", () async {
      final DashboardViewModel viewModel = createViewModel();
      addTearDown(viewModel.dispose);
      final MediaListItem a = masterItem(id: 1, name: "clip_a");
      final MediaListItem b = masterItem(id: 2, name: "clip_b");

      viewModel.enqueueBakeJob(a, recipe(id: 1, name: "Recipe A"));
      viewModel.enqueueBakeJob(b, recipe(id: 2, name: "Recipe B"));
      await _drainQueue();

      expect(viewModel.bakeQueueFinished, hasLength(2));
      final String firstId = viewModel.bakeQueueFinished.first.id;
      viewModel.clearFinishedBakeTask(firstId);
      expect(viewModel.bakeQueueFinished, hasLength(1));

      viewModel.clearAllFinishedBakeTasks();
      expect(viewModel.bakeQueueFinished, isEmpty);
    });
  });
}
