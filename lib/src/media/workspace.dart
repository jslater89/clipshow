import "package:path/path.dart" as p;

class Workspace {
  const Workspace({required this.rootPath});

  final String rootPath;

  String get databasePath => p.join(rootPath, "obs_clipshow.db");
}
