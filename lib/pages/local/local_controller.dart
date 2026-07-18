import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/features/library/application/local_library_metadata_coordinator.dart';
import 'package:kanyingyin/features/library/application/local_library_preferences.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/local/poster_scrape.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';
import 'package:kanyingyin/repositories/local_series_title_override_repository.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_cache_directories.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_tmdb_metadata_service.dart';
import 'package:kanyingyin/services/local_media_indexer.dart';
import 'package:kanyingyin/services/local_media_index_metadata_refresher.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/services/local_media_scanner.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_scrape_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scraper.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';
import 'package:kanyingyin/services/poster_service.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as p;

part 'local_controller.g.dart';

final class LocalLibraryScanInProgressException implements Exception {
  const LocalLibraryScanInProgressException();

  @override
  String toString() => '本地媒体库正在扫描';
}

final class LocalLibraryScanCancelledException implements Exception {
  const LocalLibraryScanCancelledException();

  @override
  String toString() => '本地媒体库扫描已取消';
}

// ignore: library_private_types_in_public_api
class LocalController = _LocalController with _$LocalController;

abstract class _LocalController with Store {
  _LocalController({
    ILocalMediaScanner? scanner,
    ILocalMediaIndexer? mediaIndexer,
    LocalMediaLibraryBuilder? mediaLibraryBuilder,
    ILocalLibraryPreferences? preferences,
    LocalLibraryMetadataCoordinator? metadataCoordinator,
    ILocalMediaIndexRepository? mediaIndexRepository,
    ILocalMediaSourceRepository? mediaSourceRepository,
    ILocalSeriesTitleOverrideRepository? seriesTitleOverrideRepository,
    CloudSourceRepository? cloudSourceRepository,
    CloudMediaIndexRepository? cloudMediaIndexRepository,
    CloudCacheRootProvider? cloudCacheRootProvider,
    Future<void> Function(String sourceId)? scanCloudSource,
    CloudTmdbMetadataService? cloudTmdbMetadataService,
    LocalTmdbScrapeService? tmdbScrapeService,
  }) : this._(
          scanner: scanner,
          mediaIndexer: mediaIndexer,
          mediaLibraryBuilder: mediaLibraryBuilder,
          preferences: preferences,
          metadataCoordinator: metadataCoordinator,
          mediaIndexRepository:
              mediaIndexRepository ?? LocalMediaIndexRepository(),
          mediaSourceRepository: mediaSourceRepository,
          seriesTitleOverrideRepository: seriesTitleOverrideRepository,
          cloudSourceRepository: cloudSourceRepository,
          cloudMediaIndexRepository: cloudMediaIndexRepository,
          cloudCacheRootProvider: cloudCacheRootProvider,
          scanCloudSource: scanCloudSource,
          cloudTmdbMetadataService: cloudTmdbMetadataService,
          tmdbScrapeService: tmdbScrapeService,
        );

  _LocalController._({
    ILocalMediaScanner? scanner,
    ILocalMediaIndexer? mediaIndexer,
    LocalMediaLibraryBuilder? mediaLibraryBuilder,
    ILocalLibraryPreferences? preferences,
    LocalLibraryMetadataCoordinator? metadataCoordinator,
    required ILocalMediaIndexRepository mediaIndexRepository,
    ILocalMediaSourceRepository? mediaSourceRepository,
    ILocalSeriesTitleOverrideRepository? seriesTitleOverrideRepository,
    CloudSourceRepository? cloudSourceRepository,
    CloudMediaIndexRepository? cloudMediaIndexRepository,
    CloudCacheRootProvider? cloudCacheRootProvider,
    Future<void> Function(String sourceId)? scanCloudSource,
    CloudTmdbMetadataService? cloudTmdbMetadataService,
    LocalTmdbScrapeService? tmdbScrapeService,
  })  : _scanner = scanner ?? LocalMediaScanner(),
        _mediaIndexRepository = mediaIndexRepository,
        _mediaIndexer =
            mediaIndexer ?? LocalMediaIndexer(repository: mediaIndexRepository),
        _libraryBuilder =
            mediaLibraryBuilder ?? const LocalMediaLibraryBuilder(),
        _preferences = preferences ?? LocalLibraryPreferences(),
        _metadataCoordinator = metadataCoordinator ??
            LocalLibraryMetadataCoordinator(
              mediaIndexRepository: mediaIndexRepository,
            ),
        _seriesGrouper = const LocalSeriesGrouper(),
        _tmdbScrapeService = tmdbScrapeService ??
            LocalTmdbScrapeService(
              indexRepository: mediaIndexRepository,
              metadataRepository: TmdbMetadataRepository(),
              clientFactory: (apiKey) => TmdbClient(apiKey: apiKey),
            ),
        _posterService = PosterService(),
        _mediaSourceRepository =
            mediaSourceRepository ?? LocalMediaSourceRepository(),
        _seriesTitleOverrideRepository = seriesTitleOverrideRepository ??
            LocalSeriesTitleOverrideRepository(),
        _cloudSourceRepository =
            cloudSourceRepository ?? CloudSourceRepository(),
        _cloudMediaIndexRepository =
            cloudMediaIndexRepository ?? CloudMediaIndexRepository(),
        _cloudCacheRootProvider =
            cloudCacheRootProvider ?? defaultCloudCacheRoot,
        _scanCloudSource = scanCloudSource,
        _cloudTmdbMetadataService = cloudTmdbMetadataService;

