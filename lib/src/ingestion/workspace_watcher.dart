import "dart:async";

import "package:watcher/watcher.dart";

class WorkspaceWatcher {
  StreamSubscription<WatchEvent>? _subscription;
  final StreamController<WatchEvent> _eventsController =
      StreamController<WatchEvent>.broadcast();

  Stream<WatchEvent> get events => _eventsController.stream;

  void start(String rootPath) {
    stop();
    final DirectoryWatcher watcher = DirectoryWatcher(rootPath);
    _subscription = watcher.events.listen(_eventsController.add);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _eventsController.close();
  }
}
