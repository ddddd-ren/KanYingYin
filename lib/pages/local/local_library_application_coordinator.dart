part of 'local_controller.dart';

/// 本地媒体库应用协调逻辑；控制器只保留状态和兼容入口。
mixin _LocalLibraryApplicationCoordinator on _LocalController {
  @override
  @action
  Future<void> init() async {
    await _loadRecentDirectoriesSafe();
    _reloadMediaSourcesSafe();
    await _refreshLocalLibraryDerivedMetadataSafe();
    _reloadLocalLibraryIndexSafe();
    // 启动时也检查旧索引，补齐已匹配电视剧缺失的 TMDB 集名。
    _autoScrapeTmdbAfterScan();
    unawaited(_reloadCloudAndBackfillGenres());
    final lastDir = _preferences.lastLocalDirectory;
    final userDefaultPath = _preferences.defaultPath;

    String? resolvedPath;
    if (userDefaultPath.isNotEmpty && Directory(userDefaultPath).existsSync()) {
      resolvedPath = userDefaultPath;
    } else if (lastDir.isNotEmpty && Directory(lastDir).existsSync()) {
      resolvedPath = lastDir;
    }

    if (resolvedPath == null) {
      isLoading = false;
      errorMessage = null;
      items.clear();
      currentPath = '';
      _lastResolvedStartPath = '';
      return;
    }

    if (currentPath.isEmpty || resolvedPath != _lastResolvedStartPath) {
      _lastResolvedStartPath = resolvedPath;
      await navigateTo(resolvedPath);
    } else {
      await refresh();
    }
  }

  @override
  @action
  Future<void> navigateTo(String path) async {
    final requestId = ++_navigationRequestId;
    if (!Directory(path).existsSync()) {
      isLoading = false;
      lastDirectoryScan = LocalScanResult(
        currentPath: path,
        items: const [],
        skippedCount: 1,
        sourceAccessible: false,
        failedPaths: [path],
        minSizeBytes: lastDirectoryScan?.minSizeBytes ?? 800 * 1024 * 1024,
      );
      errorMessage = '目录暂不可用，请连接磁盘后重试，或重新选择目录：$path';
      AppLogger().w('LocalController: directory not found: $path');
      return;
    }

    errorMessage = null;
    isLoading = true;
    currentPath = path;
    _recordPathHistory(path);
    await _trySaveLastDirectory(path);

    try {
      final result = await _scanner.scan(
        path,
        sortMode: LocalSortMode.fromValue(sortBy),
        ascending: sortAscending,
      );
      if (requestId != _navigationRequestId) {
        AppLogger().i('LocalController: ignored stale scan result from $path');
        return;
      }
      final previousItems = lastDirectoryScan?.currentPath == path
          ? items.toList()
          : const <LocalFileItem>[];
      lastDirectoryScan = result;
      final scannedPaths = result.items.map((item) => item.path).toSet();
      final retained = previousItems.where(
        (item) =>
            !scannedPaths.contains(item.path) &&
            result.failedPaths.any(
              (failed) =>
                  p.equals(failed, item.path) || p.isWithin(failed, item.path),
            ),
      );
      items = ObservableList.of(
        _mergeIndexedMetadata(
          _applySeriesTitleOverrides([...result.items, ...retained]),
        ),
      );
      if (result.failedPaths.isNotEmpty) {
        errorMessage = result.sourceAccessible
            ? '${result.failedPaths.length} 项读取失败，已保留可用内容；请检查目录权限后重试'
            : '目录暂不可用，已保留原有资料；请连接磁盘或重新选择目录';
      }
      if (result.failedPaths.isEmpty) {
        await _tryUpdateMediaSourceScanSummary(path, result);
      }
      AppLogger().i(
        'LocalController: loaded ${items.length} items from $path, skipped ${result.skippedCount}',
      );
    } catch (e) {
      if (requestId != _navigationRequestId) {
        AppLogger().i(
          'LocalController: ignored stale scan error from $path: $e',
        );
        return;
      }
      errorMessage = '读取目录失败: $e';
      AppLogger().e('LocalController: failed to read directory: $e');
    } finally {
      if (requestId == _navigationRequestId) {
        isLoading = false;
      }
    }
  }

  @override
  @action
  Future<Map<String, int>> fetchPosters() async {
    final groups = _seriesGrouper.group(items);
    final targets =
        groups.expand((group) => group.episodes).toList(growable: false);
    return _fetchPostersForItems(targets);
  }

  @override
  @action
  Future<Map<String, int>> fetchPosterForItem(LocalFileItem item) async {
    return _fetchPostersForItems([item]);
  }

  @override
  @action
  Future<Map<String, int>> fetchPosterForItems(
    List<LocalFileItem> targetItems,
  ) async {
    return _fetchPostersForItems(targetItems);
  }

  Future<Map<String, int>> _fetchPostersForItems(
    List<LocalFileItem> targetItems,
  ) async {
    if (isFetchingPosters) {
      return PosterScrapeResult.empty.toMap();
    }

    final posterRequestId = ++_posterRequestId;
    final posterPath = currentPath;
    final navigationRequestId = _navigationRequestId;
    isFetchingPosters = true;
    _applyPosterProgress(const PosterScrapeProgress(
      phase: PosterScrapePhase.preparing,
      current: 0,
      total: 0,
      fileName: '',
      progress: 0,
    ));

    PosterScrapeResult result = PosterScrapeResult.empty;
    var cancelled = false;
    try {
      final batchResult = await _metadataCoordinator.fetchPosters(
        targetItems,
        isCancelled: () => !_isCurrentPosterRequest(
          posterRequestId,
          posterPath,
          navigationRequestId,
        ),
        onProgress: (progress) {
          if (_isCurrentPosterRequest(
            posterRequestId,
            posterPath,
            navigationRequestId,
          )) {
            _applyPosterProgress(progress);
          }
        },
        fallbackCover: (item) {
          return _fallbackCoverForPoster(item, targetItems);
        },
      );
      result = batchResult.result;
      cancelled = batchResult.cancelled;
    } catch (e) {
      AppLogger().e('LocalController: fetchPosters error: $e');
    } finally {
      if (posterRequestId == _posterRequestId) {
        isFetchingPosters = false;
        _resetPosterProgress();
      }
    }

    if (!cancelled &&
        _isCurrentPosterRequest(
          posterRequestId,
          posterPath,
          navigationRequestId,
        )) {
      final refreshNavigationRequestId = _navigationRequestId + 1;
      await refresh();
      if (_isCurrentPosterRequest(
        posterRequestId,
        posterPath,
        refreshNavigationRequestId,
      )) {
        await _syncIndexedCovers(
          targetItems,
          coversByLocationId: result.coversByLocationId,
          posterRequestId: posterRequestId,
          posterPath: posterPath,
          navigationRequestId: refreshNavigationRequestId,
        );
      }
    }
    return result.toMap();
  }

  FutureOr<String?> _fallbackCoverForPoster(
    LocalFileItem item,
    List<LocalFileItem> targetItems,
  ) async {
    final cached = _findIndexedTmdbCover(item.path);
    if (cached != null) return cached;

    final seriesName = item.episodeInfo?.seriesName.trim();
    if (seriesName == null || seriesName.isEmpty) return null;

    final result = await _tmdbScrapeService.scrapeSeries(
      apiKey: _tmdbApiKey,
      seriesName: seriesName,
      options: tmdbScrapeOptions,
    );
    return _tmdbImageUrl(
      result.metadata?.imageOverride.poster ?? result.metadata?.posterUrl,
    );
  }

  String? _findIndexedTmdbCover(String path) {
    for (final indexed in localLibraryItems) {
      if (indexed.path == path) {
        final cover = _tmdbImageUrl(
          indexed.tmdb?.imageOverride.poster ?? indexed.tmdb?.posterUrl,
        );
        if (cover != null && cover.isNotEmpty) return cover;
      }
    }
    return null;
  }

  Future<void> _syncIndexedCovers(
    List<LocalFileItem> targetItems, {
    required Map<String, String> coversByLocationId,
    required int posterRequestId,
    required String posterPath,
    required int navigationRequestId,
  }) async {
    var updated = false;
    for (final item in targetItems) {
      if (!_isCurrentPosterRequest(
        posterRequestId,
        posterPath,
        navigationRequestId,
      )) {
        return;
      }
      final indexed = _mediaIndexRepository.getByLocation(item.location);
      if (indexed == null) continue;

      final cover = coversByLocationId[item.location.stableId] ??
          (item.location.isFile
              ? await LocalCoverFinder().findVideoCover(item.path)
              : null);
      if (cover == null || cover.isEmpty || cover == indexed.cover) {
        continue;
      }

      if (!_isCurrentPosterRequest(
        posterRequestId,
        posterPath,
        navigationRequestId,
      )) {
        return;
      }
      await _mediaIndexRepository.patchItem(
          indexed, indexed.copyWith(cover: cover));
      if (!_isCurrentPosterRequest(
        posterRequestId,
        posterPath,
        navigationRequestId,
      )) {
        return;
      }
      updated = true;
    }
    if (updated &&
        _isCurrentPosterRequest(
          posterRequestId,
          posterPath,
          navigationRequestId,
        )) {
      _reloadLocalLibraryIndexSafe();
    }
  }

  @override
  @action
  Future<int> fetchMediaInfo() async {
    if (isFetchingMediaInfo) return 0;

    final videoItems = items.where((item) => item.isVideo).toList();
    if (videoItems.isEmpty) return 0;

    final path = currentPath;
    final navigationRequestId = _navigationRequestId;
    isFetchingMediaInfo = true;
    mediaInfoCurrent = 0;
    mediaInfoTotal = videoItems.length;
    mediaInfoCurrentFile = '';
    final indexUpdates = <String, LocalMediaIndexItem>{};
    final indexOriginals = <String, LocalMediaIndexItem>{};
    try {
      final result = await _metadataCoordinator.probeMediaInfo(
        videoItems,
        isCancelled: () =>
            path != currentPath || navigationRequestId != _navigationRequestId,
        onProgress: (progress) {
          mediaInfoCurrent = progress.current;
          mediaInfoCurrentFile = progress.fileName;
        },
        onResult: (update) {
          final index = items.indexWhere(
            (currentItem) => currentItem.path == update.item.path,
          );
          if (index < 0) return;
          items[index] = items[index].copyWith(
            duration: update.info.duration,
            videoWidth: update.info.width,
            videoHeight: update.info.height,
          );
          final indexed = _mediaIndexRepository.getByPath(update.item.path);
          if (indexed != null) {
            indexOriginals[indexed.id] = indexed;
            indexUpdates[indexed.id] = indexed.copyWith(
              durationMillis: update.info.duration?.inMilliseconds ??
                  indexed.durationMillis,
              videoWidth: update.info.width ?? indexed.videoWidth,
              videoHeight: update.info.height ?? indexed.videoHeight,
              indexedAt: DateTime.now(),
            );
          }
        },
      );
      if (indexUpdates.isNotEmpty) {
        await _mediaIndexRepository.patchItems(indexUpdates,
            originals: indexOriginals);
        _reloadLocalLibraryIndexSafe();
      }
      return result.updated;
    } finally {
      isFetchingMediaInfo = false;
      mediaInfoCurrentFile = '';
      mediaInfoCurrent = 0;
      mediaInfoTotal = 0;
    }
  }

  @override
  @action
  Future<int> fetchThumbnails() async {
    if (isFetchingThumbnails) return 0;

    final videoItems = items
        .where((item) =>
            item.isVideo && (item.cover == null || item.cover!.isEmpty))
        .toList();
    if (videoItems.isEmpty) return 0;

    final path = currentPath;
    final navigationRequestId = _navigationRequestId;
    isFetchingThumbnails = true;
    thumbnailCurrent = 0;
    thumbnailTotal = videoItems.length;
    thumbnailCurrentFile = '';
    try {
      final result = await _metadataCoordinator.generateThumbnails(
        videoItems,
        isCancelled: () =>
            path != currentPath || navigationRequestId != _navigationRequestId,
        onProgress: (progress) {
          thumbnailCurrent = progress.current;
          thumbnailCurrentFile = progress.fileName;
        },
        onResult: (update) {
          final index = items.indexWhere(
            (currentItem) => currentItem.path == update.item.path,
          );
          if (index < 0) return;
          items[index] = items[index].copyWith(cover: update.thumbnailPath);
        },
      );
      return result.updated;
    } finally {
      isFetchingThumbnails = false;
      thumbnailCurrentFile = '';
      thumbnailCurrent = 0;
      thumbnailTotal = 0;
    }
  }

  Future<bool> setRootDirectory(String path) async {
    if (!Directory(path).existsSync()) {
      errorMessage = '目录暂不可用，请连接磁盘后重试，或重新选择目录：$path';
      AppLogger().w('LocalController: root directory not found: $path');
      return false;
    }
    await _trySaveDefaultDirectory(path);
    await _tryUpsertMediaSource(path);
    _reloadMediaSourcesSafe();
    _lastResolvedStartPath = path;
    await navigateTo(path);
    return true;
  }

  @override
  @action
  void reloadMediaSources() {
    _reloadMediaSourcesSafe();
  }

  @override
  @action
  Future<bool> removeMediaSource(String path) async {
    try {
      final removed = await _sourceCoordinator.removeSource(
        path,
        scanInProgress: isIndexingLibrary,
      );
      if (isIndexingLibrary) return false;
      _reloadMediaSourcesSafe();
      _reloadLocalLibraryIndexSafe();
      return removed;
    } catch (e) {
      AppLogger().w(
        'LocalController: failed to remove local media source: $path',
        error: e,
      );
      return false;
    }
  }

  bool isMediaSourceAvailable(LocalMediaSource source) {
    if (source.location.isDocument) {
      return _sourceAccessibility[source.id] ?? true;
    }
    return _sourceCoordinator.isAvailable(source);
  }

  int unavailableMediaSourceCount() =>
      mediaSources.where((source) => !isMediaSourceAvailable(source)).length;

  @override
  @action
  Future<int> removeUnavailableMediaSources() async {
    final removedCount = await _sourceCoordinator.removeUnavailableSources(
      mediaSources.where((source) => source.location.isFile),
      scanInProgress: isIndexingLibrary,
    );
    if (isIndexingLibrary) return 0;
    _reloadMediaSourcesSafe();
    _reloadLocalLibraryIndexSafe();
    return removedCount;
  }

  @override
  @computed
  int get localLibraryVideoCount => localLibraryItems.length;

  @override
  @computed
  int get mediaLibraryVideoCount => localLibraryItems.length;

  @override
  @computed
  int get localLibrarySeriesCount => localLibrarySeries.length;

  @override
  @computed
  List<LocalMediaSeries> get localLibrarySeries => _libraryBuilder.buildSeries(
        localLibraryItems,
        sourceTitlesByMediaId: localSourceTitlesByMediaId,
        legacyTitlesByMediaId: localLegacySeriesTitlesByMediaId,
      );

  Map<String, String> get localSourceTitlesByMediaId =>
      _sourceTitlesFor(localLibraryItems);

  Map<String, String> _sourceTitlesFor(
      Iterable<LocalMediaIndexItem> indexedItems) {
    return {
      for (final group
          in _localSourceGroups(indexedItems, applyTitleOverrides: true))
        for (final item in group.episodes)
          (item.location.isFile
              ? LocalMediaIndexItem.normalizePath(item.path)
              : item.location.stableId): group.title,
    };
  }

  Map<String, List<String>> get localLegacySeriesTitlesByMediaId =>
      _legacyTitlesFor(localLibraryItems);

  Map<String, List<String>> _legacyTitlesFor(
      Iterable<LocalMediaIndexItem> indexedItems) {
    final indexedById = {for (final item in indexedItems) item.id: item};
    final sourceTitles = _sourceTitlesFor(indexedItems);
    final oldTitles = {
      for (final group in _libraryBuilder.buildSeries(indexedItems))
        for (final item in group.episodes) item.id: group.title,
    };
    final candidatesById = <String, Set<String>>{};
    final owners = <String, Set<String>>{};
    String aliasKey(LocalMediaIndexItem item, String title) =>
        '${item.parentLocation.stableId}|${Uri.encodeComponent(title.toLowerCase())}';
    for (final group
        in _localSourceGroups(indexedItems, applyTitleOverrides: false)) {
      for (final file in group.episodes) {
        final id = file.location.isFile
            ? LocalMediaIndexItem.normalizePath(file.path)
            : file.location.stableId;
        final item = indexedById[id]!;
        final rawTitle = _seriesGrouper.group([file]).single.title;
        final owner = rawTitle.toLowerCase();
        final candidates = <String>{
          rawTitle,
          ...[sourceTitles[id], oldTitles[id], item.tmdb?.title]
              .whereType<String>()
              .map((title) => title.trim())
              .where((title) => title.isNotEmpty),
        };
        candidatesById[id] = candidates;
        for (final title in candidates) {
          owners
              .putIfAbsent(aliasKey(item, title), () => <String>{})
              .add(owner);
        }
      }
    }
    return {
      for (final entry in candidatesById.entries)
        entry.key: entry.value
            .where((title) =>
                owners[aliasKey(indexedById[entry.key]!, title)]!.length == 1)
            .toList(growable: false),
    };
  }

  Iterable<LocalVideoGroup> _localSourceGroups(
    Iterable<LocalMediaIndexItem> indexedItems, {
    required bool applyTitleOverrides,
  }) {
    final parser = LocalEpisodeParser();
    final byDirectory = <String, List<LocalFileItem>>{};
    for (final item in indexedItems) {
      byDirectory.putIfAbsent(item.parentLocation.stableId, () => []).add(
            LocalFileItem(
              location: item.location,
              name: item.name,
              size: item.size,
              modified: item.modified,
              isDirectory: false,
              isVideo: true,
              episodeInfo: item.location.isFile
                  ? parser.parse(item.path)
                  : item.episodeInfo,
              seriesTitleOverride: applyTitleOverrides
                  ? _seriesTitleOverrideRepository
                      .getForDirectory(item.parentPath)
                  : null,
            ),
          );
    }
    return byDirectory.values.expand(_seriesGrouper.group);
  }

  CloudMediaLibrary get localMediaLibrary =>
      const CloudMediaLibraryAggregator().build(
        localItems: localLibraryItems,
        localSourceTitlesByMediaId: localSourceTitlesByMediaId,
        localLegacyTitlesByMediaId: localLegacySeriesTitlesByMediaId,
        cloudItems: const <CloudMediaIndexItem>[],
        cloudSources: const <CloudSource>[],
      );

  CloudMediaLibrary get cachedLocalMediaLibrary {
    return const CloudMediaLibraryAggregator().build(
      localItems: cachedLocalLibraryItems,
      localSourceTitlesByMediaId: _sourceTitlesFor(cachedLocalLibraryItems),
      localLegacyTitlesByMediaId: _legacyTitlesFor(cachedLocalLibraryItems),
      localSourceAvailability: _cachedLocalSourceAvailability,
      localSourceNames: _cachedLocalSourceNames,
      cloudItems: const [],
      cloudSources: const [],
    );
  }

  CloudMediaLibrary get combinedMediaLibrary =>
      const CloudMediaLibraryAggregator().build(
        localItems: localLibraryItems,
        localSourceTitlesByMediaId: localSourceTitlesByMediaId,
        localLegacyTitlesByMediaId: localLegacySeriesTitlesByMediaId,
        cloudItems: cloudLibraryItems,
        cloudSources: cloudLibrarySources,
      );

  List<MediaLibrarySeries> get visibleMediaLibrarySeries =>
      combinedMediaLibrary.filterBySource(selectedLibrarySourceId);

  void selectLibrarySource(String sourceId) {
    selectedLibrarySourceId = sourceId;
  }

  Future<void> reloadCloudLibraryIndex({bool throwOnFailure = false}) async {
    try {
      final sources = await _cloudSourceRepository.getAll();
      final items = <CloudMediaIndexItem>[];
      for (final source in sources) {
        final sourceItems =
            await _cloudMediaIndexRepository.getBySource(source.id);
        items.addAll(
          sourceItems.where(
            (item) =>
                CloudSourcePathScope.containsSourcePath(
                  source,
                  item.remotePath,
                ) &&
                LocalVideoFileTypes.isRecognizedVideoSize(item.size,
                    minSizeBytes: _cloudMinSizeBytesProvider?.call() ?? 0),
          ),
        );
      }
      runInAction(() {
        cloudLibrarySources
          ..clear()
          ..addAll(sources);
        cloudLibraryItems
          ..clear()
          ..addAll(items);
      });
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        'LocalController: failed to load cloud media library',
        error: error,
        stackTrace: stackTrace,
      );
      if (throwOnFailure) rethrow;
    }
  }

  Future<void> _reloadCloudAndBackfillGenres() async {
    await reloadCloudLibraryIndex();
    await refreshLibraryGenres();
  }

  @override
  @action
  Future<LibraryGenreBackfillResult> refreshLibraryGenres() async {
    if (isRefreshingLibraryGenres) {
      return const LibraryGenreBackfillResult(
        updatedWorks: 0,
        failedWorks: 0,
      );
    }
    isRefreshingLibraryGenres = true;
    libraryGenreRefreshProgress = '正在检查类型标签';
    libraryGenreRefreshError = null;
    try {
      final result = await _genreBackfillService.backfill(
        apiKey: _tmdbApiKey,
        localItems: localLibraryItems.toList(growable: false),
        cloudItems: cloudLibraryItems.toList(growable: false),
        onProgress: (current, total) => runInAction(() {
          libraryGenreRefreshProgress = '正在补齐类型 $current/$total';
        }),
      );
      _reloadLocalLibraryIndexSafe();
      await reloadCloudLibraryIndex();
      libraryGenreRefreshProgress = '已更新 ${result.updatedWorks} 个作品类型';
      if (result.failedWorks > 0) {
        libraryGenreRefreshError = '${result.failedWorks} 个作品暂时无法更新';
      }
      return result;
    } on Object catch (error, stackTrace) {
      libraryGenreRefreshError = '类型标签更新失败，请稍后重试';
      AppLogger().w(
        'LocalController: genre backfill failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const LibraryGenreBackfillResult(
        updatedWorks: 0,
        failedWorks: 1,
      );
    } finally {
      isRefreshingLibraryGenres = false;
    }
  }

  Future<void> revealCloudLibrarySource(String sourceId) async {
    await reloadCloudLibraryIndex();
    runInAction(() => selectedLibrarySourceId = sourceId);
  }

  Future<bool> refreshCloudLibrarySource(String sourceId) async {
    final scan = _scanCloudSource;
    if (scan == null || refreshingCloudSourceIds.contains(sourceId)) {
      return false;
    }
    runInAction(() {
      refreshingCloudSourceIds.add(sourceId);
      cloudRefreshError = null;
    });
    try {
      await scan(sourceId);
      await reloadCloudLibraryIndex();
      return true;
    } on Object {
      runInAction(() => cloudRefreshError = '刷新网盘来源失败，请检查连接后重试');
      return false;
    } finally {
      runInAction(() => refreshingCloudSourceIds.remove(sourceId));
    }
  }

  @override
  @action
  void reloadLocalLibraryIndex() {
    _reloadLocalLibraryIndexSafe();
  }

  @override
  @action
  void reloadAvailableLocalLibraryIndex() {
    _reloadLocalLibraryIndexSafe(requireExistingFiles: true);
  }

  Future<int> refreshLocalLibraryDerivedMetadata() async {
    final result = await _refreshLocalLibraryDerivedMetadataSafe();
    if (result.refreshedCount > 0) {
      _reloadLocalLibraryIndexSafe();
    }
    return result.refreshedCount;
  }

  @override
  @action
  Future<Map<String, int>> refreshLocalLibraryIndex({
    bool throwOnFailure = false,
  }) async {
    if (isIndexingLibrary) {
      if (throwOnFailure) {
        throw const LocalLibraryScanInProgressException();
      }
      return const <String, int>{};
    }

    final availableSources = mediaSources.toList(growable: false);
    if (availableSources.isEmpty) {
      libraryIndexSummary = '没有可扫描的媒体源';
      return const <String, int>{
        'sources': 0,
        'total': 0,
        'added': 0,
        'updated': 0,
        'reused': 0,
        'removed': 0,
        'skipped': 0,
        'changes': 0,
      };
    }

    isIndexingLibrary = true;
    cancelLibraryIndexRequested = false;
    libraryIndexFailures.clear();
    libraryIndexChanges.clear();
    libraryIndexCurrent = 0;
    libraryIndexTotal = 0;
    libraryIndexProgressValue = 0;
    libraryIndexCurrentFile = '';
    libraryIndexProgress = '正在准备媒体库索引';
    libraryIndexSummary = '';

    var totalCount = 0;
    var addedCount = 0;
    var updatedCount = 0;
    var reusedCount = 0;
    var removedCount = 0;
    var skippedCount = 0;
    var filteredBySizeCount = 0;
    var scanCancelled = false;

    try {
      for (var sourceIndex = 0;
          sourceIndex < availableSources.length;
          sourceIndex++) {
        final source = availableSources[sourceIndex];
        void onProgress(LocalMediaIndexProgress progress) {
          _applyLibraryIndexProgress(
            progress,
            sourceIndex: sourceIndex,
            sourceCount: availableSources.length,
          );
        }

        final typedIndexer = _mediaIndexer is ILocalMediaLocationIndexer
            ? _mediaIndexer as ILocalMediaLocationIndexer
            : null;
        final LocalMediaIndexResult result;
        if (typedIndexer != null) {
          result = await typedIndexer.indexSourceLocation(
            source.location,
            enrichMediaInfo: true,
            generateThumbnails: true,
            isCancelled: () => cancelLibraryIndexRequested,
            onProgress: onProgress,
          );
        } else if (source.location.isFile) {
          result = await _mediaIndexer.indexSource(
            source.path,
            enrichMediaInfo: true,
            generateThumbnails: true,
            isCancelled: () => cancelLibraryIndexRequested,
            onProgress: onProgress,
          );
        } else {
          throw UnsupportedError('当前索引器不支持 Android 文档来源');
        }
        _sourceAccessibility[source.id] = result.sourceAccessible;
        if (result.mediaIdAliases.isNotEmpty) {
          try {
            await MediaLibraryUserStateRepository()
                .remapMediaIds(result.mediaIdAliases);
          } on Object {
            libraryIndexFailures.add(LocalMediaIndexFailure(
              path: source.path,
              message: '改名后的收藏关联未保存，原记录已保留，可在媒体分类中手动关联',
            ));
          }
        }
        totalCount += result.totalCount;
        addedCount += result.addedCount;
        updatedCount += result.updatedCount;
        reusedCount += result.reusedCount;
        removedCount += result.removedCount;
        skippedCount += result.skippedCount;
        filteredBySizeCount += result.filteredBySizeCount;
        libraryIndexFailures.addAll(result.failures);
        libraryIndexChanges.addAll(result.changes);
        if (result.cancelled || cancelLibraryIndexRequested) {
          scanCancelled = true;
          libraryIndexSummary = '媒体库扫描已取消，已保留 $localLibraryVideoCount 个已索引视频';
          break;
        }
        if (result.sourceAccessible) {
          await _mediaSourceRepository.updateScanSummaryForLocation(
            location: source.location,
            fileCount: result.totalCount,
            videoCount: result.totalCount,
            directoryCount: 0,
            skippedCount: result.skippedCount,
          );
        }
      }
      _reloadMediaSourcesSafe();
      _reloadLocalLibraryIndexSafe();
      if (!scanCancelled) {
        try {
          final inherited =
              await _tmdbScrapeService.inheritMatchedSeriesMetadata();
          if (inherited > 0) {
            _reloadLocalLibraryIndexSafe();
            AppLogger().i(
              'LocalController: inherited TMDB metadata for '
              '$inherited index items',
            );
          }
        } on Object catch (error, stackTrace) {
          AppLogger().w(
            'LocalController: failed to inherit local TMDB metadata',
            error: error,
            stackTrace: stackTrace,
          );
        }
        final failureText = libraryIndexFailures.isEmpty
            ? ''
            : '，${libraryIndexFailures.length} 项需要处理';
        libraryIndexSummary =
            '媒体库已更新：$totalCount 个视频，$filteredBySizeCount 个因大小过滤，$localLibrarySeriesCount 个系列$failureText${totalCount == 0 && filteredBySizeCount == 0 && libraryIndexFailures.isEmpty ? '，未发现视频文件' : ''}';
        _autoScrapeTmdbAfterScan();
      }
    } catch (e, stackTrace) {
      libraryIndexSummary = '媒体库索引失败，已保留原有资料，请重试';
      libraryIndexFailures.add(LocalMediaIndexFailure(
          path: currentPath, message: '索引读取或保存失败，请检查目录和磁盘后重试'));
      AppLogger().w(
        'LocalController: failed to refresh local library index',
        error: e,
        stackTrace: stackTrace,
      );
      if (throwOnFailure) rethrow;
    } finally {
      isIndexingLibrary = false;
      libraryIndexCurrentFile = '';
      libraryIndexCurrent = 0;
      libraryIndexTotal = 0;
      libraryIndexProgressValue = 0;
      libraryIndexProgress = '';
    }

    if (throwOnFailure && scanCancelled) {
      throw const LocalLibraryScanCancelledException();
    }

    return <String, int>{
      'sources': availableSources.length,
      'total': totalCount,
      'added': addedCount,
      'updated': updatedCount,
      'reused': reusedCount,
      'removed': removedCount,
      'skipped': skippedCount,
      'filteredBySize': filteredBySizeCount,
      'failed': libraryIndexFailures.length,
      'changes': libraryIndexChanges.length,
      'cancelled': scanCancelled ? 1 : 0,
    };
  }

  @override
  @action
  void cancelLocalLibraryIndex() {
    if (!isIndexingLibrary) return;
    cancelLibraryIndexRequested = true;
    libraryIndexProgress = '正在取消媒体库扫描';
  }

  @override
  @action
  Future<Map<String, int>> retryFailedLocalLibraryIndexItems() async {
    if (libraryIndexFailures.isEmpty) {
      return const <String, int>{};
    }
    return refreshLocalLibraryIndex();
  }

  @override
  @action
  Future<int> scrapeTmdbMetadata() async {
    if (isScrapingTmdb) return 0;

    final items = localLibraryItems;
    if (items.isEmpty) return 0;

    final unmatched = <String>{};
    for (final item in items) {
      if (_tmdbCoordinator.needsScrape(item)) {
        final name = item.seriesName.trim();
        if (name.isNotEmpty) unmatched.add(name);
      }
    }
    if (unmatched.isEmpty) {
      if (_tmdbApiKey.isNotEmpty) {
        await _autoClassifyMatchedSeries();
      }
      tmdbScrapeProgress = '所有系列已完成 TMDB 刮削';
      return 0;
    }
    if (_tmdbApiKey.isEmpty) {
      tmdbScrapeProgress = '请先在设置中填写 TMDB API Key';
      return 0;
    }

    isScrapingTmdb = true;
    tmdbScrapeCurrent = 0;
    tmdbScrapeTotal = unmatched.length;
    tmdbScrapeProgress = '正在刮削 TMDB 信息...';
    var matched = 0;

    try {
      for (final seriesName in unmatched) {
        tmdbScrapeCurrent++;
        tmdbScrapeProgress =
            '正在匹配 $seriesName ($tmdbScrapeCurrent/$tmdbScrapeTotal)';

        final result = await _tmdbScrapeService.scrapeSeries(
          apiKey: _tmdbApiKey,
          seriesName: seriesName,
          options: tmdbScrapeOptions,
        );
        if (result.status == TmdbScrapeStatus.matched) matched++;
      }
      await _autoClassifyMatchedSeries();
      _reloadLocalLibraryIndexSafe();
      tmdbScrapeProgress =
          matched > 0 ? '已完成 $matched 个系列的 TMDB 刮削' : '没有可自动匹配的 TMDB 信息';
    } catch (e) {
      tmdbScrapeProgress = 'TMDB 刮削出错';
      AppLogger().w('LocalController: TMDB scrape failed', error: e);
    } finally {
      isScrapingTmdb = false;
    }

    return matched;
  }

  Future<void> _autoClassifyMatchedSeries() async {
    final names = localLibraryItems
        .where((item) => item.tmdb != null)
        .map((item) => item.seriesName.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    for (final name in names) {
      await _tmdbScrapeService.classifyExistingSeries(seriesName: name);
    }
  }

  Future<TmdbScrapeResult> scrapeSeriesWithTmdb(
    String seriesName, {
    bool force = true,
    TmdbScrapeOptions? options,
  }) async {
    final result = await _tmdbScrapeService.scrapeSeries(
      apiKey: _tmdbApiKey,
      seriesName: seriesName,
      force: force,
      options: options ?? tmdbScrapeOptions,
    );
    _reloadLocalLibraryIndexSafe();
    await _tmdbScrapeService.classifyExistingSeries(seriesName: seriesName);
    return result;
  }

  Future<TmdbScrapeResult> selectTmdbCandidate(
      String seriesName, TmdbMetadata candidate,
      {TmdbScrapeOptions? options}) async {
    final result = await _tmdbScrapeService.selectCandidate(
      apiKey: _tmdbApiKey,
      seriesName: seriesName,
      candidate: candidate,
      options: options ?? tmdbScrapeOptions,
    );
    _reloadLocalLibraryIndexSafe();
    return result;
  }

  Future<TmdbImageSet> loadLocalTmdbImages(
    String seriesName, {
    TmdbImageKind kind = TmdbImageKind.poster,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final service = LocalTmdbImageSelectionService(
      indexRepository: _mediaIndexRepository,
      metadataRepository: TmdbMetadataRepository(),
      client: _tmdbClientContextRegistry.contextFor(_tmdbApiKey).client,
    );
    return service.imagesForSeries(
      seriesName,
      kind: kind,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      language: tmdbScrapeOptions.language,
    );
  }

  Future<void> selectLocalTmdbImage({
    required String seriesName,
    required TmdbImageKind kind,
    required String filePath,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final startedAt = DateTime.now();
    final normalized = normalizeTmdbImagePath(filePath);
    if (normalized == null) throw ArgumentError.value(filePath, 'filePath');
    final service = LocalTmdbImageSelectionService(
      indexRepository: _mediaIndexRepository,
      metadataRepository: TmdbMetadataRepository(),
      client: _tmdbClientContextRegistry.contextFor(_tmdbApiKey).client,
    );
    await service.selectSeriesImage(
      seriesName: seriesName,
      kind: kind,
      filePath: filePath,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    _reloadLocalLibraryIndexSafe();
    _logLocalTmdbImageDisplay(
      seriesName: seriesName,
      kind: kind,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      selectedPath: normalized,
      startedAt: startedAt,
    );
  }

  Future<void> clearLocalTmdbImage({
    required String seriesName,
    required TmdbImageKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final startedAt = DateTime.now();
    final service = LocalTmdbImageSelectionService(
      indexRepository: _mediaIndexRepository,
      metadataRepository: TmdbMetadataRepository(),
      client: _tmdbClientContextRegistry.contextFor(_tmdbApiKey).client,
    );
    await service.clearSeriesImage(
      seriesName: seriesName,
      kind: kind,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    _reloadLocalLibraryIndexSafe();
    _logLocalTmdbImageDisplay(
      seriesName: seriesName,
      kind: kind,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      startedAt: startedAt,
    );
  }

  Future<CloudTmdbMatchOutcome> scrapeCloudSeries(MediaLibrarySeries series,
      {bool forceManual = false}) async {
    final service = await _cloudTmdbService();
    final result = forceManual
        ? await service.searchCandidates(
            seriesName: series.seriesKey, options: tmdbScrapeOptions)
        : await service.match(
            sourceId: series.sourceId,
            seriesName: series.seriesKey,
            options: tmdbScrapeOptions,
          );
    await reloadCloudLibraryIndex();
    return result;
  }

  Future<void> selectCloudTmdbCandidate(
      MediaLibrarySeries series, TmdbMetadata candidate) async {
    final service = await _cloudTmdbService();
    await service.select(
      sourceId: series.sourceId,
      seriesName: series.seriesKey,
      candidate: candidate,
      options: tmdbScrapeOptions,
    );
    await reloadCloudLibraryIndex();
  }

  Future<CloudTmdbMetadataService> _cloudTmdbService() async {
    final existing = _cloudTmdbMetadataService;
    if (existing != null) return existing;
    final apiKey = _tmdbApiKey;
    if (apiKey.isEmpty) throw StateError('请先在设置中填写 TMDB API Key');
    final cache = CloudPosterCache(
      cacheRoot: await _cloudCacheRootProvider(),
      downloader: TmdbImageClient.shared.downloadBytes,
    );
    final context = _tmdbClientContextRegistry.contextFor(apiKey);
    return _cloudTmdbMetadataService = CloudTmdbMetadataService(
      repository: _cloudMediaIndexRepository,
      client: context.client,
      cache: context.cache,
      posterCache: cache,
    );
  }

  String get _tmdbApiKey => _tmdbApiKeyProvider.read();

  TmdbScrapeOptions get tmdbScrapeOptions {
    return _tmdbCoordinator.options;
  }

  String? indexedSeriesNameForPaths(Iterable<String> paths) {
    final ids = paths.map(LocalMediaIndexItem.normalizePath).toSet();
    final indexedItems = <LocalMediaIndexItem>[
      ...localLibraryItems,
      ..._mediaIndexRepository.getAll(),
    ];
    for (final item in indexedItems) {
      if (!ids.contains(item.id)) continue;
      final name = item.seriesName.trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  TmdbMatchDraft localTmdbDraftForPaths({
    required String originalName,
    required Iterable<String> paths,
  }) {
    final ids = paths.map(LocalMediaIndexItem.normalizePath).toSet();
    final indexedById = <String, LocalMediaIndexItem>{
      for (final item in _mediaIndexRepository.getAll()) item.id: item,
      for (final item in localLibraryItems) item.id: item,
    };
    final items = indexedById.values
        .where((item) => ids.contains(item.id))
        .toList(growable: false);
    if (items.isEmpty) {
      throw StateError('请先扫描媒体库，再进行 TMDB 刮削');
    }
    final seasons = items
        .map((item) => item.seasonNumber)
        .whereType<int>()
        .where((value) => value > 0)
        .toSet();
    final episodes = items
        .map((item) => item.episodeNumber)
        .whereType<int>()
        .where((value) => value > 0)
        .toSet();
    final releaseDate = items
        .map((item) => item.tmdb?.releaseDate)
        .whereType<String>()
        .firstOrNull;
    final year = releaseDate != null && releaseDate.length >= 4
        ? int.tryParse(releaseDate.substring(0, 4))
        : null;
    return TmdbMatchDraft(
      originalName: originalName,
      searchTitle: items.first.seriesName,
      mediaTypeMode: seasons.isNotEmpty || episodes.isNotEmpty
          ? TmdbMediaTypeMode.tv
          : TmdbMediaTypeMode.auto,
      year: year,
      seasonNumber: seasons.length == 1 ? seasons.single : null,
      episodeNumber: episodes.length == 1 ? episodes.single : null,
    );
  }

  Future<TmdbPreparedSearchOutcome> searchLocalTmdb(
    String seriesName,
    TmdbPreparedSearchRequest request,
  ) {
    return _tmdbScrapeService.searchPrepared(
      apiKey: _tmdbApiKey,
      seriesName: seriesName,
      request: request,
    );
  }

  Future<TmdbVisionSuggestion?> identifyLocalTmdb(String seriesName) =>
      _tmdbScrapeService.identifySeries(seriesName);

  Future<TmdbPreparedSearchOutcome> searchLocalTmdbItem(
    String itemId,
    TmdbPreparedSearchRequest request,
  ) {
    return _tmdbScrapeService.searchItemPrepared(
      apiKey: _tmdbApiKey,
      itemId: itemId,
      request: request,
    );
  }

  Future<TmdbScrapeResult> scrapeEpisodeWithTmdb(
    String itemId, {
    bool force = true,
    TmdbScrapeOptions? options,
  }) async {
    final result = await _tmdbScrapeService.scrapeItem(
      apiKey: _tmdbApiKey,
      itemId: itemId,
      force: force,
      options: options ?? tmdbScrapeOptions,
    );
    _reloadLocalLibraryIndexSafe();
    final item = _mediaIndexRepository
        .getAll()
        .where((value) => value.id == itemId)
        .firstOrNull;
    if (item != null) {
      await _tmdbScrapeService.classifyExistingSeries(
        seriesName: item.seriesName,
      );
    }
    return result;
  }

  Future<TmdbScrapeResult> selectTmdbCandidateForEpisode(
    String itemId,
    TmdbMetadata candidate, {
    String? seriesNameOverride,
    TmdbScrapeOptions? options,
  }) async {
    final result = await _tmdbScrapeService.selectItemCandidate(
      apiKey: _tmdbApiKey,
      itemId: itemId,
      candidate: candidate,
      seriesNameOverride: seriesNameOverride,
      options: options ?? tmdbScrapeOptions,
    );
    _reloadLocalLibraryIndexSafe();
    return result;
  }

  ManualEpisodeMatchController manualEpisodeMatchControllerForPaths({
    required Iterable<String> paths,
    required TmdbMetadata selectedSeries,
  }) {
    final apiKey = _tmdbApiKey;
    if (apiKey.isEmpty) {
      throw StateError('请先在设置中填写 TMDB API Key');
    }
    if (selectedSeries.mediaType != TmdbMediaType.tv) {
      throw StateError('剧集匹配只支持 TMDB 电视剧');
    }
    final ids = paths.map(LocalMediaIndexItem.normalizePath).toSet();
    final indexedById = <String, LocalMediaIndexItem>{
      for (final item in _mediaIndexRepository.getAll()) item.id: item,
      for (final item in localLibraryItems) item.id: item,
    };
    final selectedItems = indexedById.values
        .where((item) => ids.contains(item.id))
        .toList(growable: false);
    if (selectedItems.length != ids.length) {
      throw StateError('请先扫描媒体库，再进行剧集匹配');
    }
    const preMatcher = ManualEpisodePreMatcher();
    final matchItems = selectedItems.map((item) {
      final parentName = p.basename(item.parentPath);
      final automatic = preMatcher.match(
        originalName: item.name,
        parentName: parentName,
        grandParentName: p.basename(p.dirname(item.parentPath)),
        expectedSeriesName: item.seriesName,
      );
      return ManualEpisodeMatchItem(
        resourceId: item.id,
        originalName: item.name,
        parentName: parentName,
        existingSeasonNumber: item.seasonNumber,
        existingEpisodeNumber: item.episodeNumber,
        automaticSeasonNumber: automatic?.seasonNumber,
        automaticEpisodeNumber: automatic?.episodeNumber,
        manualOverride: item.manualOverride,
      );
    }).toList(growable: false);
    final client = _tmdbClientContextRegistry.contextFor(apiKey).client;
    if (client is! ITmdbClientCapabilities) {
      throw StateError('当前 TMDB 客户端不支持季度详情');
    }
    final capabilities = client as ITmdbClientCapabilities;
    return ManualEpisodeMatchController(
      selectedSeries: selectedSeries,
      items: matchItems,
      loadDetails: (id, mediaType, language) =>
          client.details(id, mediaType, language: language),
      loadSeason: (id, seasonNumber, language) => capabilities.seasonDetails(
        id,
        seasonNumber,
        language: language,
      ),
    );
  }

  Future<void> saveManualEpisodeAssignments({
    required Iterable<String> paths,
    required List<ManualEpisodeAssignment> assignments,
    required TmdbMetadata metadata,
    required int selectedSeasonNumber,
    String? seriesNameOverride,
  }) async {
    await LocalEpisodeMatchService(repository: _mediaIndexRepository).save(
      resourceIds: paths.map(LocalMediaIndexItem.normalizePath),
      assignments: assignments,
      metadata: metadata,
      selectedSeasonNumber: selectedSeasonNumber,
      seriesNameOverride: seriesNameOverride,
    );
    _reloadLocalLibraryIndexSafe();
  }

  String? _tmdbImageUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return 'https://image.tmdb.org/t/p/w780$path';
  }

  String? tmdbPosterUrlForPaths(Iterable<String> paths) {
    final ids = paths.map(LocalMediaIndexItem.normalizePath).toSet();
    final matches = localLibraryItems
        .where((item) => ids.contains(item.id))
        .toList(growable: false);
    final metadata = matches.map((item) => item.tmdb).nonNulls.firstOrNull;
    if (metadata == null) return null;
    final seasons = matches
        .map((item) => item.seasonNumber)
        .whereType<int>()
        .where((value) => value > 0)
        .toSet();
    final poster = const TmdbPosterPolicy().select(
      metadata,
      seasonNumber: seasons.length == 1 ? seasons.single : null,
      options: const TmdbScrapeOptions.defaults(),
    );
    return _tmdbImageUrl(poster);
  }

  void _logLocalTmdbImageDisplay({
    required String seriesName,
    required TmdbImageKind kind,
    int? seasonNumber,
    int? episodeNumber,
    String? selectedPath,
    required DateTime startedAt,
  }) {
    final key = seriesName.trim().toLowerCase();
    final matching = localLibraryItems
        .where((item) => item.seriesName.trim().toLowerCase() == key)
        .toList(growable: false);
    final metadata = matching.map((item) => item.tmdb).nonNulls.firstOrNull;
    if (metadata == null) return;
    final displayPath = switch (kind) {
      TmdbImageKind.poster => const TmdbPosterPolicy().select(
          metadata,
          seasonNumber: seasonNumber,
          options: const TmdbScrapeOptions.defaults(),
        ),
      TmdbImageKind.backdrop =>
        metadata.imageOverride.backdrop ?? metadata.backdropUrl,
      TmdbImageKind.still => seasonNumber == null || episodeNumber == null
          ? null
          : metadata
              .imageOverride.episodeStills['$seasonNumber:$episodeNumber'],
    };
    final synced = selectedPath == null || kind == TmdbImageKind.still
        ? null
        : normalizeTmdbImagePath(displayPath) ==
            normalizeTmdbImagePath(selectedPath);
    TmdbImageSelectionLogger.write(
      scope: 'local',
      phase: 'display',
      target: episodeNumber != null
          ? 'episode'
          : seasonNumber != null
              ? 'season'
              : 'series',
      kind: kind,
      identity: seriesName,
      tmdbId: metadata.id,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      selectedPath: selectedPath,
      displayPath: displayPath,
      indexSynced: synced,
      elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
      result: synced == false ? 'mismatch' : 'success',
    );
  }

  @override
  @action
  Future<void> updateLocalLibraryItem(
    LocalMediaIndexItem item, {
    required String seriesName,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
    String? releaseGroup,
    String? resolution,
    String? source,
    String? codec,
  }) async {
    final updated = item.copyWith(
      seriesName:
          seriesName.trim().isEmpty ? item.seriesName : seriesName.trim(),
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeTitle: _emptyAsNull(episodeTitle),
      releaseGroup: _emptyAsNull(releaseGroup),
      resolution: _emptyAsNull(resolution),
      source: _emptyAsNull(source),
      codec: _emptyAsNull(codec),
      manualOverride: true,
      indexedAt: DateTime.now(),
    );
    await _mediaIndexRepository.patchItem(item, updated);
    _reloadLocalLibraryIndexSafe();
  }

  @override
  @action
  Future<bool> updateLocalSeriesTitle(
    Iterable<String> videoPaths,
    String title,
  ) async {
    final normalizedTitle = title.trim();
    final paths = videoPaths.toSet();
    if (normalizedTitle.isEmpty || paths.isEmpty) return false;

    final ids = paths.map(LocalMediaIndexItem.normalizePath).toSet();
    await _seriesTitleOverrideRepository.saveForDirectories(
      paths.map(p.dirname).toSet(),
      normalizedTitle,
    );
    items = ObservableList.of(items.map((item) {
      return ids.contains(LocalMediaIndexItem.normalizePath(item.path))
          ? item.copyWith(seriesTitleOverride: normalizedTitle)
          : item;
    }));
    for (final item in _mediaIndexRepository.getAll()) {
      if (!ids.contains(item.id)) continue;
      await _mediaIndexRepository.patchItem(
          item,
          item.copyWith(
            seriesName: normalizedTitle,
            manualOverride: true,
            indexedAt: DateTime.now(),
          ));
    }
    _reloadLocalLibraryIndexSafe();
    return true;
  }

  String? _emptyAsNull(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  @override
  @action
  Future<void> navigateUp() async {
    if (currentPath.isEmpty) return;
    final parent = Directory(currentPath).parent.path;
    if (parent == currentPath) return;
    await navigateTo(parent);
  }

  @override
  @action
  Future<void> refresh() async {
    if (currentPath.isEmpty) {
      await init();
      return;
    }
    await navigateTo(currentPath);
  }

  @override
  @action
  Future<void> toggleSort(String field) async {
    if (sortBy == field) {
      sortAscending = !sortAscending;
    } else {
      sortBy = field;
      sortAscending = true;
    }
    await refresh();
  }

  void _applyPosterProgress(PosterScrapeProgress progress) {
    posterCurrent = progress.current;
    posterTotal = progress.total;
    posterCurrentFile = progress.fileName;
    posterProgressValue = progress.progress;
    posterProgress = progress.label;
  }

  bool _isCurrentPosterRequest(
    int posterRequestId,
    String posterPath,
    int navigationRequestId,
  ) {
    return posterRequestId == _posterRequestId &&
        currentPath == posterPath &&
        _navigationRequestId == navigationRequestId;
  }

  void _resetPosterProgress() {
    posterProgress = '';
    posterProgressValue = 0;
    posterCurrentFile = '';
    posterCurrent = 0;
    posterTotal = 0;
  }

  void _applyLibraryIndexProgress(
    LocalMediaIndexProgress progress, {
    required int sourceIndex,
    required int sourceCount,
  }) {
    libraryIndexCurrent = progress.current;
    libraryIndexTotal = progress.total;
    libraryIndexCurrentFile = progress.currentPath.isEmpty
        ? ''
        : progress.currentPath.split(Platform.pathSeparator).last;
    final sourceProgress =
        sourceCount <= 0 ? 0.0 : (sourceIndex / sourceCount).clamp(0, 1);
    final perSourceProgress =
        sourceCount <= 0 ? 0.0 : progress.progress / sourceCount;
    libraryIndexProgressValue =
        (sourceProgress + perSourceProgress).clamp(0, 1);
    libraryIndexProgress =
        '${progress.label} (${sourceIndex + 1}/$sourceCount)';
  }

  void _recordPathHistory(String path) {
    if (pathHistory.isEmpty || pathHistory.first != path) {
      pathHistory.remove(path);
      pathHistory.insert(0, path);
      while (pathHistory.length > _LocalController._maxRecentDirectories) {
        pathHistory.removeLast();
      }
      unawaited(_trySaveRecentDirectories());
    }
  }

  Future<void> _loadRecentDirectoriesSafe() async {
    try {
      final paths = _preferences.recentDirectories;
      pathHistory = ObservableList.of(
        paths
            .where((path) => path.isNotEmpty && Directory(path).existsSync())
            .take(_LocalController._maxRecentDirectories),
      );
    } catch (e) {
      AppLogger()
          .w('LocalController: failed to load recent directories', error: e);
    }
  }

  Future<void> _trySaveRecentDirectories() async {
    final paths = pathHistory.toList();
    _recentDirectoriesWriteQueue = _recentDirectoriesWriteQueue
        .catchError((_) {})
        .then((_) => _preferences.saveRecentDirectories(paths));
    try {
      await _recentDirectoriesWriteQueue;
    } catch (e) {
      AppLogger()
          .w('LocalController: failed to save recent directories', error: e);
    }
  }

  Future<void> _trySaveLastDirectory(String path) async {
    try {
      await _preferences.saveLastLocalDirectory(path);
    } catch (e) {
      AppLogger().w(
        'LocalController: failed to save last directory: $path',
        error: e,
      );
    }
  }

  Future<void> _trySaveDefaultDirectory(String path) async {
    try {
      await _preferences.saveDefaultPath(path);
    } catch (e) {
      AppLogger().w(
        'LocalController: failed to save default directory: $path',
        error: e,
      );
    }
  }

  Future<void> _tryUpsertMediaSource(String path) async {
    try {
      await _mediaSourceRepository.upsertPath(path);
      _reloadMediaSourcesSafe();
    } catch (e) {
      AppLogger().w(
        'LocalController: failed to save local media source: $path',
        error: e,
      );
    }
  }

  Future<void> addMediaSourceLocation(
    MediaLocation location, {
    required String displayName,
  }) async {
    await _mediaSourceRepository.upsertLocation(
      location,
      displayName: displayName,
    );
    _reloadMediaSourcesSafe();
  }

  Future<void> _tryUpdateMediaSourceScanSummary(
    String path,
    LocalScanResult result,
  ) async {
    try {
      await _mediaSourceRepository.updateScanSummary(
        path: path,
        fileCount: result.items.length,
        videoCount: result.items.where((item) => item.isVideo).length,
        directoryCount: result.items.where((item) => item.isDirectory).length,
        skippedCount: result.skippedCount,
      );
      _reloadMediaSourcesSafe();
    } catch (e) {
      AppLogger().w(
        'LocalController: failed to update local media source scan: $path',
        error: e,
      );
    }
  }

  void _reloadMediaSourcesSafe() {
    try {
      mediaSources = ObservableList.of(_mediaSourceRepository.getAll());
      final sourceIds = mediaSources.map((source) => source.id).toSet();
      _sourceAccessibility.removeWhere(
        (sourceId, _) => !sourceIds.contains(sourceId),
      );
    } catch (e) {
      AppLogger()
          .w('LocalController: failed to load local media sources', error: e);
    }
  }

  /// Fetch TMDB posters for directories that don't have a local cover.
  @override
  @action
  Future<int> fetchDirectoryCovers() async {
    if (isFetchingDirCovers) return 0;

    final dirs = items
        .where((item) =>
            item.isDirectory && (item.cover == null || item.cover!.isEmpty))
        .toList();
    if (dirs.isEmpty) {
      dirCoverProgress = '所有文件夹已有封面';
      return 0;
    }

    isFetchingDirCovers = true;
    dirCoverCurrent = 0;
    dirCoverTotal = dirs.length;
    dirCoverProgress = '正在获取封面...';
    var fetched = 0;

    try {
      for (final dirItem in dirs) {
        dirCoverCurrent++;
        dirCoverProgress =
            '正在获取 ${dirItem.name} ($dirCoverCurrent/$dirCoverTotal)';

        try {
          final posterUrl = await _posterService.searchPoster(
            rawFilename: dirItem.name,
          );
          if (posterUrl == null) continue;

          final savePath = LocalCoverFinder.directoryCoverPath(dirItem.path);

          final savedPath = await _posterService.downloadPosterTo(
            posterUrl,
            savePath,
          );
          if (savedPath != null) {
            fetched++;
          }
        } catch (e) {
          AppLogger().w(
            'LocalController: failed to fetch cover for ${dirItem.name}',
            error: e,
          );
        }
      }

      // Refresh items to pick up new covers.
      if (currentPath.isNotEmpty) {
        await navigateTo(currentPath);
      }

      dirCoverProgress = fetched > 0 ? '已获取 $fetched 个文件夹封面' : '未找到可用封面';
    } catch (e) {
      dirCoverProgress = '封面获取出错';
      AppLogger().w('LocalController: fetchDirectoryCovers failed', error: e);
    } finally {
      isFetchingDirCovers = false;
    }

    return fetched;
  }

  void _autoScrapeTmdbAfterScan() {
    if (!_tmdbCoordinator.shouldAutoScrape(localLibraryItems)) return;
    final unmatched = _tmdbCoordinator.unmatchedSeriesNames(localLibraryItems);
    if (unmatched.isEmpty) return;
    AppLogger().i(
      'LocalController: auto-scraping ${unmatched.length} series with TMDB',
    );
    unawaited(scrapeTmdbMetadata().then((matched) {
      if (matched > 0) {
        AppLogger().i(
          'LocalController: auto-scraped $matched series with TMDB',
        );
      }
    }).catchError((Object e) {
      AppLogger().w(
        'LocalController: automatic TMDB scrape failed',
        error: e,
      );
    }));
  }

  void _reloadLocalLibraryIndexSafe({bool requireExistingFiles = false}) {
    try {
      final threshold = _localMinSizeBytesProvider?.call() ?? 0;
      final cached = _mediaIndexRepository.getAll();
      final sources = {
        for (final source in _mediaSourceRepository.getAll()) source.id: source
      };
      final availability = <String, bool>{};
      for (final item in cached) {
        availability.putIfAbsent(item.sourceLocation.stableId, () {
          final source = sources[item.sourceLocation.stableId];
          if (source != null) {
            return source.enabled && isMediaSourceAvailable(source);
          }
          return item.sourceLocation.isDocument ||
              Directory(item.sourcePath).existsSync();
        });
      }
      _cachedLocalSourceAvailability
        ..clear()
        ..addAll(availability);
      _cachedLocalSourceNames
        ..clear()
        ..addAll(
            {for (final entry in sources.entries) entry.key: entry.value.name});
      if (cached.length != cachedLocalLibraryItems.length ||
          cached.asMap().entries.any((entry) =>
              !identical(entry.value, cachedLocalLibraryItems[entry.key]))) {
        cachedLocalLibraryItems
          ..clear()
          ..addAll(cached);
      }
      final indexedItems = cached
          .where((item) => LocalVideoFileTypes.isRecognizedVideoSize(item.size,
              minSizeBytes: threshold))
          .toList(growable: false);
      final nextItems = requireExistingFiles
          ? indexedItems
              .where(
                (item) =>
                    item.location.isDocument || File(item.path).existsSync(),
              )
              .toList(growable: false)
          : indexedItems;
      final currentItems = localLibraryItems;
      var unchanged = currentItems.length == nextItems.length;
      for (var index = 0; unchanged && index < currentItems.length; index++) {
        unchanged = currentItems[index].id == nextItems[index].id &&
            identical(currentItems[index], nextItems[index]);
      }
      if (unchanged) {
        return;
      }
      localLibraryItems = ObservableList.of(nextItems);
      if (items.isNotEmpty) {
        items = ObservableList.of(_mergeIndexedMetadata(items));
      }
    } catch (e) {
      AppLogger().w(
        'LocalController: failed to load local media index',
        error: e,
      );
    }
  }

  List<LocalFileItem> _applySeriesTitleOverrides(
    Iterable<LocalFileItem> scanItems,
  ) {
    return scanItems.map((item) {
      if (!item.isVideo) return item;
      final title = _seriesTitleOverrideRepository.getForDirectory(
        p.dirname(item.path),
      );
      return title == null ? item : item.copyWith(seriesTitleOverride: title);
    }).toList(growable: false);
  }

  List<LocalFileItem> _mergeIndexedMetadata(
    Iterable<LocalFileItem> scanItems,
  ) {
    final indexedByPath = <String, LocalMediaIndexItem>{
      for (final indexed in localLibraryItems)
        LocalMediaIndexItem.normalizePath(indexed.path): indexed,
    };
    return scanItems.map((item) {
      final indexed =
          indexedByPath[LocalMediaIndexItem.normalizePath(item.path)];
      if (indexed == null) return item;
      return item.copyWith(
        duration: item.duration ??
            (indexed.durationMillis == null
                ? null
                : Duration(milliseconds: indexed.durationMillis!)),
        videoWidth: item.videoWidth ?? indexed.videoWidth,
        videoHeight: item.videoHeight ?? indexed.videoHeight,
        releaseGroup: item.releaseGroup ?? indexed.releaseGroup,
        resolution: item.resolution ?? indexed.resolution,
        source: item.source ?? indexed.source,
        codec: item.codec ?? indexed.codec,
      );
    }).toList(growable: false);
  }

  Future<LocalMediaIndexMetadataRefreshResult>
      _refreshLocalLibraryDerivedMetadataSafe() async {
    try {
      final batchResult = await _metadataCoordinator.refreshDerivedMetadata();
      final result = batchResult.result;
      if (result.refreshedCount > 0) {
        AppLogger().i(
          'LocalController: refreshed ${result.refreshedCount} local media index metadata items',
        );
      }
      return result;
    } catch (e, stackTrace) {
      AppLogger().w(
        'LocalController: failed to refresh local media index metadata',
        error: e,
        stackTrace: stackTrace,
      );
      return const LocalMediaIndexMetadataRefreshResult(
        checkedCount: 0,
        refreshedCount: 0,
        skippedCount: 0,
      );
    }
  }
}
