import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'package:kanyingyin/repositories/cloud_hidden_video_repository.dart';
import 'package:kanyingyin/repositories/cloud_episode_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_tag_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
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

class CloudResourcesController extends ChangeNotifier {
  CloudResourcesController({
    required CloudSourceRepository repository,
    required CloudCredentialStore credentialStore,
    CloudProviderRegistry? providerRegistry,
    CloudResourceTmdbCoordinator? tmdbCoordinator,
    CloudWorkTmdbCoordinator? workTmdbCoordinator,
    CloudResourceAutoOrganizer? autoOrganizer,
    int Function()? minRecognizedVideoSizeBytesProvider,
    CloudResourceCollectionGrouper? collectionGrouper,
    CloudMediaIndexRepository? mediaIndexRepository,
    ICloudMediaTagRepository? mediaTagRepository,
    ICloudHiddenVideoRepository? hiddenVideoRepository,
    CloudMediaIndexer? mediaIndexer,
    CloudMediaTreeResolver? mediaTreeResolver,
    CloudDirectoryScopeTreeBuilder? directoryScopeTreeBuilder,
    CloudEpisodeMatchService? episodeMatchService,
    TmdbApiKeyProvider? tmdbApiKeyProvider,
    TmdbClientContextRegistry? tmdbClientContextRegistry,
  })  : _repository = repository,
        _credentialStore = credentialStore,
        _mediaIndexRepository =
            mediaIndexRepository ?? CloudMediaIndexRepository(),
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
  List<CloudWorkIdentity> _works = <CloudWorkIdentity>[];
  CloudMediaTree? _mediaTree;

  List<CloudSource> sources = <CloudSource>[];
  List<CloudFileEntry> entries = <CloudFileEntry>[];
  CloudSource? selectedSource;
  @Deprecated('网盘资源页已改为来源级海报墙')
  CloudRemoteRef? currentDirectory;
  @Deprecated('网盘资源页已改为来源级海报墙')
  bool isVirtualRoot = false;
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

  bool get canGoBack => false;
  Future<void> get scanCompletion => _scanFuture ?? Future<void>.value();

  Map<String, CloudResourceTmdbRecord> get tmdbRecords =>
      _tmdbCoordinator?.records ?? const <String, CloudResourceTmdbRecord>{};

  Map<String, CloudWorkTmdbRecord> get workTmdbRecords =>
      _workTmdbCoordinator?.recordsByWorkKey ??
      const <String, CloudWorkTmdbRecord>{};

  List<CloudWorkIdentity> get works =>
      List<CloudWorkIdentity>.unmodifiable(_works);

  List<CloudHiddenVideo> get hiddenVideos =>
      List<CloudHiddenVideo>.unmodifiable(_hiddenVideos);

  Set<String> get selectedGenres => Set<String>.unmodifiable(_selectedGenres);

  List<String> get availableGenres =>
      _genreFilter.availableGenres(_indexedItems.values);

  List<String> get availableCustomTags {
    final tags = <String>{};
    for (final item in _indexedItems.values) {
      tags.addAll(_customTagsForItem(item));
    }
    return tags.toList(growable: false)..sort();
  }

  List<String> get availableTags {
    final tags = <String>{
      ...availableGenres,
      ...availableCustomTags,
    };
    return tags.toList(growable: false)..sort();
  }

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

  CloudResourceTmdbRecord? get currentDirectoryTmdbRecord => null;

  CloudDirectoryScopeTree get _directoryScopeTree =>
      _directoryScopeTreeCache ??= _directoryScopeTreeBuilder(
        rootPaths: selectedSource?.remoteRoots.map((root) => root.path) ??
            const <String>[],
        mediaPaths: _indexedItems.values.map((item) => item.remotePath),
      );

  List<CloudDirectoryScopeItem> get directoryScopeChildren =>
      _directoryScopeTree.childrenOf(currentDirectoryScope);

  String get directoryScopeAddress => currentDirectoryScope ?? '/';

  List<CloudMediaIndexItem> get visibleIndexedItems {
    final scopeTree = _directoryScopeTree;
    return _genreFilter
        .apply(
          _indexedItems.values,
          _selectedGenres,
          customTagsFor: _customTagsForItem,
        )
        .where(
          (item) =>
              !_isHidden(
                sourceId: item.sourceId,
                remoteId: item.remoteId,
                remotePath: item.remotePath,
              ) &&
              scopeTree.contains(
                item.remotePath,
                currentDirectoryScope,
              ),
        )
        .toList(growable: false);
  }