  final ILocalMediaScanner _scanner;
  final ILocalMediaIndexRepository _mediaIndexRepository;
  final ILocalMediaIndexer _mediaIndexer;
  final LocalMediaLibraryBuilder _libraryBuilder;
  final ILocalLibraryPreferences _preferences;
  final LocalLibraryMetadataCoordinator _metadataCoordinator;
  final LocalSeriesGrouper _seriesGrouper;
  final LocalTmdbScrapeService _tmdbScrapeService;
  final PosterService _posterService;
  final ILocalMediaSourceRepository _mediaSourceRepository;
  final ILocalSeriesTitleOverrideRepository _seriesTitleOverrideRepository;
  final CloudSourceRepository _cloudSourceRepository;
  final CloudMediaIndexRepository _cloudMediaIndexRepository;
  final CloudCacheRootProvider _cloudCacheRootProvider;
  final Future<void> Function(String sourceId)? _scanCloudSource;
  CloudTmdbMetadataService? _cloudTmdbMetadataService;

  static const int _maxRecentDirectories = 10;

  @observable
  String currentPath = '';

  @observable
  ObservableList<LocalFileItem> items = ObservableList<LocalFileItem>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @observable
  String sortBy = LocalSortMode.name.value;

  @observable
  bool sortAscending = true;

  @observable
  ObservableList<String> pathHistory = ObservableList<String>();

  @observable
  ObservableList<LocalMediaSource> mediaSources =
      ObservableList<LocalMediaSource>();

  @observable
  bool isFetchingPosters = false;

  @observable
  String posterProgress = '';

  @observable
  double posterProgressValue = 0;

  @observable
  String posterCurrentFile = '';

  @observable
  int posterCurrent = 0;

  @observable
  int posterTotal = 0;

  @observable
  bool isFetchingMediaInfo = false;

  @observable
  String mediaInfoCurrentFile = '';

  @observable
  int mediaInfoCurrent = 0;

  @observable
  int mediaInfoTotal = 0;

  @observable
  bool isFetchingThumbnails = false;

  @observable
  String thumbnailCurrentFile = '';

  @observable
  int thumbnailCurrent = 0;

  @observable
  int thumbnailTotal = 0;

  @observable
  ObservableList<LocalMediaIndexItem> localLibraryItems =
      ObservableList<LocalMediaIndexItem>();

  final ObservableList<CloudMediaIndexItem> cloudLibraryItems =
      ObservableList<CloudMediaIndexItem>();
  final ObservableList<CloudSource> cloudLibrarySources =
      ObservableList<CloudSource>();
  String selectedLibrarySourceId = 'all';
  final ObservableSet<String> refreshingCloudSourceIds =
      ObservableSet<String>();
  String? cloudRefreshError;

  @observable
  bool isMatchingBangumi = false;

  @observable
  String bangumiMatchProgress = '';

  @observable
  int bangumiMatchCurrent = 0;

  @observable
  int bangumiMatchTotal = 0;

  @observable
  bool isIndexingLibrary = false;

  @observable
  String libraryIndexCurrentFile = '';

  @observable
  int libraryIndexCurrent = 0;

  @observable
  int libraryIndexTotal = 0;

  @observable
  double libraryIndexProgressValue = 0;

  @observable
  String libraryIndexProgress = '';

  @observable
  String libraryIndexSummary = '';

  @observable
  bool cancelLibraryIndexRequested = false;

  @observable
  ObservableList<LocalMediaIndexFailure> libraryIndexFailures =
      ObservableList<LocalMediaIndexFailure>();

  String _lastResolvedStartPath = '';
  int _navigationRequestId = 0;
  int _posterRequestId = 0;
  Future<void> _recentDirectoriesWriteQueue = Future<void>.value();

