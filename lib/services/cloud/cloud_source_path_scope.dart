import 'package:kanyingyin/modules/cloud/cloud_source.dart';

abstract final class CloudSourcePathScope {
  static String normalizePath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');
    if (normalized.isEmpty) return '/';
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool containsPath({
    required Iterable<String> roots,
    required String path,
  }) {
    if (path.trim().isEmpty) return false;
    final normalizedPath = normalizePath(path);
    final normalizedRoots = roots
        .where((root) => root.trim().isNotEmpty)
        .map(normalizePath)
        .toSet();
    if (normalizedRoots.isEmpty) return false;
    return normalizedRoots.any(
      (root) =>
          root == '/' ||
          normalizedPath == root ||
          normalizedPath.startsWith('$root/'),
    );
  }

  static bool containsSourcePath(CloudSource source, String path) =>
      containsPath(
        roots: source.remoteRoots.map((root) => root.path),
        path: path,
      );

  static bool hasRootSelectionChanged(
    CloudSource? previous,
    CloudSource current,
  ) {
    if (previous == null) return current.remoteRoots.isNotEmpty;
    if (previous.type != current.type) return true;
    final previousRoots = _rootIdentities(previous);
    final currentRoots = _rootIdentities(current);
    return previousRoots.length != currentRoots.length ||
        !previousRoots.containsAll(currentRoots);
  }

  static Set<(String, String?)> _rootIdentities(CloudSource source) =>
      source.remoteRoots.map((root) {
        final path = normalizePath(root.path);
        if (source.type == CloudSourceType.openList) return (path, null);
        final id = root.id.trim();
        return (path, id.isEmpty ? null : id);
      }).toSet();
}
