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
    final pending = _mediaLibraryReloadFuture;
    if (!force && pending != null) return pending;
    final future = _reloadMediaLibrarySnapshot(++_mediaLibraryReloadGeneration);
    _mediaLibraryReloadFuture = future;
    return future.whenComplete(() {
      if (identical(_mediaLibraryReloadFuture, future)) {
        _mediaLibraryReloadFuture = null;
      }
    });
  }

  Future<void> _reloadMediaLibrarySnapshot(int generation) async {
    final nextSeries = Map<String, List<MediaLibrarySeries>>.from(
      _mediaLibrarySeriesBySource,
    );
    final enabledSources = (await _repository.getAll())
        .where((source) => source.enabled)
        .toList(growable: false);
    final records = await _workTmdbRepository?.getAll() ??
        workTmdbRecords.values.toList(growable: false);
    final nextSourceIds = enabledSources.map((source) => source.id).toSet();

    for (final source in enabledSources) {
      try {
        final snapshot = await _mediaIndexRepository.snapshot(source.id);
        final hidden = await _hiddenVideoRepository.getBySource(source.id);
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
        final tree = _mediaTreeResolver.resolve(
          sourceId: source.id,
          configuredRoots: source.remoteRoots
              .map((root) => root.path)
              .toList(growable: false),
          directoryEntries: snapshot.directoryEntries,
          minSizeBytes: _minRecognizedVideoSizeBytesProvider(),
        );
        final sourceRecords = <String, CloudWorkTmdbRecord>{
          for (final record in records)
            if (record.sourceId == source.id) record.workKey: record,
        };
        final collection = _collectionGrouper.group(
          items: items,
          works: tree.works,
          recordsByWorkKey: sourceRecords,
          query: '',
        );
        nextSeries[source.id] = _mediaLibraryAdapter.convert(
          source: source,
          collection: collection,
          indexedItems: items,
        );
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
    _mediaLibrarySources = enabledSources;
    nextSeries.removeWhere(
      (sourceId, _) => !nextSourceIds.contains(sourceId),
    );
    _mediaLibrarySeriesBySource
      ..clear()
      ..addAll(nextSeries);
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
    _notify();
    var sourcesRead = false;
    try {
      final loadedSources = (await _repository.getAll())
          .where((source) => source.enabled)
          .toList(growable: false);
      if (!_isCurrent(generation)) return;
      sourcesRead = true;
      sources = loadedSources;
      // 只有成功读到来源列表才移除快照成员，同时废弃仍在读取的旧快照。
      _mediaLibraryReloadGeneration++;
      _mediaLibrarySources = loadedSources;
      final sourceIds = loadedSources.map((source) => source.id).toSet();
      _mediaLibrarySeriesBySource
          .removeWhere((id, _) => !sourceIds.contains(id));
      if (loadedSources.isEmpty) _mediaLibrarySnapshotInitialized = true;
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
