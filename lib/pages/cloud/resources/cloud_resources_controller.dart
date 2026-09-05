import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:kanyingyin/features/cloud/application/cloud_directory_scope_tree.dart';
import 'package:kanyingyin/features/cloud/application/cloud_genre_filter.dart';
import 'package:kanyingyin/features/cloud/application/cloud_resource_tmdb_facade.dart';
import 'package:kanyingyin/features/episode_matching/application/cloud_episode_match_service.dart';
import 'package:kanyingyin/features/episode_matching/application/manual_episode_match_controller.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_hidden_video.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_media_library_adapter.dart';
import 'package:kanyingyin/repositories/cloud_hidden_video_repository.dart';
import 'package:kanyingyin/repositories/cloud_episode_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_tag_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_media_tree_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_auto_organizer.dart';
import 'package:kanyingyin/services/cloud/cloud_series_identity_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_service.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/utils/logger.dart';

part 'cloud_resources_controller/directory_scope.dart';
part 'cloud_resources_controller/filter_tags.dart';
part 'cloud_resources_controller/hidden_videos.dart';
part 'cloud_resources_controller/sources.dart';
part 'cloud_resources_controller/scan.dart';
part 'cloud_resources_controller/tmdb_entry.dart';
part 'cloud_resources_controller/tmdb_work.dart';
part 'cloud_resources_controller/episode_match.dart';
part 'cloud_resources_controller/auto_organize.dart';

int _defaultCloudMinSizeBytes() =>
    LocalVideoFileTypes.minRecognizedVideoSizeBytes;

typedef CloudDirectoryScopeTreeBuilder = CloudDirectoryScopeTree Function({
  required Iterable<String> rootPaths,
  required Iterable<String> mediaPaths,
});

CloudDirectoryScopeTree _buildDirectoryScopeTree({
  required Iterable<String> rootPaths,
  required Iterable<String> mediaPaths,
}) =>
    CloudDirectoryScopeTree.build(
      rootPaths: rootPaths,
      mediaPaths: mediaPaths,
    );

enum CloudResourceAutoOrganizePhase { scanning, scraping }

class CloudResourceAutoOrganizeProgress {
  const CloudResourceAutoOrganizeProgress({
    required this.phase,
    required this.scannedDirectories,
    required this.discoveredTargets,
    required this.completedTargets,
    required this.totalTargets,
  });

  final CloudResourceAutoOrganizePhase phase;
  final int scannedDirectories;
  final int discoveredTargets;
  final int completedTargets;
  final int totalTargets;
}

class CloudResourceAutoOrganizeSummary {
  const CloudResourceAutoOrganizeSummary({
    required this.matched,
    required this.pending,
    required this.noResult,
    required this.failed,
    required this.skipped,
  });

  final int matched;
  final int pending;
  final int noResult;
  final int failed;
  final int skipped;
}

/// 比较两份隐藏视频记录是否一致（拆分自原类的静态方法）。
bool _sameHiddenVideos(
  List<CloudHiddenVideo> current,
  List<CloudHiddenVideo> next,
) {
  if (current.length != next.length) return false;
  final currentByIdentity = <String, CloudHiddenVideo>{
    for (final record in current) record.identityKey: record,
  };
  return next.every(
    (record) => currentByIdentity[record.identityKey] == record,
  );
}

/// 生成索引项的 TMDB 稳定键（拆分自原类的静态方法）。
String _resourceKeyForItem(CloudMediaIndexItem item) => cloudResourceTmdbKey(
      sourceId: item.sourceId,
      remoteId: item.remoteId,
      remotePath: item.remotePath,
    );

