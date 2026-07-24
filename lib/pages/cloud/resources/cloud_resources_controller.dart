import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/cloud/application/cloud_resource_tmdb_facade.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_media_tree_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_auto_organizer.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_service.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

int _defaultCloudMinSizeBytes() =>
    LocalVideoFileTypes.minRecognizedVideoSizeBytes;

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
    CloudMediaIndexer? mediaIndexer,
    CloudMediaTreeResolver? mediaTreeResolver,
  })  : _repository = repository,
        _credentialStore = credentialStore,
        _mediaIndexRepository =
            mediaIndexRepository ?? CloudMediaIndexRepository(),
        _providerRegistry = providerRegistry ?? CloudProviderRegistry(),
        _tmdbCoordinator = tmdbCoordinator,
        _workTmdbCoordinator = workTmdbCoordinator,
        _minRecognizedVideoSizeBytesProvider =
            minRecognizedVideoSizeBytesProvider ?? _defaultCloudMinSizeBytes,
        _collectionGrouper =
            collectionGrouper ?? CloudResourceCollectionGrouper(),
        _mediaTreeResolver =
            mediaTreeResolver ?? const CloudMediaTreeResolver(),
        _autoOrganizer = autoOrganizer ??
            CloudResourceAutoOrganizer(
              minRecognizedVideoSizeBytesProvider:
                  minRecognizedVideoSizeBytesProvider ??
                      _defaultCloudMinSizeBytes,
            ) {
    _mediaIndexer = mediaIndexer ??
        CloudMediaIndexer(
          repository: _mediaIndexRepository,
          minRecognizedVideoSizeBytesProvider:
              _minRecognizedVideoSizeBytesProvider,
        );
    _tmdbCoordinator?.addListener(_notify);
    _workTmdbCoordinator?.addListener(_notify);
  }

  final CloudSourceRepository _repository;
  final CloudCredentialStore _credentialStore;
  final CloudMediaIndexRepository _mediaIndexRepository;
  late final CloudMediaIndexer _mediaIndexer;
  final CloudProviderRegistry _providerRegistry;
  final CloudResourceTmdbCoordinator? _tmdbCoordinator;
  final CloudWorkTmdbCoordinator? _workTmdbCoordinator;
  final CloudResourceAutoOrganizer _autoOrganizer;
  final int Function() _minRecognizedVideoSizeBytesProvider;
  final CloudResourceCollectionGrouper _collectionGrouper;
  final CloudMediaTreeResolver _mediaTreeResolver;
  final CloudResourceTmdbFacade _tmdbFacade = const CloudResourceTmdbFacade();
  final Map<String, CloudMediaIndexItem> _indexedItems =
      <String, CloudMediaIndexItem>{};
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

  int _generation = 0;
  bool _disposed = false;
  CloudScanCancellationToken? _scanToken;
  Future<void>? _scanFuture;

  bool get canGoBack => false;
  Future<void> get scanCompletion => _scanFuture ?? Future<void>.value();

  Map<String, CloudResourceTmdbRecord> get tmdbRecords =>
      _tmdbCoordinator?.records ?? const <String, CloudResourceTmdbRecord>{};

  Map<String, CloudWorkTmdbRecord> get workTmdbRecords =>
      _workTmdbCoordinator?.recordsByWorkKey ??
      const <String, CloudWorkTmdbRecord>{};

  List<CloudWorkIdentity> get works =>
      List<CloudWorkIdentity>.unmodifiable(_works);

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

  List<CloudFileEntry> get visibleEntries {
    final keyword = query.trim().toLowerCase();
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    final filtered = entries
        .where(
          (entry) =>
              LocalVideoFileTypes.isRecognizedVideo(
                entry.name,
                size: entry.size,
                minSizeBytes: minSizeBytes,
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
    if (_workTmdbCoordinator != null && _works.isNotEmpty) {
      return _collectionGrouper.group(
        items: _indexedItems.values.toList(growable: false),
        works: _works,
        recordsByWorkKey: workTmdbRecords,
        query: query,
      );
    }
    return _collectionGrouper.group(
      sourceId: selectedSource?.id ?? '',
      entries: entries,
      records: tmdbRecords,
      minSizeBytes: _minRecognizedVideoSizeBytesProvider(),
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

  Future<void> load() => _loadSources(startScan: true);

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
    final previousWorks = List<CloudWorkIdentity>.from(_works);
    final previousMediaTree = _mediaTree;
    final previousQuery = query;
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
    _works = previousWorks;
    _mediaTree = previousMediaTree;
    query = previousQuery;
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
      _works = <CloudWorkIdentity>[];
      _mediaTree = null;
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
    query = '';
    entries = <CloudFileEntry>[];
    _indexedItems.clear();
    _works = <CloudWorkIdentity>[];
    _mediaTree = null;
    currentDirectory = null;
    isVirtualRoot = false;
    errorMessage = null;
    selectedSource = sourceId == null
        ? null
        : sources.where((source) => source.id == sourceId).firstOrNull;
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
    await _loadSnapshot(source, generation);
    if (!_isCurrent(generation)) return;
    loading = false;
    _notify();
    _scheduleTmdb(source, entries);
    if (startScan) {
      _startScan(source, generation);
    }
  }

  Future<void> _loadSnapshot(CloudSource source, int generation) async {
    final snapshot = await _mediaIndexRepository.snapshot(source.id);
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
  }) {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 刮削服务不可用');
    return coordinator.selectPrepared(
      workForGroup(group),
      candidate,
      options: options,
    );
  }

  Future<List<TmdbMetadata>> rematchWork(
    CloudResourceMediaGroup group, {
    TmdbScrapeOptions? options,
  }) {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 刮削服务不可用');
    return coordinator.rematch(
      workForGroup(group),
      options: options,
    );
  }

  Future<CloudWorkTmdbOutcome> scrapeWork(
    CloudResourceMediaGroup group, {
    TmdbScrapeOptions? options,
  }) {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 刮削服务不可用');
    return coordinator.scrape(
      workForGroup(group),
      options: options,
    );
  }

  Future<CloudWorkTmdbRecord> saveScrapeTitle(
    CloudResourceMediaGroup group,
    String title,
  ) {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 元数据服务不可用');
    return coordinator.saveScrapeTitle(workForGroup(group), title);
  }

  Future<CloudWorkTmdbRecord> clearScrapeTitle(
    CloudResourceMediaGroup group,
  ) {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 元数据服务不可用');
    return coordinator.clearScrapeTitle(workForGroup(group));
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

  CloudMediaIndexItem? _indexedItemFor(CloudFileEntry entry) {
    final source = selectedSource;
    if (source == null) return null;
    return _indexedItems[cloudResourceTmdbKey(
      sourceId: source.id,
      remoteId: entry.id,
      remotePath: entry.remotePath,
    )];
  }

  static String _resourceKeyForItem(CloudMediaIndexItem item) =>
      cloudResourceTmdbKey(
        sourceId: item.sourceId,
        remoteId: item.remoteId,
        remotePath: item.remotePath,
      );

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _scanToken?.cancel();
    _tmdbCoordinator?.removeListener(_notify);
    _workTmdbCoordinator?.removeListener(_notify);
    super.dispose();
  }
}