  @action
  Future<void> init() async {
    await _loadRecentDirectoriesSafe();
    _reloadMediaSourcesSafe();
    await _refreshLocalLibraryDerivedMetadataSafe();
    _reloadLocalLibraryIndexSafe();
    unawaited(reloadCloudLibraryIndex());
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

  @action
  Future<void> navigateTo(String path) async {
    if (!Directory(path).existsSync()) {
      errorMessage = '目录不存在: $path';
      AppLogger().w('LocalController: directory not found: $path');
      return;
    }

    final requestId = ++_navigationRequestId;
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
        AppLogger().i(
          'LocalController: ignored stale scan result from $path',
        );
        return;
      }
      items = ObservableList.of(_applySeriesTitleOverrides(result.items));
      await _tryUpdateMediaSourceScanSummary(path, result);
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

  @action
  Future<Map<String, int>> fetchPosters() async {
    final groups = _seriesGrouper.group(items);
    final targets =
        groups.expand((group) => group.episodes).toList(growable: false);
    return _fetchPostersForItems(targets);
  }

  @action
  Future<Map<String, int>> fetchPosterForItem(LocalFileItem item) async {
    return _fetchPostersForItems([item]);
  }

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
    try {
      result = await _metadataCoordinator.fetchPosters(
        targetItems,
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
    } catch (e) {
      AppLogger().e('LocalController: fetchPosters error: $e');
    } finally {
      if (posterRequestId == _posterRequestId) {
        isFetchingPosters = false;
        _resetPosterProgress();
      }
    }

    if (_isCurrentPosterRequest(
      posterRequestId,
      posterPath,
      navigationRequestId,
    )) {
      await refresh();
      await _syncIndexedCovers(targetItems);
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
    return _tmdbImageUrl(result.metadata?.posterUrl);
  }

  String? _findIndexedTmdbCover(String path) {
    for (final indexed in localLibraryItems) {
      if (indexed.path == path) {
        final cover = _tmdbImageUrl(indexed.tmdb?.posterUrl);
        if (cover != null && cover.isNotEmpty) return cover;
      }
    }
    return null;
  }

  Future<void> _syncIndexedCovers(List<LocalFileItem> targetItems) async {
    var updated = false;
    for (final item in targetItems) {
      final indexed = _mediaIndexRepository.getByPath(item.path);
      if (indexed == null) continue;

      final cover = LocalCoverFinder().findVideoCover(item.path);
      if (cover == null || cover.isEmpty || cover == indexed.cover) {
        continue;
      }

      await _mediaIndexRepository.updateItem(indexed.copyWith(cover: cover));
      updated = true;
    }
    if (updated) {
      _reloadLocalLibraryIndexSafe();
    }
  }

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
        },
      );
      return result.updated;
    } finally {
      isFetchingMediaInfo = false;
      mediaInfoCurrentFile = '';
      mediaInfoCurrent = 0;
      mediaInfoTotal = 0;
    }
  }

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
      errorMessage = '目录不存在: $path';
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

  @action
  void reloadMediaSources() {
    _reloadMediaSourcesSafe();
  }

  @action
  Future<bool> removeMediaSource(String path) async {
    try {
      final removed = await _mediaSourceRepository.removePath(path);
      await _tryRemoveMediaIndexSource(path);
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
    return Directory(source.path).existsSync();
  }

  int unavailableMediaSourceCount() {
    return mediaSources
        .where((source) => !isMediaSourceAvailable(source))
        .length;
  }

  @action
  Future<int> removeUnavailableMediaSources() async {
    final unavailableSources = mediaSources
        .where((source) => !isMediaSourceAvailable(source))
        .toList(growable: false);
    var removedCount = 0;
    for (final source in unavailableSources) {
      try {
        final removed = await _mediaSourceRepository.removePath(source.path);
        if (removed) {
          await _tryRemoveMediaIndexSource(source.path);
          removedCount++;
        }
      } catch (e) {
        AppLogger().w(
          'LocalController: failed to remove unavailable media source: ${source.path}',
          error: e,
        );
      }
    }
    _reloadMediaSourcesSafe();
    _reloadLocalLibraryIndexSafe();
    return removedCount;
  }

  @computed
  int get localLibraryVideoCount => localLibraryItems.length;

  @computed
  int get mediaLibraryVideoCount =>
      localLibraryItems.length + cloudLibraryItems.length;

  @computed
  int get localLibrarySeriesCount =>
      _libraryBuilder.buildSeries(localLibraryItems).length;

  @computed
  List<LocalMediaSeries> get localLibrarySeries =>
      _libraryBuilder.buildSeries(localLibraryItems);

  CloudMediaLibrary get combinedMediaLibrary =>
      const CloudMediaLibraryAggregator().build(
        localItems: localLibraryItems,
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
        items.addAll(await _cloudMediaIndexRepository.getBySource(source.id));
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

  @action
  void reloadLocalLibraryIndex() {
    _reloadLocalLibraryIndexSafe();
  }

  Future<int> refreshLocalLibraryDerivedMetadata() async {
    final result = await _refreshLocalLibraryDerivedMetadataSafe();
    if (result.refreshedCount > 0) {
      _reloadLocalLibraryIndexSafe();
    }
    return result.refreshedCount;
  }

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

    final availableSources = mediaSources
        .where((source) => isMediaSourceAvailable(source))
        .toList(growable: false);
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
      };
    }

    isIndexingLibrary = true;
    cancelLibraryIndexRequested = false;
    libraryIndexFailures.clear();
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
    var scanCancelled = false;

    try {
      for (var sourceIndex = 0;
          sourceIndex < availableSources.length;
          sourceIndex++) {
        final source = availableSources[sourceIndex];
        final result = await _mediaIndexer.indexSource(
          source.path,
          enrichMediaInfo: true,
          generateThumbnails: true,
          isCancelled: () => cancelLibraryIndexRequested,
          onProgress: (progress) {
            _applyLibraryIndexProgress(
              progress,
              sourceIndex: sourceIndex,
              sourceCount: availableSources.length,
            );
          },
        );
        totalCount += result.totalCount;
        addedCount += result.addedCount;
        updatedCount += result.updatedCount;
        reusedCount += result.reusedCount;
        removedCount += result.removedCount;
        skippedCount += result.skippedCount;
        libraryIndexFailures.addAll(result.failures);
        await _mediaSourceRepository.updateScanSummary(
          path: source.path,
          fileCount: result.totalCount,
          videoCount: result.totalCount,
          directoryCount: 0,
          skippedCount: result.skippedCount,
        );
        if (result.cancelled || cancelLibraryIndexRequested) {
          scanCancelled = true;
          libraryIndexSummary = '媒体库扫描已取消，已保留 $localLibraryVideoCount 个已索引视频';
          break;
        }
      }
      _reloadMediaSourcesSafe();
      _reloadLocalLibraryIndexSafe();
      if (!scanCancelled) {
        final failureText = libraryIndexFailures.isEmpty
            ? ''
            : '，${libraryIndexFailures.length} 项需要处理';
        libraryIndexSummary =
            '媒体库已更新：$totalCount 个视频，$localLibrarySeriesCount 个系列$failureText';
        _autoScrapeTmdbAfterScan();
      }
    } catch (e, stackTrace) {
      libraryIndexSummary = '媒体库索引失败';
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
      'failed': libraryIndexFailures.length,
      'cancelled': scanCancelled ? 1 : 0,
    };
  }

  @action
  void cancelLocalLibraryIndex() {
    if (!isIndexingLibrary) return;
    cancelLibraryIndexRequested = true;
    libraryIndexProgress = '正在取消媒体库扫描';
  }

  @action
  Future<Map<String, int>> retryFailedLocalLibraryIndexItems() async {
    if (libraryIndexFailures.isEmpty) {
      return const <String, int>{};
    }
    return refreshLocalLibraryIndex();
  }

  @action
  Future<int> matchWithBangumi() async {
    if (isMatchingBangumi) return 0;

    final items = localLibraryItems;
    if (items.isEmpty) return 0;

    final unmatched = <String>{};
    for (final item in items) {
      if (item.tmdb == null || item.scrapeStatus != TmdbScrapeStatus.matched) {
        final name = item.seriesName.trim();
        if (name.isNotEmpty) unmatched.add(name);
      }
    }
    if (unmatched.isEmpty) {
      bangumiMatchProgress = '所有系列已完成 TMDB 刮削';
      return 0;
    }
    if (_tmdbApiKey.isEmpty) {
      bangumiMatchProgress = '请先在设置中填写 TMDB API Key';
      return 0;
    }

    isMatchingBangumi = true;
    bangumiMatchCurrent = 0;
    bangumiMatchTotal = unmatched.length;
    bangumiMatchProgress = '正在刮削 TMDB 信息...';
    var matched = 0;

    try {
      for (final seriesName in unmatched) {
        bangumiMatchCurrent++;
        bangumiMatchProgress =
            '正在匹配 $seriesName ($bangumiMatchCurrent/$bangumiMatchTotal)';

        final result = await _tmdbScrapeService.scrapeSeries(
          apiKey: _tmdbApiKey,
          seriesName: seriesName,
          options: tmdbScrapeOptions,
        );
        if (result.status == TmdbScrapeStatus.matched) matched++;
      }
      _reloadLocalLibraryIndexSafe();
      bangumiMatchProgress =
          matched > 0 ? '已完成 $matched 个系列的 TMDB 刮削' : '没有可自动匹配的 TMDB 信息';
    } catch (e) {
      bangumiMatchProgress = 'TMDB 刮削出错';
      AppLogger().w('LocalController: TMDB scrape failed', error: e);
    } finally {
      isMatchingBangumi = false;
    }

    return matched;
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
      downloader: (url) async {
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(Uri.parse(url))).close();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException('海报下载失败：${response.statusCode}');
          }
          return response.fold<List<int>>(<int>[], (bytes, chunk) {
            bytes.addAll(chunk);
            return bytes;
          });
        } finally {
          client.close(force: true);
        }
      },
    );
    return _cloudTmdbMetadataService = CloudTmdbMetadataService(
      repository: _cloudMediaIndexRepository,
      client: TmdbClient(apiKey: apiKey),
      posterCache: cache,
    );
  }

  String get _tmdbApiKey {
    try {
      return GStorage.setting
          .get('tmdbApiKey', defaultValue: '')
          .toString()
          .trim();
    } catch (_) {
      return '';
    }
  }

  TmdbScrapeOptions get tmdbScrapeOptions {
    try {
      return TmdbScrapeOptions.fromMap(
        GStorage.setting.get('tmdbScrapeOptions'),
      );
    } catch (_) {
      return const TmdbScrapeOptions.defaults();
    }
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

  String? _tmdbImageUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return 'https://image.tmdb.org/t/p/w780$path';
  }

  String? tmdbPosterUrlForPaths(Iterable<String> paths) {
    final ids = paths.map(LocalMediaIndexItem.normalizePath).toSet();
    for (final item in localLibraryItems) {
      if (!ids.contains(item.id)) continue;
      final url = _tmdbImageUrl(item.tmdb?.posterUrl);
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

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
    await _mediaIndexRepository.updateItem(updated);
    _reloadLocalLibraryIndexSafe();
  }

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
      await _mediaIndexRepository.updateItem(item.copyWith(
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

  @action
  Future<void> navigateUp() async {
    if (currentPath.isEmpty) return;
    final parent = Directory(currentPath).parent.path;
    if (parent == currentPath) return;
    await navigateTo(parent);
  }

  @action
  Future<void> refresh() async {
    if (currentPath.isEmpty) {
      await init();
      return;
    }
    await navigateTo(currentPath);
  }

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
      while (pathHistory.length > _maxRecentDirectories) {
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
            .take(_maxRecentDirectories),
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
    } catch (e) {
      AppLogger()
          .w('LocalController: failed to load local media sources', error: e);
    }
  }

  @observable
  bool isFetchingDirCovers = false;

  @observable
  String dirCoverProgress = '';

  @observable
  int dirCoverCurrent = 0;

  @observable
  int dirCoverTotal = 0;

  /// Fetch TMDB posters for directories that don't have a local cover.
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
    bool autoScrape;
    try {
      autoScrape =
          GStorage.setting.get('tmdbAutoScrape', defaultValue: true) as bool;
    } catch (_) {
      return;
    }
    if (!autoScrape || _tmdbApiKey.isEmpty) return;

    final unmatched = localLibraryItems
        .where((item) =>
            item.tmdb == null || item.scrapeStatus != TmdbScrapeStatus.matched)
        .map((item) => item.seriesName.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (unmatched.isEmpty) return;
    AppLogger().i(
      'LocalController: auto-scraping ${unmatched.length} series with TMDB',
    );
    matchWithBangumi().then((matched) {
      if (matched > 0) {
        AppLogger().i(
          'LocalController: auto-scraped $matched series with TMDB',
        );
      }
    }).catchError((e) {
      AppLogger().w(
        'LocalController: automatic TMDB scrape failed',
        error: e,
      );
    });
  }

  void _reloadLocalLibraryIndexSafe() {
    try {
      localLibraryItems = ObservableList.of(_mediaIndexRepository.getAll());
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

  Future<LocalMediaIndexMetadataRefreshResult>
      _refreshLocalLibraryDerivedMetadataSafe() async {
    try {
      final result = await _metadataCoordinator.refreshDerivedMetadata();
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

  Future<void> _tryRemoveMediaIndexSource(String path) async {
    try {
      await _mediaIndexRepository.removeSource(path);
    } catch (e) {
      AppLogger().w(
        'LocalController: failed to remove media index source: $path',
        error: e,
      );
    }
  }
}
