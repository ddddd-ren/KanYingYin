import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/features/library/application/local_library_metadata_coordinator.dart';
import 'package:kanyingyin/features/library/application/local_library_preferences.dart';
import 'package:kanyingyin/features/library/application/local_library_source_coordinator.dart';
import 'package:kanyingyin/features/library/application/local_library_tmdb_coordinator.dart';
import 'package:kanyingyin/features/library/application/library_genre_backfill_service.dart';
import 'package:kanyingyin/features/episode_matching/application/local_episode_match_service.dart';
import 'package:kanyingyin/features/episode_matching/application/manual_episode_match_controller.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_pre_matcher.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
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
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_cache_directories.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';
import 'package:kanyingyin/services/cloud/cloud_tmdb_metadata_service.dart';
import 'package:kanyingyin/services/local_media_indexer.dart';
import 'package:kanyingyin/services/local_media_index_metadata_refresher.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/services/local_media_scanner.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_scrape_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';
import 'package:kanyingyin/services/tmdb/tmdb_image_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_poster_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scraper.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';
import 'package:kanyingyin/services/poster_service.dart';
import 'package:kanyingyin/utils/logger.dart';
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
    CloudWorkTmdbRepository? cloudWorkTmdbRepository,
    CloudCacheRootProvider? cloudCacheRootProvider,
    Future<void> Function(String sourceId)? scanCloudSource,
    CloudTmdbMetadataService? cloudTmdbMetadataService,
    LocalTmdbScrapeService? tmdbScrapeService,
    TmdbApiKeyProvider? tmdbApiKeyProvider,
    TmdbClientContextRegistry? tmdbClientContextRegistry,
    TmdbScrapeOptions Function()? tmdbScrapeOptionsProvider,
    bool Function()? tmdbAutoScrapeProvider,
    LibraryGenreBackfillService? genreBackfillService,
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
          cloudWorkTmdbRepository: cloudWorkTmdbRepository,
          cloudCacheRootProvider: cloudCacheRootProvider,
          scanCloudSource: scanCloudSource,
          cloudTmdbMetadataService: cloudTmdbMetadataService,
          tmdbScrapeService: tmdbScrapeService,
          tmdbApiKeyProvider:
              tmdbApiKeyProvider ?? TmdbApiKeyProvider(userKeyReader: () => ''),
          tmdbClientContextRegistry:
              tmdbClientContextRegistry ?? TmdbClientContextRegistry(),
          tmdbScrapeOptionsProvider: tmdbScrapeOptionsProvider,
          tmdbAutoScrapeProvider: tmdbAutoScrapeProvider,
          genreBackfillService: genreBackfillService,
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
    CloudWorkTmdbRepository? cloudWorkTmdbRepository,
    CloudCacheRootProvider? cloudCacheRootProvider,
    Future<void> Function(String sourceId)? scanCloudSource,
    CloudTmdbMetadataService? cloudTmdbMetadataService,
    LocalTmdbScrapeService? tmdbScrapeService,
    required TmdbApiKeyProvider tmdbApiKeyProvider,
    required TmdbClientContextRegistry tmdbClientContextRegistry,
    TmdbScrapeOptions Function()? tmdbScrapeOptionsProvider,
    bool Function()? tmdbAutoScrapeProvider,
    LibraryGenreBackfillService? genreBackfillService,
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
        _tmdbClientContextRegistry = tmdbClientContextRegistry,
        _tmdbScrapeService = tmdbScrapeService ??
            LocalTmdbScrapeService(
              indexRepository: mediaIndexRepository,
              metadataRepository: TmdbMetadataRepository(),
              clientFactory: tmdbClientContextRegistry.clientFor,
              cacheFactory: tmdbClientContextRegistry.cacheFor,
            ),
        _tmdbApiKeyProvider = tmdbApiKeyProvider,
        _tmdbScrapeOptionsProvider = tmdbScrapeOptionsProvider ??
            (() => const TmdbScrapeOptions.defaults()),
        _tmdbAutoScrapeProvider = tmdbAutoScrapeProvider ?? (() => true),
        _posterService = PosterService(apiKeyProvider: tmdbApiKeyProvider),
        _mediaSourceRepository =
            mediaSourceRepository ?? LocalMediaSourceRepository(),
        _seriesTitleOverrideRepository = seriesTitleOverrideRepository ??
            LocalSeriesTitleOverrideRepository(),
        _cloudSourceRepository =
            cloudSourceRepository ?? CloudSourceRepository(),
        _cloudMediaIndexRepository =
            cloudMediaIndexRepository ?? CloudMediaIndexRepository(),
        _cloudWorkTmdbRepository =
            cloudWorkTmdbRepository ?? CloudWorkTmdbRepository(),
        _cloudCacheRootProvider =
            cloudCacheRootProvider ?? defaultCloudCacheRoot,
        _scanCloudSource = scanCloudSource,
        _cloudTmdbMetadataService = cloudTmdbMetadataService,
        _providedGenreBackfillService = genreBackfillService;

  final ILocalMediaScanner _scanner;
  final ILocalMediaIndexRepository _mediaIndexRepository;
  final ILocalMediaIndexer _mediaIndexer;
  final LocalMediaLibraryBuilder _libraryBuilder;
  final ILocalLibraryPreferences _preferences;
  final LocalLibraryMetadataCoordinator _metadataCoordinator;
  final LocalSeriesGrouper _seriesGrouper;
  final TmdbClientContextRegistry _tmdbClientContextRegistry;
  final LocalTmdbScrapeService _tmdbScrapeService;
  final TmdbApiKeyProvider _tmdbApiKeyProvider;
  final TmdbScrapeOptions Function() _tmdbScrapeOptionsProvider;
  final bool Function() _tmdbAutoScrapeProvider;
  final PosterService _posterService;
  final ILocalMediaSourceRepository _mediaSourceRepository;
  final ILocalSeriesTitleOverrideRepository _seriesTitleOverrideRepository;
  final CloudSourceRepository _cloudSourceRepository;
  final CloudMediaIndexRepository _cloudMediaIndexRepository;
  final CloudWorkTmdbRepository _cloudWorkTmdbRepository;
  final CloudCacheRootProvider _cloudCacheRootProvider;
  final Future<void> Function(String sourceId)? _scanCloudSource;
  CloudTmdbMetadataService? _cloudTmdbMetadataService;
  final LibraryGenreBackfillService? _providedGenreBackfillService;
  late final LibraryGenreBackfillService _genreBackfillService =
      _providedGenreBackfillService ??
          LibraryGenreBackfillService(
            localRepository: _mediaIndexRepository,
            cloudRepository: _cloudMediaIndexRepository,
            workRepository: _cloudWorkTmdbRepository,
            clientFactory: (apiKey) =>
                _tmdbClientContextRegistry.clientFor(apiKey),
          );
  final ObservableMap<String, bool> _sourceAccessibility = ObservableMap();
  late final LocalLibrarySourceCoordinator _sourceCoordinator =
      LocalLibrarySourceCoordinator(
    sourceRepository: _mediaSourceRepository,
    indexRepository: _mediaIndexRepository,
  );
  late final LocalLibraryTmdbCoordinator _tmdbCoordinator =
      LocalLibraryTmdbCoordinator(
    apiKeyProvider: _tmdbApiKeyProvider.read,
    optionsProvider: _tmdbScrapeOptionsProvider,
    autoScrapeProvider: _tmdbAutoScrapeProvider,
  );

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
  bool isRefreshingLibraryGenres = false;

  @observable
  String libraryGenreRefreshProgress = '';

  @observable
  String? libraryGenreRefreshError;

  @observable
  bool isScrapingTmdb = false;

  @observable
  String tmdbScrapeProgress = '';

  @observable
  int tmdbScrapeCurrent = 0;

  @observable
  int tmdbScrapeTotal = 0;

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
              ? LocalCoverFinder().findVideoCover(item.path)
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
      await _mediaIndexRepository.updateItem(indexed.copyWith(cover: cover));
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

  @computed
  int get localLibraryVideoCount => localLibraryItems.length;

  @computed
  int get mediaLibraryVideoCount => localLibraryItems.length;

  @computed
  int get localLibrarySeriesCount =>
      _libraryBuilder.buildSeries(localLibraryItems).length;

  @computed
  List<LocalMediaSeries> get localLibrarySeries =>
      _libraryBuilder.buildSeries(localLibraryItems);

  CloudMediaLibrary get localMediaLibrary =>
      const CloudMediaLibraryAggregator().build(
        localItems: localLibraryItems,
        cloudItems: const <CloudMediaIndexItem>[],
        cloudSources: const <CloudSource>[],
      );

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
        final sourceItems =
            await _cloudMediaIndexRepository.getBySource(source.id);
        items.addAll(
          sourceItems.where(
            (item) => CloudSourcePathScope.containsSourcePath(
              source,
              item.remotePath,
            ),
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
        .where(
          (source) =>
              source.location.isDocument || isMediaSourceAvailable(source),
        )
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
        totalCount += result.totalCount;
        addedCount += result.addedCount;
        updatedCount += result.updatedCount;
        reusedCount += result.reusedCount;
        removedCount += result.removedCount;
        skippedCount += result.skippedCount;
        libraryIndexFailures.addAll(result.failures);
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
