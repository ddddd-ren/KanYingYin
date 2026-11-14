part of '../cloud_resources_controller.dart';

/// 扫描：网盘索引快照加载与目录扫描（含取消与进度通知）。
mixin _CloudScanMixin on _CloudResourcesControllerBase {
  @override
  Future<void> _loadSnapshot(CloudSource source, int generation) async {
    final snapshot = await _mediaIndexRepository.snapshot(source.id);
    if (!_isCurrent(generation) || selectedSource?.id != source.id) return;
    Map<String, List<String>> customTags;
    try {
      customTags = await _mediaTagRepository.getBySource(source.id);
    } on Object {
      customTags = <String, List<String>>{};
    }
    if (!_isCurrent(generation) || selectedSource?.id != source.id) return;
    final scopedItems = snapshot.items
        .where(
          (item) => CloudSourcePathScope.containsSourcePath(
            source,
            item.remotePath,
          ),
        )
        .toList(growable: false);
    _indexedItems
      ..clear()
      ..addEntries(
        scopedItems.map(
          (item) => MapEntry(_resourceKeyForItem(item), item),
        ),
      );
    _customTagsByResourceKey
      ..clear()
      ..addAll(customTags);
    final tree = _mediaTreeResolver.resolve(
      sourceId: source.id,
      configuredRoots:
          source.remoteRoots.map((root) => root.path).toList(growable: false),
      directoryEntries: snapshot.directoryEntries,
      minSizeBytes: _minRecognizedVideoSizeBytesProvider(),
    );
    _mediaTree = tree;
    _works = tree.works;
    entries = scopedItems
        .map(
          (item) => CloudFileEntry(
            id: item.remoteId,
            remotePath: item.remotePath,
            name: item.name,
            size: item.size,
            modifiedAt: item.modifiedAt,
            isDirectory: false,
          ),
        )
        .toList(growable: false);
    _invalidateDirectoryScopeTree();
    _reconcileDirectoryScope();
    _reconcileSelectedGenres();
    await reloadMediaLibrarySnapshot(force: true);
  }

  @override
  void _startScan(CloudSource source, int generation) {
    final future = _scanSelectedSource(source, generation);
    _scanFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_scanFuture, future)) _scanFuture = null;
      }),
    );
  }

  Future<void> _scanSelectedSource(CloudSource source, int generation) async {
    final token = CloudScanCancellationToken();
    _scanToken = token;
    if (_isCurrent(generation)) {
      scanning = true;
      scannedDirectories = 0;
      currentScanPath = null;
      errorMessage = null;
      scanFailureTypes = const {};
      _notify();
    }
    CloudDriveClient? client;
    try {
      client = _providerRegistry.createClient(source, _credentialStore);
      final result = await _mediaIndexer.scan(
        source: source,
        client: client,
        cancellationToken: token,
        onProgress: (progress) {
          if (!_isCurrent(generation)) return;
          scannedDirectories = progress.scanned;
          currentScanPath = progress.currentPath;
          _notify();
        },
      );
      if (!_isCurrent(generation) || result.cancelled) return;
      lastScanResult = result;
      scanFailureTypes = result.failureTypes;
      await _loadSnapshot(source, generation);
      if (!_isCurrent(generation)) return;
      if (result.failures > 0) {
        final type = scanRecoveryType;
        final reason = type == null
            ? '目录读取失败'
            : _providerRegistry.errorMessage(
                source.type,
                CloudDriveException(type),
              );
        errorMessage = '$reason，${result.failures} 个目录未读取，已保留原有资料';
      }
      _scheduleTmdb(source, entries);
    } on CloudScanInProgressException {
      if (!_isCurrent(generation)) return;
      errorMessage = '该来源正在扫描，正在显示上次索引';
    } on CloudDriveException catch (error) {
      if (!_isCurrent(generation)) return;
      scanFailureTypes = {error.type};
      errorMessage = _providerRegistry.errorMessage(source.type, error);
    } on Object {
      if (!_isCurrent(generation)) return;
      errorMessage = '网盘媒体扫描失败，已保留上次索引';
    } finally {
      try {
        await client?.close();
      } on Object catch (error, stackTrace) {
        AppLogger().w(
          'CloudResourcesController: failed to close scan client',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (_isCurrent(generation)) {
        scanning = false;
        currentScanPath = null;
        _notify();
      }
    }
  }

  @override
  Future<void> refresh() async {
    if (loading) return;
    final source = selectedSource;
    if (source == null) return;
    if (scanning) return scanCompletion;
    final generation = ++_generation;
    _startScan(source, generation);
    await scanCompletion;
  }
}
