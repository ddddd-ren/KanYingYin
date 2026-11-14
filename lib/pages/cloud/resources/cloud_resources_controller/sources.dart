part of '../cloud_resources_controller.dart';

/// 来源加载：来源列表、选中来源切换与媒体库快照加载。
mixin _CloudSourcesMixin on _CloudResourcesControllerBase {
  Future<void> load({bool startScan = true}) =>
      _loadSources(startScan: startScan);

  Future<void> ensureLoaded({bool startScan = true}) {
    if (_resourcesInitialized) return Future<void>.value();
    final pending = _resourcesLoadFuture;
    if (pending != null) return pending;
    final future = load(startScan: startScan);
    _resourcesLoadFuture = future;
    return future.whenComplete(() {
      if (identical(_resourcesLoadFuture, future)) {
        _resourcesLoadFuture = null;
        if (!_disposed && !_sourceLoadFailed) {
          _resourcesInitialized = true;
        }
      }
    });
  }

  Future<void> retry({bool startScan = true}) async {
    if (loading) return;
    if (scanning) return scanCompletion;
    if (_sourceLoadFailed || selectedSource == null) {
      await load(startScan: startScan);
    } else {
      await refresh();
    }
  }

  Future<void> ensureMediaLibrarySnapshot() {
    if (_mediaLibrarySnapshotInitialized) return Future<void>.value();
    return reloadMediaLibrarySnapshot();
  }

  @override
  Future<void> reloadMediaLibrarySnapshot({bool force = false}) {
    if (_disposed) return Future<void>.value();
    final pending = _mediaLibraryReloadFuture;
    if (pending != null) {
      if (force) _mediaLibraryReloadGeneration++;
      return pending;
    }
    final future = _reloadLatestMediaLibrarySnapshot(
      ++_mediaLibraryReloadGeneration,
    );
    final completion = future.whenComplete(() {
      _mediaLibraryReloadFuture = null;
    });
    _mediaLibraryReloadFuture = completion;
    return completion;
  }

  Future<void> _reloadLatestMediaLibrarySnapshot(int generation) async {
    while (!_disposed) {
      try {
        await _reloadMediaLibrarySnapshot(generation);
      } catch (_) {
        if (_disposed || generation == _mediaLibraryReloadGeneration) rethrow;
      }
      if (generation == _mediaLibraryReloadGeneration) return;
      // 连续刮削通知只补读最新快照，避免同时重建多份媒体库。
      generation = _mediaLibraryReloadGeneration;
    }
  }

  Future<void> _reloadMediaLibrarySnapshot(int generation) async {
    final nextSeries = Map<String, List<MediaLibrarySeries>>.from(
      _mediaLibrarySeriesBySource,
    );
    final nextCached = Map<String, List<MediaLibrarySeries>>.from(
      _cachedMediaLibrarySeriesBySource,
    );
    final cachedSources = await _repository.getAll();
    if (_disposed || generation != _mediaLibraryReloadGeneration) return;
    final records = await _workTmdbRepository?.getAll() ??
        workTmdbRecords.values.toList(growable: false);
    final nextSourceIds = cachedSources.map((source) => source.id).toSet();

    for (final source in cachedSources) {
      if (_disposed || generation != _mediaLibraryReloadGeneration) return;
      try {
        final snapshot = await _mediaIndexRepository.snapshot(source.id);
        if (_disposed || generation != _mediaLibraryReloadGeneration) return;
        final hidden = await _hiddenVideoRepository.getBySource(source.id);
        if (_disposed || generation != _mediaLibraryReloadGeneration) return;
        final items = snapshot.items.where((item) {
          final inScope = CloudSourcePathScope.containsSourcePath(
            source,
            item.remotePath,
          );
          final isHidden = hidden.any(
            (record) => record.matches(
              sourceId: item.sourceId,
              remoteId: item.remoteId,
              remotePath: item.remotePath,
            ),
          );
          return inScope && !isHidden;
        }).toList(growable: false);
        final sourceRecords = <String, CloudWorkTmdbRecord>{
          for (final record in records)
            if (record.sourceId == source.id) record.workKey: record,
        };
        List<MediaLibrarySeries> build(List<CloudMediaIndexItem> visible, int threshold) {
          final tree = _mediaTreeResolver.resolve(
            sourceId: source.id,
            configuredRoots: source.remoteRoots.map((root) => root.path).toList(),
            directoryEntries: snapshot.directoryEntries,
            minSizeBytes: threshold,
          );
          return _mediaLibraryAdapter.convert(
            source: source,
            collection: _collectionGrouper.group(
              sourceId: source.id, items: visible, works: tree.works, recordsByWorkKey: sourceRecords, query: '',
            ),
            indexedItems: visible,
          );
        }
        nextCached[source.id] = build(items, 0);
        final threshold = _minRecognizedVideoSizeBytesProvider();
        final visible = items.where((item) => LocalVideoFileTypes.isRecognizedVideoSize(
            item.size, minSizeBytes: threshold)).toList(growable: false);
        nextSeries[source.id] = source.enabled
            ? (threshold == 0 ? nextCached[source.id]! : build(visible, threshold))
            : const [];
      } on Object catch (error, stackTrace) {
        AppLogger().w(
          'CloudResourcesController: failed to load media library snapshot '
          'sourceId=${source.id}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (_disposed || generation != _mediaLibraryReloadGeneration) return;
    _mediaLibrarySources = cachedSources;
    nextSeries.removeWhere(
      (sourceId, _) => !nextSourceIds.contains(sourceId),
    );
    _mediaLibrarySeriesBySource
      ..clear()
      ..addAll(nextSeries);
    nextCached.removeWhere((sourceId, _) => !nextSourceIds.contains(sourceId));
    _cachedMediaLibrarySeriesBySource
      ..clear()
      ..addAll(nextCached);
    _mediaLibrarySnapshotInitialized = true;
    if (!_disposed) {
      _mediaLibraryNotifier.notifyListeners();
      _notify();
    }
  }

  Future<void> reloadSourcesAndSnapshot({String? preferredSourceId}) async {
    _scanToken?.cancel();
    await scanCompletion;
    final sourceListBeforeLoad = sources;
    final previousSources = List<CloudSource>.from(sources);
    final previousEntries = List<CloudFileEntry>.from(entries);
    final previousSelectedSource = selectedSource;
    final previousIndexedItems = Map<String, CloudMediaIndexItem>.from(
      _indexedItems,
    );
    final previousHiddenVideos = List<CloudHiddenVideo>.from(_hiddenVideos);
    final previousWorks = List<CloudWorkIdentity>.from(_works);
    final previousMediaTree = _mediaTree;
    final previousQuery = query;
    final previousDirectoryScope = currentDirectoryScope;
    final previousSelectedGenres = Set<String>.from(_selectedGenres);
    final previousCustomTags = <String, List<String>>{
      for (final entry in _customTagsByResourceKey.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    };
    final generation = _generation + 1;
    await _loadSources(
      startScan: false,
      preferredSourceId: preferredSourceId,
    );
    if (!_isCurrent(generation) || !_sourceLoadFailed) return;
    if (identical(sources, sourceListBeforeLoad)) {
      errorMessage = '网盘来源加载失败，请重试';
      _notify();
      return;
    }
    sources = previousSources;
    entries = previousEntries;
    selectedSource = previousSelectedSource;
    _indexedItems
      ..clear()
      ..addAll(previousIndexedItems);
    _hiddenVideos = previousHiddenVideos;
    _works = previousWorks;
    _mediaTree = previousMediaTree;
    query = previousQuery;
    currentDirectoryScope = previousDirectoryScope;
    _selectedGenres
      ..clear()
      ..addAll(previousSelectedGenres);
    _customTagsByResourceKey
      ..clear()
      ..addAll(previousCustomTags);
    _invalidateDirectoryScopeTree();
    loading = false;
    scanning = false;
    errorMessage = '网盘来源加载失败，请重试';
    _notify();
  }

  Future<void> _loadSources({
    required bool startScan,
    String? preferredSourceId,
  }) async {
    final generation = ++_generation;
    _scanToken?.cancel();
    loading = true;
    _sourceLoadFailed = false;
    errorMessage = null;
    scanFailureTypes = const {};
    lastScanResult = null;
    _notify();
    var sourcesRead = false;
    try {
      final allSources = await _repository.getAll();
      final loadedSources = allSources.where((source) => source.enabled)
          .toList(growable: false);
      if (!_isCurrent(generation)) return;
      sourcesRead = true;
      sources = loadedSources;
      // 只有成功读到来源列表才移除快照成员，同时废弃仍在读取的旧快照。
      _mediaLibraryReloadGeneration++;
      _mediaLibrarySources = allSources;
      final sourceIds = allSources.map((source) => source.id).toSet();
      _mediaLibrarySeriesBySource
          .removeWhere((id, _) => !sourceIds.contains(id));
      _cachedMediaLibrarySeriesBySource.removeWhere((id, _) => !sourceIds.contains(id));
      if (loadedSources.isEmpty && allSources.isNotEmpty) {
        await reloadMediaLibrarySnapshot(force: true);
      }
      if (!_isCurrent(generation)) return;
      _mediaLibraryNotifier.notifyListeners();
      final currentId = selectedSource?.id;
      final nextId = loadedSources.any(
        (source) => source.id == preferredSourceId,
      )
          ? preferredSourceId
          : loadedSources.any((source) => source.id == currentId)
              ? currentId
              : loadedSources.firstOrNull?.id;
      await _selectSource(
        nextId,
        generation: generation,
        startScan: startScan,
      );
      if (_isCurrent(generation)) _resourcesInitialized = true;
    } on Object {
      if (!_isCurrent(generation)) return;
      // 来源读取失败时尚未切换状态，保留期间已经成功提交的隐藏等操作。
      if (sourcesRead) {
        sources = <CloudSource>[];
        selectedSource = null;
        entries = <CloudFileEntry>[];
        _indexedItems.clear();
        _customTagsByResourceKey.clear();
        _selectedGenres.clear();
        _hiddenVideos = <CloudHiddenVideo>[];
        _works = <CloudWorkIdentity>[];
        _mediaTree = null;
        currentDirectoryScope = null;
        _invalidateDirectoryScopeTree();
      }
      loading = false;
      scanning = false;
      _sourceLoadFailed = true;
      _resourcesInitialized = false;
      errorMessage = '网盘来源加载失败';
      _notify();
    }
  }

  Future<void> selectSource(String? sourceId) {
    final generation = ++_generation;
    _scanToken?.cancel();
    return _selectSource(
      sourceId,
      generation: generation,
      startScan: true,
    );
  }

  Future<void> _selectSource(
    String? sourceId, {
    required int generation,
    required bool startScan,
  }) async {
    final previousSourceId = selectedSource?.id;
    query = '';
    entries = <CloudFileEntry>[];
    _indexedItems.clear();
    _customTagsByResourceKey.clear();
    _hiddenVideos = <CloudHiddenVideo>[];
    _works = <CloudWorkIdentity>[];
    _mediaTree = null;
    currentDirectoryScope = null;
    errorMessage = null;
    scanFailureTypes = const {};
    lastScanResult = null;
    selectedSource = sourceId == null
        ? null
        : sources.where((source) => source.id == sourceId).firstOrNull;
    if (previousSourceId != selectedSource?.id) _selectedGenres.clear();
    _invalidateDirectoryScopeTree();
    final source = selectedSource;
    if (source == null) {
      loading = false;
      scanning = false;
      _notify();
      return;
    }
    if (source.remoteRoots.isEmpty) {
      loading = false;
      errorMessage = '该来源还没有配置媒体根目录';
      _notify();
      return;
    }
    loading = true;
    _notify();
    String? hiddenVideoWarning;
    final hiddenVideosRevision = _hiddenVideosRevision;
    try {
      final hiddenVideos = await _hiddenVideoRepository.getBySource(source.id);
      if (!_isCurrent(generation) || selectedSource?.id != source.id) return;
      if (hiddenVideosRevision == _hiddenVideosRevision) {
        _hiddenVideos = hiddenVideos;
      }
    } on Object {
      if (!_isCurrent(generation) || selectedSource?.id != source.id) return;
      if (hiddenVideosRevision == _hiddenVideosRevision) {
        _hiddenVideos = <CloudHiddenVideo>[];
        hiddenVideoWarning = '隐藏视频设置读取失败，已显示全部视频';
      }
    }
    await _loadSnapshot(source, generation);
    if (!_isCurrent(generation)) return;
    loading = false;
    errorMessage ??= hiddenVideoWarning;
    _notify();
    _scheduleTmdb(source, entries);
    if (startScan) {
      _startScan(source, generation);
    }
  }
}
