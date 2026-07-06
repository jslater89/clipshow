import "package:flutter/foundation.dart";

/// Lifecycle of a single [OsgBakeQueueTask].
enum OsgBakeQueueTaskStatus { pending, running, completed, failed, cancelled }

int _nextTaskSequence = 1;

/// Session-scoped, monotonically increasing id for bake queue tasks. Queue
/// tasks are not persisted across app restarts, so a simple in-memory counter
/// (unlike [OsgBakeRecipe]'s id, which is saved) is sufficient.
String nextBakeQueueTaskId() => "bake_task_${_nextTaskSequence++}";

/// One media item queued (or run) against a recipe.
///
/// Job identifiers ([mediaStableKey], [recipeId]) are resolved against live
/// workspace state at run time, so tag/annotation edits made while a task
/// waits in the queue are reflected in the bake; [mediaDisplayName] and
/// [recipeName] are captured at enqueue time purely for display.
@immutable
class OsgBakeQueueTask {
  const OsgBakeQueueTask({
    required this.id,
    required this.mediaStableKey,
    required this.mediaDisplayName,
    required this.recipeId,
    required this.recipeName,
    required this.status,
    required this.enqueuedAt,
    this.destPath,
    this.errorMessage,
    this.completedAt,
  });

  final String id;
  final String mediaStableKey;
  final String mediaDisplayName;
  final int recipeId;
  final String recipeName;
  final OsgBakeQueueTaskStatus status;
  final DateTime enqueuedAt;

  /// Set once [status] is [OsgBakeQueueTaskStatus.completed].
  final String? destPath;

  /// Set once [status] is [OsgBakeQueueTaskStatus.failed] (or, rarely,
  /// carries the cancellation message for [OsgBakeQueueTaskStatus.cancelled]).
  final String? errorMessage;

  /// Set once [status] leaves [OsgBakeQueueTaskStatus.pending]/[OsgBakeQueueTaskStatus.running].
  final DateTime? completedAt;

  OsgBakeQueueTask copyWith({
    OsgBakeQueueTaskStatus? status,
    String? destPath,
    String? errorMessage,
    DateTime? completedAt,
  }) {
    return OsgBakeQueueTask(
      id: id,
      mediaStableKey: mediaStableKey,
      mediaDisplayName: mediaDisplayName,
      recipeId: recipeId,
      recipeName: recipeName,
      status: status ?? this.status,
      enqueuedAt: enqueuedAt,
      destPath: destPath ?? this.destPath,
      errorMessage: errorMessage ?? this.errorMessage,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
