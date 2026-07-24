import 'package:path/path.dart' as p;

class CloudDirectoryScopeItem {
  const CloudDirectoryScopeItem({
    required this.path,
    required this.label,
  });

  final String path;
  final String label;
}

/// 从媒体根目录和已索引文件路径派生只读目录范围。
class CloudDirectoryScopeTree {
  CloudDirectoryScopeTree._(this._roots, this._directories);

  final List<String> _roots;
  final Set<String> _directories;

  factory CloudDirectoryScopeTree.build({
    required Iterable<String> rootPaths,
    required Iterable<String> mediaPaths,
  }) {
    final roots = rootPaths.map(normalize).toSet().toList()..sort(_comparePath);
    final directories = <String>{...roots};
    for (final mediaPath in mediaPaths) {
      final media = normalize(mediaPath);
      for (final root in roots) {
        if (!_isWithin(media, root)) continue;
        var directory = normalize(p.posix.dirname(media));
        while (_isWithin(directory, root)) {
          directories.add(directory);
          if (directory == root) break;
          final parent = normalize(p.posix.dirname(directory));
          if (parent == directory) break;
          directory = parent;
        }
        break;
      }
    }
    return CloudDirectoryScopeTree._(
      List<String>.unmodifiable(roots),
      Set<String>.unmodifiable(directories),
    );
  }

  List<CloudDirectoryScopeItem> childrenOf(String? scopePath) {
    late final Iterable<String> paths;
    if (scopePath == null) {
      paths = _roots.contains('/')
          ? _directories.where(
              (path) => path != '/' && normalize(p.posix.dirname(path)) == '/',
            )
          : _roots;
    } else {
      final scope = normalize(scopePath);
      paths = _directories.where(
        (path) => path != scope && normalize(p.posix.dirname(path)) == scope,
      );
    }
    final items = paths
        .map(
          (path) => CloudDirectoryScopeItem(
            path: path,
            label:
                p.posix.basename(path).isEmpty ? path : p.posix.basename(path),
          ),
        )
        .toList(growable: false);
    items.sort(
      (left, right) =>
          left.label.toLowerCase().compareTo(right.label.toLowerCase()),
    );
    return items;
  }

  bool contains(String mediaPath, String? scopePath) {
    final media = normalize(mediaPath);
    if (scopePath != null) return _isWithin(media, normalize(scopePath));
    return _roots.any((root) => _isWithin(media, root));
  }

  String? parentOf(String scopePath) {
    final scope = normalize(scopePath);
    final containingRoots = _roots
        .where((root) => _isWithin(scope, root))
        .toList(growable: false)
      ..sort((left, right) => right.length.compareTo(left.length));
    if (containingRoots.isEmpty || containingRoots.first == scope) return null;
    final parent = normalize(p.posix.dirname(scope));
    return _isWithin(parent, containingRoots.first) ? parent : null;
  }

  bool hasDirectory(String path) => _directories.contains(normalize(path));

  static String normalize(String value) {
    var normalized = value.trim().replaceAll(r'\', '/');
    if (normalized.isEmpty) return '/';
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    normalized = p.posix.normalize(normalized);
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static int _comparePath(String left, String right) =>
      left.toLowerCase().compareTo(right.toLowerCase());

  static bool _isWithin(String path, String root) =>
      root == '/' || path == root || path.startsWith('$root/');
}
