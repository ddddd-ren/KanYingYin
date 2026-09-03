part of '../cloud_resources_controller.dart';

/// 目录范围导航：目录树构建缓存与范围切换。
mixin _CloudDirectoryScopeMixin on _CloudResourcesControllerBase {
  @override
  CloudDirectoryScopeTree get _directoryScopeTree =>
      _directoryScopeTreeCache ??= _directoryScopeTreeBuilder(
        rootPaths: selectedSource?.remoteRoots.map((root) => root.path) ??
            const <String>[],
        mediaPaths: _indexedItems.values.map((item) => item.remotePath),
      );

  List<CloudDirectoryScopeItem> get directoryScopeChildren =>
      _directoryScopeTree.childrenOf(currentDirectoryScope);

  String get directoryScopeAddress => currentDirectoryScope ?? '/';

  void selectDirectoryScope(String path) {
    final normalized = CloudDirectoryScopeTree.normalize(path);
    if (!_directoryScopeTree.hasDirectory(normalized)) {
      throw ArgumentError.value(path, 'path', '目录不在当前媒体索引中');
    }
    if (currentDirectoryScope == normalized) return;
    currentDirectoryScope = normalized;
    _invalidateCollection();
    _notify();
  }

  void navigateDirectoryScopeUp() {
    final current = currentDirectoryScope;
    if (current == null) return;
    currentDirectoryScope = _directoryScopeTree.parentOf(current);
    _invalidateCollection();
    _notify();
  }

  String? submitDirectoryScope(String rawPath) {
    final normalized = CloudDirectoryScopeTree.normalize(rawPath);
    if (normalized == '/') {
      clearDirectoryScope();
      return null;
    }
    if (!_directoryScopeTree.hasDirectory(normalized)) {
      return '目录不存在或无法访问';
    }
    selectDirectoryScope(normalized);
    return null;
  }

  void clearDirectoryScope() {
    if (currentDirectoryScope == null) return;
    currentDirectoryScope = null;
    _invalidateCollection();
    _notify();
  }

  @override
  void _reconcileDirectoryScope() {
    final current = currentDirectoryScope;
    if (current == null || _directoryScopeTree.hasDirectory(current)) return;
    currentDirectoryScope = null;
  }
}