/// 归一化网盘路径（拆分自原类的静态方法）。
String _normalizeCloudPath(String value) {
  var path = value.trim().replaceAll('\\', '/');
  path = path.replaceAll(RegExp(r'/+'), '/');
  if (path.isEmpty) return '/';
  if (!path.startsWith('/')) path = '/$path';
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

/// 网盘资源控制器基类：集中持有全部依赖、状态字段、基础 getter 与通用工具，
/// 各职责分组的方法由同目录 part 文件中的 mixin 提供，跨分组成员在下方抽象声明。
abstract class _CloudResourcesControllerBase extends ChangeNotifier {
  _CloudResourcesControllerBase({
    required CloudSourceRepository repository,
    required CloudCredentialStore credentialStore,
    CloudProviderRegistry? providerRegistry,
    CloudResourceTmdbCoordinator? tmdbCoordinator,
    CloudWorkTmdbCoordinator? workTmdbCoordinator,
    CloudResourceAutoOrganizer? autoOrganizer,
    int Function()? minRecognizedVideoSizeBytesProvider,
    CloudResourceCollectionGrouper? collectionGrouper,
    CloudMediaIndexRepository? mediaIndexRepository,
    CloudWorkTmdbRepository? workTmdbRepository,
    ICloudMediaTagRepository? mediaTagRepository,
    ICloudHiddenVideoRepository? hiddenVideoRepository,
    CloudMediaIndexer? mediaIndexer,
    CloudMediaTreeResolver? mediaTreeResolver,
    CloudDirectoryScopeTreeBuilder? directoryScopeTreeBuilder,
    CloudResourceMediaLibraryAdapter? mediaLibraryAdapter,
    CloudEpisodeMatchService? episodeMatchService,
    TmdbApiKeyProvider? tmdbApiKeyProvider,
    TmdbClientContextRegistry? tmdbClientContextRegistry,
  })  : _repository = repository,
        _credentialStore = credentialStore,
        _mediaIndexRepository =
            mediaIndexRepository ?? CloudMediaIndexRepository(),
        _workTmdbRepository = workTmdbRepository,
        _mediaTagRepository = mediaTagRepository ?? CloudMediaTagRepository(),
        _hiddenVideoRepository =
            hiddenVideoRepository ?? CloudHiddenVideoRepository(),
        _providerRegistry = providerRegistry ?? CloudProviderRegistry(),
        _tmdbCoordinator = tmdbCoordinator,
        _workTmdbCoordinator = workTmdbCoordinator,
        _minRecognizedVideoSizeBytesProvider =
            minRecognizedVideoSizeBytesProvider ?? _defaultCloudMinSizeBytes,
        _collectionGrouper =
            collectionGrouper ?? CloudResourceCollectionGrouper(),
        _mediaTreeResolver =
            mediaTreeResolver ?? const CloudMediaTreeResolver(),
        _directoryScopeTreeBuilder =
            directoryScopeTreeBuilder ?? _buildDirectoryScopeTree,
        _mediaLibraryAdapter =
            mediaLibraryAdapter ?? const CloudResourceMediaLibraryAdapter(),
        _autoOrganizer = autoOrganizer ??
            CloudResourceAutoOrganizer(
              minRecognizedVideoSizeBytesProvider:
                  minRecognizedVideoSizeBytesProvider ??
                      _defaultCloudMinSizeBytes,
            ) {
    _episodeMatchService = episodeMatchService ??
        CloudEpisodeMatchService(
          ruleRepository: CloudEpisodeMatchRuleRepository(),
          indexRepository: _mediaIndexRepository,
        );
    _tmdbApiKeyProvider =
        tmdbApiKeyProvider ?? TmdbApiKeyProvider(userKeyReader: () => '');
    _tmdbClientContextRegistry =
        tmdbClientContextRegistry ?? TmdbClientContextRegistry();
    _mediaIndexer = mediaIndexer ??
        CloudMediaIndexer(
          repository: _mediaIndexRepository,
          minRecognizedVideoSizeBytesProvider:
              _minRecognizedVideoSizeBytesProvider,
        );
    _resourceTmdbRecordsRevision = _tmdbCoordinator?.recordsRevision ?? 0;
    _workTmdbRecordsRevision = _workTmdbCoordinator?.recordsRevision ?? 0;
    _tmdbCoordinator?.addListener(_handleTmdbChange);
    _workTmdbCoordinator?.addListener(_handleTmdbChange);
  }

  final CloudSourceRepository _repository;
  final CloudCredentialStore _credentialStore;
  final CloudMediaIndexRepository _mediaIndexRepository;
  final CloudWorkTmdbRepository? _workTmdbRepository;
  final ICloudMediaTagRepository _mediaTagRepository;
  final ICloudHiddenVideoRepository _hiddenVideoRepository;
  late final CloudMediaIndexer _mediaIndexer;
  final CloudProviderRegistry _providerRegistry;
  final CloudResourceTmdbCoordinator? _tmdbCoordinator;
  final CloudWorkTmdbCoordinator? _workTmdbCoordinator;
  final CloudResourceAutoOrganizer _autoOrganizer;
  final int Function() _minRecognizedVideoSizeBytesProvider;
  final CloudResourceCollectionGrouper _collectionGrouper;
  final CloudMediaTreeResolver _mediaTreeResolver;
  final CloudDirectoryScopeTreeBuilder _directoryScopeTreeBuilder;
  final CloudResourceMediaLibraryAdapter _mediaLibraryAdapter;
  final CloudResourceTmdbFacade _tmdbFacade = const CloudResourceTmdbFacade();
  late final CloudEpisodeMatchService _episodeMatchService;
  late final TmdbApiKeyProvider _tmdbApiKeyProvider;
  late final TmdbClientContextRegistry _tmdbClientContextRegistry;
  final CloudGenreFilter _genreFilter = const CloudGenreFilter();
  final Map<String, CloudMediaIndexItem> _indexedItems =
      <String, CloudMediaIndexItem>{};
  final Map<String, List<String>> _customTagsByResourceKey =
      <String, List<String>>{};
  final Set<String> _selectedGenres = <String>{};
  List<CloudHiddenVideo> _hiddenVideos = <CloudHiddenVideo>[];
  int _hiddenVideosRevision = 0;
  List<CloudWorkIdentity> _works = <CloudWorkIdentity>[];
  CloudMediaTree? _mediaTree;
  final Map<String, List<MediaLibrarySeries>> _mediaLibrarySeriesBySource =
      <String, List<MediaLibrarySeries>>{};
  List<CloudSource> _mediaLibrarySources = const <CloudSource>[];
  final ChangeNotifier _mediaLibraryNotifier = ChangeNotifier();

  List<CloudSource> sources = <CloudSource>[];
  List<CloudFileEntry> entries = <CloudFileEntry>[];
  CloudSource? selectedSource;
  bool loading = false;
  bool scanning = false;
  int scannedDirectories = 0;
  String? currentScanPath;
  bool autoOrganizing = false;
  String query = '';
  String? errorMessage;
  String? currentDirectoryScope;

  int _generation = 0;
  bool _disposed = false;
  CloudScanCancellationToken? _scanToken;
  Future<void>? _scanFuture;
  CloudDirectoryScopeTree? _directoryScopeTreeCache;
  CloudResourceCollection? _collectionCache;
  int? _collectionMinSizeBytes;
  int _resourceTmdbRecordsRevision = 0;
  int _workTmdbRecordsRevision = 0;
  bool _resourcesInitialized = false;
  bool _sourceLoadFailed = false;
  Future<void>? _resourcesLoadFuture;
  bool _mediaLibrarySnapshotInitialized = false;
  Future<void>? _mediaLibraryReloadFuture;
  int _mediaLibraryReloadGeneration = 0;

  Future<void> get scanCompletion => _scanFuture ?? Future<void>.value();

  Map<String, CloudResourceTmdbRecord> get tmdbRecords =>
      _tmdbCoordinator?.records ?? const <String, CloudResourceTmdbRecord>{};

  Map<String, CloudWorkTmdbRecord> get workTmdbRecords =>
      _workTmdbCoordinator?.recordsByWorkKey ??
      const <String, CloudWorkTmdbRecord>{};

  CloudMediaLibrary get mediaLibrarySnapshot => CloudMediaLibrary(
        series: <MediaLibrarySeries>[
          for (final source in _mediaLibrarySources)
            ...?_mediaLibrarySeriesBySource[source.id],
        ],
        filters: <MediaLibrarySourceFilter>[
          const MediaLibrarySourceFilter('all', '全部', null),
          for (final source in _mediaLibrarySources)
            MediaLibrarySourceFilter(
              source.id,
              source.name,
              MediaSourceKind.cloud,
            ),
        ],
      );

  Listenable get mediaLibrarySnapshotListenable => _mediaLibraryNotifier;

  List<CloudWorkIdentity> get works =>
      List<CloudWorkIdentity>.unmodifiable(_works);

  List<CloudHiddenVideo> get hiddenVideos =>
      List<CloudHiddenVideo>.unmodifiable(_hiddenVideos);

  Set<String> get selectedGenres => Set<String>.unmodifiable(_selectedGenres);

  Set<String> get tmdbScrapingKeys =>
      _workTmdbCoordinator?.scrapingWorkKeys ??
      _tmdbCoordinator?.scrapingKeys ??
      const <String>{};

  int get tmdbCompletedCount =>
      _workTmdbCoordinator?.completedCount ??
      _tmdbCoordinator?.completedCount ??
      0;
  int get tmdbTotalCount =>
      _workTmdbCoordinator?.totalCount ?? _tmdbCoordinator?.totalCount ?? 0;
  TmdbScrapeOptions get tmdbScrapeOptions =>
      _workTmdbCoordinator?.options ??
      _tmdbCoordinator?.options ??
      const TmdbScrapeOptions.defaults();

  bool get isCurrentDirectoryConfiguredRoot => false;

  // ==== 以下成员由各职责 mixin（part 文件）提供实现 ====
  // 跨分组调用统一经由基类声明，保证 mixin 之间的可见性。

  CloudDirectoryScopeTree get _directoryScopeTree;
  bool _isHiddenEntry(CloudFileEntry entry);
  bool _isHidden({
    required String sourceId,
    required String remoteId,
    required String remotePath,
  });
  CloudMediaIndexItem? _indexedItemFor(CloudFileEntry entry);
  void _reconcileDirectoryScope();
  void _reconcileSelectedGenres();
  Future<void> reloadMediaLibrarySnapshot({bool force = false});
  Future<void> refresh();
  Future<void> _loadSnapshot(CloudSource source, int generation);
  void _startScan(CloudSource source, int generation);
  CloudResourceTmdbTarget tmdbTargetFor(CloudFileEntry entry);
  void _scheduleTmdb(
    CloudSource source,
    List<CloudFileEntry> loadedEntries,
  );
  void _handleTmdbChange();

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _invalidateCollection() {
    _collectionCache = null;
    _collectionMinSizeBytes = null;
  }

  void _invalidateDirectoryScopeTree() {
    _directoryScopeTreeCache = null;
    _invalidateCollection();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _scanToken?.cancel();
    _tmdbCoordinator?.removeListener(_handleTmdbChange);
    _workTmdbCoordinator?.removeListener(_handleTmdbChange);
    _mediaLibraryNotifier.dispose();
    super.dispose();
  }
}

/// 对外网盘资源控制器：组合基类状态与各职责 mixin。
/// 构造参数与公开 API 与拆分前完全一致。
class CloudResourcesController extends _CloudResourcesControllerBase
    with
        _CloudDirectoryScopeMixin,
        _CloudFilterTagsMixin,
        _CloudHiddenVideosMixin,
        _CloudSourcesMixin,
        _CloudScanMixin,
        _CloudTmdbEntryMixin,
        _CloudTmdbWorkMixin,
        _CloudEpisodeMatchMixin,
        _CloudAutoOrganizeMixin {
  CloudResourcesController({
    required super.repository,
    required super.credentialStore,
    super.providerRegistry,
    super.tmdbCoordinator,
    super.workTmdbCoordinator,
    super.autoOrganizer,
    super.minRecognizedVideoSizeBytesProvider,
    super.collectionGrouper,
    super.mediaIndexRepository,
    super.workTmdbRepository,
    super.mediaTagRepository,
    super.hiddenVideoRepository,
    super.mediaIndexer,
    super.mediaTreeResolver,
    super.directoryScopeTreeBuilder,
    super.mediaLibraryAdapter,
    super.episodeMatchService,
    super.tmdbApiKeyProvider,
    super.tmdbClientContextRegistry,
  });
}