  List<CloudFileEntry> get visibleEntries {
    final keyword = query.trim().toLowerCase();
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    final scopeTree = _directoryScopeTree;
    final filtered = entries
        .where(
          (entry) =>
              !_isHiddenEntry(entry) &&
              LocalVideoFileTypes.isRecognizedVideo(
                entry.name,
                size: entry.size,
                minSizeBytes: minSizeBytes,
              ) &&
              scopeTree.contains(
                entry.remotePath,
                currentDirectoryScope,
              ) &&
              (keyword.isEmpty || entry.name.toLowerCase().contains(keyword)),
        )
        .toList(growable: false);
    filtered.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(second.name.toLowerCase()),
    );
    return filtered;
  }

  CloudResourceCollection get collection {
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    final cached = _collectionCache;
    if (cached != null && _collectionMinSizeBytes == minSizeBytes) {
      return cached;
    }
    _collectionCache = null;
    _collectionMinSizeBytes = minSizeBytes;
    final scopedItems = visibleIndexedItems;
    if (_workTmdbCoordinator != null && _works.isNotEmpty) {
      final visibleWorkKeys =
          scopedItems.map((item) => item.workKey).whereType<String>().toSet();
      return _collectionCache = _collectionGrouper.group(
        items: scopedItems,
        works: _works
            .where((work) => visibleWorkKeys.contains(work.workKey))
            .toList(growable: false),
        recordsByWorkKey: workTmdbRecords,
        query: query,
      );
    }
    final scopeTree = _directoryScopeTree;
    return _collectionCache = _collectionGrouper.group(
      sourceId: selectedSource?.id ?? '',
      entries: entries
          .where(
            (entry) =>
                !_isHiddenEntry(entry) &&
                _matchesSelectedGenres(entry) &&
                scopeTree.contains(
                  entry.remotePath,
                  currentDirectoryScope,
                ),
          )
          .toList(growable: false),
      records: tmdbRecords,
      minSizeBytes: minSizeBytes,
      query: query,
    );
  }

  List<CloudFileEntry> get tmdbEntriesForSelectedSource {
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    return entries
        .where(
          (entry) => LocalVideoFileTypes.isRecognizedVideo(
            entry.name,
            size: entry.size,
            minSizeBytes: minSizeBytes,
          ),
        )
        .toList(growable: false);
  }

  @Deprecated('请使用 tmdbEntriesForSelectedSource')
  List<CloudFileEntry> get tmdbEntriesForCurrentDirectory =>
      tmdbEntriesForSelectedSource;

  CloudRemoteRef? subtitleFor(CloudFileEntry video) =>
      _indexedItemFor(video)?.subtitleRefs.firstOrNull;

  bool hasSubtitle(CloudFileEntry video) =>
      _indexedItemFor(video)?.subtitleRefs.isNotEmpty == true;

  Future<void> hideVideos(Iterable<CloudFileEntry> videos) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    final nextByIdentity = <String, CloudHiddenVideo>{
      for (final record in _hiddenVideos) record.identityKey: record,
    };
    for (final video in videos) {
      final record = CloudHiddenVideo.fromEntry(
        sourceId: source.id,
        entry: video,
      );
      nextByIdentity[record.identityKey] = record;
    }
    final next = nextByIdentity.values.toList(growable: false);
    if (_sameHiddenVideos(_hiddenVideos, next)) return;
    await _hiddenVideoRepository.replaceSource(source.id, next);
    if (selectedSource?.id != source.id) return;
    _hiddenVideos = next;
    _invalidateCollection();
    _notify();
  }

  Future<void> restoreHiddenVideo(CloudHiddenVideo record) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    if (record.sourceId != source.id) {
      throw ArgumentError.value(record, 'record', '隐藏视频不属于当前网盘来源');
    }
    final next = _hiddenVideos
        .where((candidate) => candidate.identityKey != record.identityKey)
        .toList(growable: false);
    if (next.length == _hiddenVideos.length) return;
    await _hiddenVideoRepository.replaceSource(source.id, next);
    if (selectedSource?.id != source.id) return;
    _hiddenVideos = next;
    _invalidateCollection();
    _notify();
  }

  Future<void> restoreAllHiddenVideos() async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    if (_hiddenVideos.isEmpty) return;
    await _hiddenVideoRepository.clearSource(source.id);
    if (selectedSource?.id != source.id) return;
    _hiddenVideos = <CloudHiddenVideo>[];
    _invalidateCollection();
    _notify();
  }

  Future<void> load({bool startScan = true}) =>
      _loadSources(startScan: startScan);

  Future<void> reloadSourcesAndSnapshot({String? preferredSourceId}) async {
    _scanToken?.cancel();
    await scanCompletion;
    final previousSources = List<CloudSource>.from(sources);
    final previousEntries = List<CloudFileEntry>.from(entries);
    final previousSelectedSource = selectedSource;
    final previousCurrentDirectory = currentDirectory;
    final previousIsVirtualRoot = isVirtualRoot;
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
    await _loadSources(
      startScan: false,
      preferredSourceId: preferredSourceId,
    );
    if (errorMessage != '网盘来源加载失败') return;
    sources = previousSources;
    entries = previousEntries;
    selectedSource = previousSelectedSource;
    currentDirectory = previousCurrentDirectory;
    isVirtualRoot = previousIsVirtualRoot;
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
    errorMessage = null;
    _notify();
    try {
      final loadedSources = (await _repository.getAll())
          .where((source) => source.enabled)
          .toList(growable: false);
      if (!_isCurrent(generation)) return;
      sources = loadedSources;
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
    } on Object {
      if (!_isCurrent(generation)) return;
      sources = <CloudSource>[];
      selectedSource = null;
      currentDirectory = null;
      entries = <CloudFileEntry>[];
      _indexedItems.clear();
      _customTagsByResourceKey.clear();
      _selectedGenres.clear();
      _hiddenVideos = <CloudHiddenVideo>[];
      _works = <CloudWorkIdentity>[];
      _mediaTree = null;
      currentDirectoryScope = null;
      _invalidateDirectoryScopeTree();
      loading = false;
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
    currentDirectory = null;
    isVirtualRoot = false;
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
    try {
      final hiddenVideos = await _hiddenVideoRepository.getBySource(source.id);
      if (!_isCurrent(generation) || selectedSource?.id != source.id) return;
      _hiddenVideos = hiddenVideos;
    } on Object {
      if (!_isCurrent(generation) || selectedSource?.id != source.id) return;
      _hiddenVideos = <CloudHiddenVideo>[];
      hiddenVideoWarning = '隐藏视频设置读取失败，已显示全部视频';
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
    _reconcileSelectedGenres();
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
  }

  void _startScan(CloudSource source, int generation) {
    final future = _scanSelectedSource(source, generation);
    _scanFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_scanFuture, future)) _scanFuture = null;
      }),
    );
  }

  Future<void> _scanSelectedSource(
    CloudSource source,
    int generation,
  ) async {
    final token = CloudScanCancellationToken();
    _scanToken = token;
    if (_isCurrent(generation)) {
      scanning = true;
      scannedDirectories = 0;
      currentScanPath = null;
      errorMessage = null;
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
      await _loadSnapshot(source, generation);
      if (!_isCurrent(generation)) return;
      if (result.failures > 0) {
        errorMessage = '部分网盘目录扫描失败，已保留可用索引';
      }
      _scheduleTmdb(source, entries);
    } on CloudScanInProgressException {
      if (!_isCurrent(generation)) return;
      errorMessage = '该来源正在扫描，正在显示上次索引';
    } on CloudDriveException catch (error) {
      if (!_isCurrent(generation)) return;
      errorMessage = _providerRegistry.errorMessage(source.type, error);
    } on Object {
      if (!_isCurrent(generation)) return;
      errorMessage = '网盘媒体扫描失败，已保留上次索引';
    } finally {
      await client?.close();
      if (_isCurrent(generation)) {
        scanning = false;
        currentScanPath = null;
        _notify();
      }
    }
  }

  @Deprecated('网盘资源页已改为来源级海报墙')
  Future<void> openDirectory(CloudRemoteRef directory) async {}

  @Deprecated('网盘资源页已改为来源级海报墙')
  Future<void> goBack() async {}

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

  void _reconcileDirectoryScope() {
    final current = currentDirectoryScope;
    if (current == null || _directoryScopeTree.hasDirectory(current)) return;
    currentDirectoryScope = null;
  }

  Future<void> refresh() async {
    if (loading) return;
    final source = selectedSource;
    if (source == null) return;
    if (scanning) return scanCompletion;
    final generation = ++_generation;
    _startScan(source, generation);
    await scanCompletion;
  }

  void setQuery(String value) {
    if (query == value) return;
    query = value;
    _invalidateCollection();
    _notify();
  }

  void toggleGenre(String genre) {
    final normalized = genre.trim();
    if (normalized.isEmpty || !availableTags.contains(normalized)) return;
    if (!_selectedGenres.remove(normalized)) {
      _selectedGenres.add(normalized);
    }
    _invalidateCollection();
    _notify();
  }

  void clearGenres() {
    if (_selectedGenres.isEmpty) return;
    _selectedGenres.clear();
    _invalidateCollection();
    _notify();
  }

  List<String> customTagsForGroup(CloudResourceMediaGroup group) {
    final key = _customTagKeyForGroup(group);
    return List<String>.unmodifiable(
      _customTagsByResourceKey[key] ?? const <String>[],
    );
  }

  Future<void> saveCustomTags(
    CloudResourceMediaGroup group,
    Iterable<String> tags,
  ) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    final key = _customTagKeyForGroup(group);
    await _mediaTagRepository.saveForResource(source.id, key, tags);
    if (selectedSource?.id != source.id) return;
    final saved = await _mediaTagRepository.getBySource(source.id);
    _customTagsByResourceKey
      ..clear()
      ..addAll(saved);
    _reconcileSelectedGenres();
    _invalidateCollection();
    _notify();
  }

  CloudResourceTmdbTarget tmdbTargetFor(CloudFileEntry entry) {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    final key = cloudResourceTmdbKey(
      sourceId: source.id,
      remoteId: entry.id,
      remotePath: entry.remotePath,
    );
    return _tmdbFacade.targetFor(
      source: source,
      entry: entry,
      record: tmdbRecords[key],
      indexed: _indexedItemFor(entry),
    );
  }

  CloudResourceTmdbRecord? tmdbRecordFor(CloudFileEntry entry) {
    return tmdbRecords[tmdbTargetFor(entry).stableKey];
  }

  TmdbMatchDraft tmdbDraftFor(CloudFileEntry entry) {
    return _tmdbFacade.draftFor(
      entry: entry,
      record: tmdbRecordFor(entry),
      indexed: _indexedItemFor(entry),
    );
  }

  CloudWorkIdentity workForGroup(CloudResourceMediaGroup group) {
    return _works.firstWhere(
      (work) => work.workKey == group.workKey,
      orElse: () => throw StateError('找不到季度卡对应的作品'),
    );
  }

  List<CloudWorkIdentity> worksForGroup(CloudResourceMediaGroup group) {
    final keys =
        group.workKeys.isEmpty ? <String>[group.workKey] : group.workKeys;
    final byKey = <String, CloudWorkIdentity>{
      for (final work in _works) work.workKey: work,
    };
    return keys.map((key) => byKey[key]).whereType<CloudWorkIdentity>().toList(
          growable: false,
        );
  }

  CloudWorkTmdbRecord? workRecordForGroup(CloudResourceMediaGroup group) {
    return workTmdbRecords[group.workKey];
  }

  TmdbMatchDraft tmdbDraftForGroup(CloudResourceMediaGroup group) {
    final work = workForGroup(group);
    final record = workRecordForGroup(group);
    final title = record?.scrapeTitleOverride?.trim().isNotEmpty == true
        ? record!.scrapeTitleOverride!.trim()
        : record?.metadata?.title.trim().isNotEmpty == true
            ? record!.metadata!.title.trim()
            : work.displayTitle;
    return TmdbMatchDraft(
      originalName: work.remoteName,
      searchTitle: title,
      mediaTypeMode:
          work.seasons.isEmpty ? TmdbMediaTypeMode.auto : TmdbMediaTypeMode.tv,
      seasonNumber: group.seasonNumber,
    );
  }

  Future<List<ManualEpisodeMatchItem>> manualEpisodeItemsForGroup(
    CloudResourceMediaGroup group,
  ) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    final resourceIds =
        group.videos.map((video) => video.id).toSet().toList(growable: false);
    if (resourceIds.isEmpty) throw StateError('当前分组没有可匹配的视频');
    return _episodeMatchService.loadMatchItems(
      sourceId: source.id,
      resourceIds: resourceIds,
      expectedSeriesName: group.seriesName,
      selectedSeasonNumber: group.seasonNumber,
    );
  }

  Future<ManualEpisodeMatchController> manualEpisodeMatchControllerForGroup({
    required CloudResourceMediaGroup group,
    required TmdbMetadata selectedSeries,
  }) async {
    final apiKey = _tmdbApiKeyProvider.read().trim();
    if (apiKey.isEmpty) {
      throw StateError('请先在设置中填写 TMDB API Key');
    }
    if (selectedSeries.mediaType != TmdbMediaType.tv) {
      throw StateError('剧集匹配只支持 TMDB 电视剧');
    }
    final client = _tmdbClientContextRegistry.contextFor(apiKey).client;
    if (client is! ITmdbClientCapabilities) {
      throw StateError('当前 TMDB 客户端不支持季度详情');
    }
    final capabilities = client as ITmdbClientCapabilities;
    return ManualEpisodeMatchController(
      selectedSeries: selectedSeries,
      items: await manualEpisodeItemsForGroup(group),
      loadDetails: (id, mediaType, language) =>
          client.details(id, mediaType, language: language),
      loadSeason: (id, seasonNumber, language) => capabilities.seasonDetails(
        id,
        seasonNumber,
        language: language,
      ),
    );
  }

  Future<CloudEpisodeMatchSaveOutcome> saveManualEpisodeAssignments({
    required CloudResourceMediaGroup group,
    required List<ManualEpisodeAssignment> assignments,
    required TmdbMetadata metadata,
    required int selectedSeasonNumber,
  }) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    final outcome = await _episodeMatchService.save(
      sourceId: source.id,
      resourceIds: group.videos.map((video) => video.id).toSet(),
      assignments: assignments,
      metadata: metadata,
      selectedSeasonNumber: selectedSeasonNumber,
    );
    if (selectedSource?.id != source.id) return outcome;

    final workCoordinator = _workTmdbCoordinator;
    final works = _works
        .where(
          (work) => group.workKeys.contains(work.workKey),
        )
        .toList(growable: false);
    try {
      if (workCoordinator != null && works.isNotEmpty) {
        for (final work in works) {
          await workCoordinator.selectCandidate(
            _workForManualEpisodeSelection(
              work,
              assignments: assignments,
              selectedSeasonNumber: selectedSeasonNumber,
            ),
            metadata,
            options: tmdbScrapeOptions.copyWith(
              mediaTypeMode: TmdbMediaTypeMode.tv,
            ),
          );
        }
      } else if (_tmdbCoordinator != null) {
        await _tmdbCoordinator.select(
          tmdbTargetFor(group.anchor),
          metadata,
          options: tmdbScrapeOptions.copyWith(
            mediaTypeMode: TmdbMediaTypeMode.tv,
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        'CloudResourcesController: 作品元数据同步失败，已保留剧集匹配结果',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (selectedSource?.id != source.id) return outcome;
    await _loadSnapshot(source, _generation);
    _invalidateCollection();
    _notify();
    return outcome;
  }

  CloudWorkIdentity _workForManualEpisodeSelection(
    CloudWorkIdentity work, {
    required List<ManualEpisodeAssignment> assignments,
    required int selectedSeasonNumber,
  }) {
    if (work.seasons.length != 1) return work;
    final season = work.seasons.single;
    if (season.seasonNumber == selectedSeasonNumber ||
        season.episodes.isEmpty) {
      return work;
    }
    final assignmentsById = <String, ManualEpisodeAssignment>{
      for (final assignment in assignments) assignment.resourceId: assignment,
    };
    final remappedEpisodes = <CloudEpisodeIdentity>[];
    for (final episode in season.episodes) {
      final assignment = assignmentsById[episode.entry.id];
      if (assignment?.mode != ManualEpisodeAssignmentMode.mapped ||
          assignment?.seasonNumber != selectedSeasonNumber ||
          assignment?.episodeNumber == null) {
        return work;
      }
      remappedEpisodes.add(
        CloudEpisodeIdentity(
          entry: episode.entry,
          remoteName: episode.remoteName,
          displayName: episode.displayName,
          seasonNumber: selectedSeasonNumber,
          episodeNumber: assignment!.episodeNumber!,
          releaseTags: episode.releaseTags,
        ),
      );
    }
    return CloudWorkIdentity(
      sourceId: work.sourceId,
      workKey: work.workKey,
      root: work.root,
      remoteName: work.remoteName,
      displayTitle: work.displayTitle,
      titleCandidates: work.titleCandidates,
      seasons: <CloudSeasonIdentity>[
        CloudSeasonIdentity(
          workKey: season.workKey,
          seasonNumber: selectedSeasonNumber,
          displayName: '${work.displayTitle} 第 $selectedSeasonNumber 季',
          remoteDirectories: season.remoteDirectories,
          episodes: remappedEpisodes,
          year: season.year,
        ),
      ],
      standaloneVideos: work.standaloneVideos,
      standaloneReleaseTags: work.standaloneReleaseTags,
    );
  }

  Future<TmdbRankedResult> searchWorkTmdb(
    CloudResourceMediaGroup group,
    CloudResourceTmdbSearchRequest request,
  ) {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 刮削服务不可用');
    return coordinator.searchPrepared(workForGroup(group), request);
  }

  Future<CloudWorkTmdbSelectionOutcome> applyWorkTmdbCandidate(
    CloudResourceMediaGroup group,
    TmdbRankedCandidate candidate, {
    required TmdbScrapeOptions options,
  }) async {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 刮削服务不可用');
    CloudWorkTmdbSelectionOutcome? first;
    for (final work in worksForGroup(group)) {
      final outcome = await coordinator.selectPrepared(
        work,
        candidate,
        options: options,
      );
      first ??= outcome;
    }
    if (first == null) {
      throw StateError('找不到季度卡对应的作品');
    }
    return first;
  }

  Future<List<TmdbMetadata>> rematchWork(
    CloudResourceMediaGroup group, {
    TmdbScrapeOptions? options,
  }) async {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 刮削服务不可用');
    final works = worksForGroup(group);
    if (works.isEmpty) throw StateError('找不到季度卡对应的作品');
    final candidates = <String, TmdbMetadata>{};
    for (final work in works) {
      final results = await coordinator.rematch(work, options: options);
      for (final metadata in results) {
        candidates.putIfAbsent(
          '${metadata.mediaType.name}:${metadata.id}',
          () => metadata,
        );
      }
    }
    return candidates.values.toList(growable: false);
  }

  Future<CloudWorkTmdbOutcome> scrapeWork(
    CloudResourceMediaGroup group, {
    TmdbScrapeOptions? options,
  }) async {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 刮削服务不可用');
    CloudWorkTmdbOutcome? first;
    for (final work in worksForGroup(group)) {
      final outcome = await coordinator.scrape(work, options: options);
      first ??= outcome;
    }
    if (first == null) throw StateError('找不到季度卡对应的作品');
    return first;
  }

  Future<CloudWorkTmdbRecord> saveScrapeTitle(
    CloudResourceMediaGroup group,
    String title,
  ) async {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 元数据服务不可用');
    CloudWorkTmdbRecord? first;
    for (final work in worksForGroup(group)) {
      final record = await coordinator.saveScrapeTitle(work, title);
      first ??= record;
    }
    if (first == null) throw StateError('找不到季度卡对应的作品');
    return first;
  }

  Future<CloudWorkTmdbRecord> clearScrapeTitle(
    CloudResourceMediaGroup group,
  ) async {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 元数据服务不可用');
    CloudWorkTmdbRecord? first;
    for (final work in worksForGroup(group)) {
      final record = await coordinator.clearScrapeTitle(work);
      first ??= record;
    }
    if (first == null) throw StateError('找不到季度卡对应的作品');
    return first;
  }

  CloudMediaIndexItem detailsFor(CloudFileEntry video) {
    final item = _indexedItemFor(video);
    if (item == null) throw StateError('找不到媒体索引详情');
    return item;
  }

  Future<CloudResourceTmdbSearchOutcome> searchTmdb(
    CloudFileEntry entry,
    CloudResourceTmdbSearchRequest request,
  ) {
    final coordinator = _tmdbCoordinator;
    if (coordinator == null) throw StateError('TMDB 刮削服务不可用');
    return coordinator.searchPrepared(tmdbTargetFor(entry), request);
  }

  Future<CloudResourceTmdbSelectionOutcome> applyTmdbCandidate(
    CloudFileEntry entry,
    TmdbRankedCandidate candidate, {
    required TmdbScrapeOptions options,
  }) async {
    final coordinator = _tmdbCoordinator;
    if (coordinator == null) throw StateError('TMDB 刮削服务不可用');
    final propagationCandidates = entries
        .where(
          (candidate) =>
              !candidate.isDirectory &&
              LocalVideoFileTypes.isVideoPath(candidate.name),
        )
        .map(tmdbTargetFor)
        .toList(growable: false);
    return coordinator.selectPrepared(
      tmdbTargetFor(entry),
      candidate,
      options: options,
      propagationCandidates: propagationCandidates,
    );
  }

  Future<CloudResourceTmdbOutcome> scrapeTmdb(
    CloudFileEntry entry, {
    TmdbScrapeOptions? options,
  }) {
    final coordinator = _tmdbCoordinator;
    if (coordinator == null) throw StateError('TMDB 刮削服务不可用');
    return coordinator.scrape(tmdbTargetFor(entry), options: options);
  }

  Future<CloudResourceTmdbOutcome> rematchTmdb(
    CloudFileEntry entry, {
    TmdbScrapeOptions? options,
  }) {
    final coordinator = _tmdbCoordinator;
    if (coordinator == null) throw StateError('TMDB 刮削服务不可用');
    return coordinator.rematch(tmdbTargetFor(entry), options: options);
  }

  Future<CloudResourceTmdbRecord> selectTmdbCandidate(
    CloudFileEntry entry,
    TmdbMetadata candidate, {
    TmdbScrapeOptions? options,
  }) {
    final coordinator = _tmdbCoordinator;
    if (coordinator == null) throw StateError('TMDB 刮削服务不可用');
    return coordinator.select(
      tmdbTargetFor(entry),
      candidate,
      options: options,
    );
  }

  Future<CloudResourceTmdbRecord> saveCustomTitle(
    CloudFileEntry entry,
    String title,
  ) {
    final coordinator = _tmdbCoordinator;
    if (coordinator == null) throw StateError('TMDB 元数据服务不可用');
    return coordinator.saveCustomTitle(tmdbTargetFor(entry), title);
  }

  Future<CloudResourceTmdbRecord> clearCustomTitle(CloudFileEntry entry) {
    final coordinator = _tmdbCoordinator;
    if (coordinator == null) throw StateError('TMDB 元数据服务不可用');
    return coordinator.clearCustomTitle(tmdbTargetFor(entry));
  }

  Future<CloudResourceAutoOrganizeSummary> autoOrganizeSelectedSource({
    void Function(CloudResourceAutoOrganizeProgress progress)? onProgress,
  }) async {
    final source = selectedSource;
    final coordinator = _tmdbCoordinator;
    if (source == null || coordinator == null) {
      throw StateError('当前没有可整理的网盘来源');
    }
    if (!coordinator.hasApiKey) {
      throw StateError('请先在设置中填写 TMDB API Key');
    }
    if (coordinator.isScraping) {
      throw StateError('当前目录正在刮削，请稍后再试');
    }
    if (autoOrganizing) throw StateError('自动整理正在进行');

    autoOrganizing = true;
    _notify();
    final client = _providerRegistry.createClient(source, _credentialStore);
    try {
      final discovery = await _autoOrganizer.discover(
        source: source,
        client: client,
        onProgress: (scannedDirectories, discoveredCandidates) {
          onProgress?.call(
            CloudResourceAutoOrganizeProgress(
              phase: CloudResourceAutoOrganizePhase.scanning,
              scannedDirectories: scannedDirectories,
              discoveredTargets: discoveredCandidates,
              completedTargets: 0,
              totalTargets: 0,
            ),
          );
        },
      );
      final targets = <CloudResourceTmdbTarget>[];
      var matched = 0;
      var skipped = 0;
      final now = DateTime.now();
      for (final target in discovery.candidates) {
        try {
          final application = await coordinator.applySeriesRule(target);
          if (application != null) {
            matched++;
            continue;
          }
        } on Object {
          // 规则读取失败时继续使用原有 TMDB 整理流程。
        }
        final record = coordinator.records[target.stableKey];
        final sameName = record?.displayName == target.displayName;
        final cachedMatched = record?.status == CloudResourceTmdbStatus.matched;
        final recentlyUnmatched =
            record?.status == CloudResourceTmdbStatus.unmatched &&
                record!.checkedAt
                    .add(CloudResourceTmdbCoordinator.unmatchedRetryInterval)
                    .isAfter(now);
        if ((sameName && (cachedMatched || recentlyUnmatched)) ||
            coordinator.scrapingKeys.contains(target.stableKey)) {
          skipped++;
        } else {
          targets.add(target);
        }
      }

      var completed = matched;
      var pending = 0;
      var noResult = 0;
      var failed = discovery.failedDirectories;
      final totalTargets = matched + targets.length;
      onProgress?.call(
        CloudResourceAutoOrganizeProgress(
          phase: CloudResourceAutoOrganizePhase.scraping,
          scannedDirectories: discovery.scannedDirectories,
          discoveredTargets: discovery.candidates.length,
          completedTargets: completed,
          totalTargets: totalTargets,
        ),
      );
      for (final target in targets) {
        try {
          final outcome = await coordinator.scrape(target);
          if (outcome.selected != null) {
            matched++;
          } else if (outcome.candidates.isNotEmpty) {
            pending++;
          } else {
            noResult++;
          }
        } on Object {
          failed++;
        } finally {
          completed++;
          onProgress?.call(
            CloudResourceAutoOrganizeProgress(
              phase: CloudResourceAutoOrganizePhase.scraping,
              scannedDirectories: discovery.scannedDirectories,
              discoveredTargets: discovery.candidates.length,
              completedTargets: completed,
              totalTargets: totalTargets,
            ),
          );
        }
      }
      return CloudResourceAutoOrganizeSummary(
        matched: matched,
        pending: pending,
        noResult: noResult,
        failed: failed,
        skipped: skipped,
      );
    } finally {
      await client.close();
      autoOrganizing = false;
      _notify();
    }
  }

  void _scheduleTmdb(
    CloudSource source,
    List<CloudFileEntry> loadedEntries,
  ) {
    final workCoordinator = _workTmdbCoordinator;
    final tree = _mediaTree;
    if (workCoordinator != null && tree != null) {
      unawaited(workCoordinator.loadAndSchedule(tree).catchError((_) {}));
      return;
    }
    final coordinator = _tmdbCoordinator;
    if (coordinator == null) return;
    unawaited(
      coordinator
          .loadAndSchedule(
            CloudResourceDirectoryContext(
              source: source,
              directory: CloudRemoteRef(
                id: 'library:${source.id}',
                path: '/',
              ),
              entries: List<CloudFileEntry>.unmodifiable(loadedEntries),
              isConfiguredRoot: true,
              indexedItemsByKey:
                  Map<String, CloudMediaIndexItem>.unmodifiable(_indexedItems),
            ),
          )
          .catchError((_) {}),
    );
  }

  bool _isHiddenEntry(CloudFileEntry entry) {
    final source = selectedSource;
    if (source == null) return false;
    return _isHidden(
      sourceId: source.id,
      remoteId: entry.id,
      remotePath: entry.remotePath,
    );
  }

  bool _isHidden({
    required String sourceId,
    required String remoteId,
    required String remotePath,
  }) =>
      _hiddenVideos.any(
        (record) => record.matches(
          sourceId: sourceId,
          remoteId: remoteId,
          remotePath: remotePath,
        ),
      );

  static bool _sameHiddenVideos(
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

  CloudMediaIndexItem? _indexedItemFor(CloudFileEntry entry) {
    final source = selectedSource;
    if (source == null) return null;
    return _indexedItems[cloudResourceTmdbKey(
      sourceId: source.id,
      remoteId: entry.id,
      remotePath: entry.remotePath,
    )];
  }

  bool _matchesSelectedGenres(CloudFileEntry entry) {
    if (_selectedGenres.isEmpty) return true;
    final item = _indexedItemFor(entry);
    if (item == null) return false;
    return _genreFilter.apply(
      <CloudMediaIndexItem>[item],
      _selectedGenres,
      customTagsFor: _customTagsForItem,
    ).isNotEmpty;
  }

  void _reconcileSelectedGenres() {
    final retained = _genreFilter.retainAvailable(
      _selectedGenres,
      availableTags,
    );
    if (setEquals(retained, _selectedGenres)) return;
    _selectedGenres
      ..clear()
      ..addAll(retained);
    _invalidateCollection();
  }

  static String _resourceKeyForItem(CloudMediaIndexItem item) =>
      cloudResourceTmdbKey(
        sourceId: item.sourceId,
        remoteId: item.remoteId,
        remotePath: item.remotePath,
      );

  Iterable<String> _customTagsForItem(CloudMediaIndexItem item) sync* {
    final tags = <String>{};
    for (final key in _customTagKeysForItem(item)) {
      tags.addAll(_customTagsByResourceKey[key] ?? const <String>[]);
    }
    yield* tags;
  }

  Iterable<String> _customTagKeysForItem(CloudMediaIndexItem item) sync* {
    final resourceKey = _resourceKeyForItem(item);
    yield resourceKey;
    final workKey = item.workKey?.trim();
    if (workKey != null && workKey.isNotEmpty) {
      yield workKey;
    }

    final record = tmdbRecords[resourceKey];
    final tmdbId = record?.status == CloudResourceTmdbStatus.matched
        ? record?.tmdbId
        : record == null
            ? item.tmdbId
            : null;
    final mediaType = record?.status == CloudResourceTmdbStatus.matched
        ? record?.mediaType
        : record == null
            ? _tmdbMediaTypeForItem(item)
            : null;
    if (tmdbId != null && mediaType != null) {
      yield '${item.sourceId}|tmdb|${mediaType.name}|$tmdbId';
    }

    final normalizedSeriesName =
        CloudSeriesIdentityResolver.normalizeSeriesName(item.seriesName);
    if (normalizedSeriesName.isNotEmpty && item.episodeNumber != null) {
      yield '${item.sourceId}|series|$normalizedSeriesName';
    }
  }

  TmdbMediaType? _tmdbMediaTypeForItem(CloudMediaIndexItem item) {
    return switch (item.mediaType) {
      CloudMediaType.movie => TmdbMediaType.movie,
      CloudMediaType.series ||
      CloudMediaType.episode ||
      CloudMediaType.special =>
        TmdbMediaType.tv,
      CloudMediaType.unknown => null,
    };
  }

  String _customTagKeyForGroup(CloudResourceMediaGroup group) {
    return group.isWorkScoped ? group.workKey : group.stableKey;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _invalidateCollection() {
    _collectionCache = null;
    _collectionMinSizeBytes = null;
  }

  void _invalidateDirectoryScopeTree() {
    _directoryScopeTreeCache = null;
    _invalidateCollection();
  }

  void _handleTmdbChange() {
    final resourceRevision = _tmdbCoordinator?.recordsRevision ?? 0;
    final workRevision = _workTmdbCoordinator?.recordsRevision ?? 0;
    if (resourceRevision != _resourceTmdbRecordsRevision ||
        workRevision != _workTmdbRecordsRevision) {
      _resourceTmdbRecordsRevision = resourceRevision;
      _workTmdbRecordsRevision = workRevision;
      _syncIndexedTmdbMetadata();
      _reconcileSelectedGenres();
      _invalidateCollection();
    }
    _notify();
  }

  void _syncIndexedTmdbMetadata() {
    final sourceId = selectedSource?.id;
    if (sourceId == null || _indexedItems.isEmpty) return;

    final exactResourceRecords = <String, CloudResourceTmdbRecord>{};
    final directoryResourceRecords = <CloudResourceTmdbRecord>[];
    for (final record in tmdbRecords.values) {
      if (record.sourceId != sourceId ||
          record.status != CloudResourceTmdbStatus.matched ||
          record.tmdbId == null ||
          record.title?.trim().isNotEmpty != true) {
        continue;
      }
      if (record.resourceKind == CloudResourceKind.directory) {
        directoryResourceRecords.add(record);
      } else {
        exactResourceRecords[record.stableKey] = record;
      }
    }

    final workRecords = <String, CloudWorkTmdbRecord>{
      for (final record in workTmdbRecords.values)
        if (record.sourceId == sourceId &&
            record.status == CloudWorkTmdbStatus.matched &&
            record.metadata != null)
          record.workKey: record,
    };
    for (final entry in _indexedItems.entries) {
      var item = entry.value;
      final resourceRecord = exactResourceRecords[_resourceKeyForItem(item)] ??
          _directoryRecordFor(item, directoryResourceRecords);
      if (resourceRecord != null) {
        item = item.replaceTmdb(
          tmdbId: resourceRecord.tmdbId!,
          tmdbTitle: resourceRecord.title!.trim(),
          tmdbOriginalTitle: resourceRecord.originalTitle,
          tmdbOverview: resourceRecord.overview,
          tmdbRating: resourceRecord.rating,
          tmdbPosterUrl: resourceRecord.posterUrl,
          tmdbBackdropUrl: resourceRecord.backdropUrl,
          tmdbGenres: resourceRecord.genres,
          posterCachePath: resourceRecord.posterCachePath,
        );
      }
      final workRecord =
          item.workKey == null ? null : workRecords[item.workKey!];
      final metadata = workRecord?.metadata;
      if (metadata != null) {
        item = item.replaceTmdb(
          tmdbId: metadata.id,
          tmdbTitle: metadata.title,
          tmdbOriginalTitle: metadata.originalTitle,
          tmdbOverview: metadata.overview,
          tmdbRating: metadata.rating,
          tmdbPosterUrl: metadata.posterUrl,
          tmdbBackdropUrl: metadata.backdropUrl,
          tmdbGenres: metadata.genres,
          posterCachePath: workRecord!.posterCachePath,
        );
      }
      _indexedItems[entry.key] = item;
    }
  }

  CloudResourceTmdbRecord? _directoryRecordFor(
    CloudMediaIndexItem item,
    Iterable<CloudResourceTmdbRecord> records,
  ) {
    final itemPath = _normalizeCloudPath(item.remotePath);
    for (final record in records) {
      final targetPath = _normalizeCloudPath(record.remotePath);
      if (itemPath.startsWith(targetPath == '/' ? '/' : '$targetPath/')) {
        return record;
      }
    }
    return null;
  }

  static String _normalizeCloudPath(String value) {
    var path = value.trim().replaceAll('\\', '/');
    path = path.replaceAll(RegExp(r'/+'), '/');
    if (path.isEmpty) return '/';
    if (!path.startsWith('/')) path = '/$path';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
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
    super.dispose();
  }
}
