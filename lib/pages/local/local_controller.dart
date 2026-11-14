import 'package:kanyingyin/services/local_video_file_types.dart';
import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/features/library/application/local_library_metadata_coordinator.dart';
import 'package:kanyingyin/features/library/application/local_library_preferences.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
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
import 'package:kanyingyin/modules/local/tmdb_image_metadata.dart';
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
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_scrape_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_image_selection_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_image_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_image_selection_logger.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_poster_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scraper.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_client.dart';
import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';
import 'package:kanyingyin/services/poster_service.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as p;

part 'local_library_application_coordinator.dart';
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
class LocalController = _LocalController
    with _LocalLibraryApplicationCoordinator, _$LocalController;

abstract class _LocalController with Store {
  _LocalController({
    ILocalMediaScanner? scanner,
    int Function()? localMinSizeBytesProvider,
    int Function()? cloudMinSizeBytesProvider,
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
    TmdbVisionSearchAssist? tmdbVisionSearchAssist,
    TmdbVisionClassificationApply? tmdbVisionClassificationApply,
    LibraryGenreBackfillService? genreBackfillService,
  }) : this._(
          scanner: scanner,
          localMinSizeBytesProvider: localMinSizeBytesProvider,
          cloudMinSizeBytesProvider: cloudMinSizeBytesProvider,
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
          tmdbVisionSearchAssist: tmdbVisionSearchAssist,
          tmdbVisionClassificationApply: tmdbVisionClassificationApply,
          genreBackfillService: genreBackfillService,
        );

  _LocalController._({
    ILocalMediaScanner? scanner,
    int Function()? localMinSizeBytesProvider,
    int Function()? cloudMinSizeBytesProvider,
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
    TmdbVisionSearchAssist? tmdbVisionSearchAssist,
    TmdbVisionClassificationApply? tmdbVisionClassificationApply,
    LibraryGenreBackfillService? genreBackfillService,
  })  : _scanner = scanner ?? LocalMediaScanner(),
        _localMinSizeBytesProvider = localMinSizeBytesProvider,
        _cloudMinSizeBytesProvider = cloudMinSizeBytesProvider,
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
              visionSearchAssist: tmdbVisionSearchAssist,
              visionClassificationApply: tmdbVisionClassificationApply,
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
  final int Function()? _localMinSizeBytesProvider;
  final int Function()? _cloudMinSizeBytesProvider;
  LocalScanResult? lastDirectoryScan;
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

  final ObservableList<LocalMediaIndexItem> cachedLocalLibraryItems =
      ObservableList<LocalMediaIndexItem>();
  final ObservableMap<String, bool> _cachedLocalSourceAvailability = ObservableMap();
  final ObservableMap<String, String> _cachedLocalSourceNames = ObservableMap();

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

  @observable
  ObservableList<LocalMediaIndexChange> libraryIndexChanges =
      ObservableList<LocalMediaIndexChange>();

  @observable
  bool isFetchingDirCovers = false;

  @observable
  String dirCoverProgress = '';

  @observable
  int dirCoverCurrent = 0;

  @observable
  int dirCoverTotal = 0;

  // MobX 生成 mixin 需要在基类看到由应用协调器实现的公开入口。
  int get localLibraryVideoCount;
  int get mediaLibraryVideoCount;
  int get localLibrarySeriesCount;
  List<LocalMediaSeries> get localLibrarySeries;
  Future<void> init();
  Future<void> navigateTo(String path);
  Future<Map<String, int>> fetchPosters();
  Future<Map<String, int>> fetchPosterForItem(LocalFileItem item);
  Future<Map<String, int>> fetchPosterForItems(List<LocalFileItem> targetItems);
  Future<int> fetchMediaInfo();
  Future<int> fetchThumbnails();
  void reloadMediaSources();
  Future<bool> removeMediaSource(String path);
  Future<int> removeUnavailableMediaSources();
  Future<LibraryGenreBackfillResult> refreshLibraryGenres();
  void reloadLocalLibraryIndex();
  void reloadAvailableLocalLibraryIndex();
  Future<Map<String, int>> refreshLocalLibraryIndex({
    bool throwOnFailure = false,
  });
  void cancelLocalLibraryIndex();
  Future<Map<String, int>> retryFailedLocalLibraryIndexItems();
  Future<int> scrapeTmdbMetadata();
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
  });
  Future<bool> updateLocalSeriesTitle(
    Iterable<String> videoPaths,
    String title,
  );
  Future<void> navigateUp();
  Future<void> refresh();
  Future<void> toggleSort(String field);
  Future<int> fetchDirectoryCovers();

  String _lastResolvedStartPath = '';
  int _navigationRequestId = 0;
  int _posterRequestId = 0;
  Future<void> _recentDirectoriesWriteQueue = Future<void>.value();
}
