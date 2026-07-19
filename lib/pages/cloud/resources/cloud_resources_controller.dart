import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_name_parser.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_auto_organizer.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:path/path.dart' as p;

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
    CloudResourceAutoOrganizer? autoOrganizer,
    LocalEpisodeParser? episodeParser,
  })  : _repository = repository,
        _credentialStore = credentialStore,
        _providerRegistry = providerRegistry ?? CloudProviderRegistry(),
        _tmdbCoordinator = tmdbCoordinator,
        _autoOrganizer = autoOrganizer ?? const CloudResourceAutoOrganizer(),
        _episodeParser = episodeParser ?? LocalEpisodeParser() {
    _tmdbCoordinator?.addListener(_notify);
  }

  final CloudSourceRepository _repository;
  final CloudCredentialStore _credentialStore;
  final CloudProviderRegistry _providerRegistry;
  final CloudResourceTmdbCoordinator? _tmdbCoordinator;
  final CloudResourceAutoOrganizer _autoOrganizer;
  final LocalEpisodeParser _episodeParser;
  final List<CloudRemoteRef?> _history = <CloudRemoteRef?>[];

  List<CloudSource> sources = <CloudSource>[];
  List<CloudFileEntry> entries = <CloudFileEntry>[];
  CloudSource? selectedSource;
  CloudRemoteRef? currentDirectory;
  bool isVirtualRoot = false;
  bool loading = false;
  bool autoOrganizing = false;
  String query = '';
  String? errorMessage;

  int _generation = 0;
  bool _disposed = false;

  bool get canGoBack => _history.isNotEmpty;

  Map<String, CloudResourceTmdbRecord> get tmdbRecords =>
      _tmdbCoordinator?.records ?? const <String, CloudResourceTmdbRecord>{};

  Set<String> get tmdbScrapingKeys =>
      _tmdbCoordinator?.scrapingKeys ?? const <String>{};

  int get tmdbCompletedCount => _tmdbCoordinator?.completedCount ?? 0;
  int get tmdbTotalCount => _tmdbCoordinator?.totalCount ?? 0;
  TmdbScrapeOptions get tmdbScrapeOptions =>
      _tmdbCoordinator?.options ?? const TmdbScrapeOptions.defaults();

  bool get isCurrentDirectoryConfiguredRoot {
    final source = selectedSource;
    final directory = currentDirectory;
    if (source == null || directory == null) return false;
    return source.remoteRoots.any(
      (root) => root.id == directory.id || root.path == directory.path,
    );
  }

  CloudResourceTmdbRecord? get currentDirectoryTmdbRecord {
    final source = selectedSource;
    final directory = currentDirectory;
    if (source == null || directory == null) return null;
    final key = cloudResourceTmdbKey(
      sourceId: source.id,
      remoteId: directory.id,
      remotePath: directory.path,
    );
    return tmdbRecords[key];
  }

  List<CloudFileEntry> get visibleEntries {
    final keyword = query.trim().toLowerCase();
    final filtered = entries
        .where(
          (entry) =>
              (entry.isDirectory ||
                  LocalVideoFileTypes.isVideoPath(entry.name)) &&
              (keyword.isEmpty || entry.name.toLowerCase().contains(keyword)),
        )
        .toList(growable: false);
    filtered.sort((first, second) {
      if (first.isDirectory != second.isDirectory) {
        return first.isDirectory ? -1 : 1;
      }
      return first.name.toLowerCase().compareTo(second.name.toLowerCase());
    });
    return filtered;
  }

  List<CloudFileEntry> get tmdbEntriesForCurrentDirectory {
    final candidates = visibleEntries
        .where(
          (entry) => entry.isDirectory || isCurrentDirectoryConfiguredRoot,
        )
        .toList(growable: false);
    if (candidates.isNotEmpty || isCurrentDirectoryConfiguredRoot) {
      return candidates;
    }
    final directory = currentDirectory;
    if (directory == null || isVirtualRoot) return candidates;
    final containsVideo = entries.any(
      (entry) =>
          !entry.isDirectory && LocalVideoFileTypes.isVideoPath(entry.name),
    );
    if (!containsVideo) return candidates;
    return <CloudFileEntry>[
      CloudFileEntry(
        id: directory.id,
        remotePath: directory.path,
        name: _currentDirectoryTmdbName(directory),
        size: 0,
        modifiedAt: null,
        isDirectory: true,
      ),
    ];
  }

  Future<void> load() async {
    final generation = ++_generation;
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
      final nextId = loadedSources.any((source) => source.id == currentId)
          ? currentId
          : loadedSources.firstOrNull?.id;
      loading = false;
      await selectSource(nextId);
    } on Object {
      if (!_isCurrent(generation)) return;
      sources = <CloudSource>[];
      selectedSource = null;
      currentDirectory = null;
      entries = <CloudFileEntry>[];
      loading = false;
      errorMessage = '网盘来源加载失败';
      _notify();
    }
  }

  Future<void> selectSource(String? sourceId) async {
    final generation = ++_generation;
    _history.clear();
    query = '';
    entries = <CloudFileEntry>[];
    currentDirectory = null;
    isVirtualRoot = false;
    errorMessage = null;
    selectedSource = sourceId == null
        ? null
        : sources.where((source) => source.id == sourceId).firstOrNull;
    final source = selectedSource;
    if (source == null) {
      loading = false;
      _notify();
      return;
    }
    final roots = source.remoteRoots;
    if (roots.length > 1) {
      _showVirtualRoot(source);
      return;
    }
    if (roots.isEmpty) {
      loading = false;
      errorMessage = '该来源还没有配置媒体根目录';
      _notify();
      return;
    }
    await _loadDirectory(
      roots.single,
      generation: generation,
      pushHistory: false,
    );
  }

  Future<void> _loadDirectory(
    CloudRemoteRef directory, {
    required int generation,
    required bool pushHistory,
    CloudRemoteRef? previousDirectory,
    bool previousWasVirtualRoot = false,
  }) async {
    final source = selectedSource;
    if (source == null) return;
    loading = true;
    errorMessage = null;
    _notify();
    CloudDriveClient? client;
    try {
      client = _providerRegistry.createClient(source, _credentialStore);
      final loadedEntries = await client.listDirectory(directory);
      if (!_isCurrent(generation)) return;
      if (pushHistory) {
        _history.add(previousWasVirtualRoot ? null : previousDirectory);
      }
      currentDirectory = directory;
      entries = loadedEntries;
      isVirtualRoot = false;
      _scheduleTmdb(source, directory, loadedEntries);
    } on CloudDriveException catch (error) {
      if (!_isCurrent(generation)) return;
      errorMessage = _providerRegistry.errorMessage(source.type, error);
    } on Object {
      if (!_isCurrent(generation)) return;
      errorMessage = '网盘目录加载失败';
    } finally {
      await client?.close();
      if (_isCurrent(generation)) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> openDirectory(CloudRemoteRef directory) {
    final generation = ++_generation;
    return _loadDirectory(
      directory,
      generation: generation,
      pushHistory: true,
      previousDirectory: currentDirectory,
      previousWasVirtualRoot: isVirtualRoot,
    );
  }

  Future<void> goBack() async {
    if (_history.isEmpty || loading) return;
    final previous = _history.removeLast();
    if (previous == null) {
      final source = selectedSource;
      if (source != null) _showVirtualRoot(source);
      return;
    }
    final generation = ++_generation;
    await _loadDirectory(
      previous,
      generation: generation,
      pushHistory: false,
    );
  }

  Future<void> refresh() async {
    if (loading) return;
    final source = selectedSource;
    if (source == null) return;
    if (isVirtualRoot) {
      _showVirtualRoot(source);
      return;
    }
    final directory = currentDirectory;
    if (directory == null) return;
    final generation = ++_generation;
    await _loadDirectory(
      directory,
      generation: generation,
      pushHistory: false,
    );
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
    return CloudResourceTmdbTarget(
      sourceId: source.id,
      remote: CloudRemoteRef(id: entry.id, path: entry.remotePath),
      displayName: entry.name,
      resourceKind: entry.isDirectory
          ? CloudResourceKind.directory
          : CloudResourceKind.standaloneVideo,
      customTitle: tmdbRecords[key]?.customTitle,
      size: entry.isDirectory ? null : entry.size,
    );
  }

  CloudResourceTmdbRecord? tmdbRecordFor(CloudFileEntry entry) {
    return tmdbRecords[tmdbTargetFor(entry).stableKey];
  }

  TmdbMatchDraft tmdbDraftFor(CloudFileEntry entry) {
    final record = tmdbRecordFor(entry);
    return const CloudMediaNameParser().parse(
      originalName: entry.name,
      isDirectory: entry.isDirectory,
      preferredTitle: record?.customTitle ?? record?.title,
    );
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
    CloudRemoteRef directory,
    List<CloudFileEntry> loadedEntries,
  ) {
    final coordinator = _tmdbCoordinator;
    if (coordinator == null) return;
    final isConfiguredRoot = source.remoteRoots.any(
      (root) => root.id == directory.id || root.path == directory.path,
    );
    unawaited(
      coordinator
          .loadAndSchedule(
            CloudResourceDirectoryContext(
              source: source,
              directory: directory,
              entries: List<CloudFileEntry>.unmodifiable(loadedEntries),
              isConfiguredRoot: isConfiguredRoot,
            ),
          )
          .catchError((_) {}),
    );
  }

  void _showVirtualRoot(CloudSource source) {
    entries = source.remoteRoots
        .map(
          (root) => CloudFileEntry(
            id: root.id,
            remotePath: root.path,
            name: p.posix.basename(root.path),
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        )
        .toList(growable: false);
    currentDirectory = null;
    isVirtualRoot = true;
    loading = false;
    errorMessage = null;
    _notify();
  }

  String _currentDirectoryTmdbName(CloudRemoteRef directory) {
    for (final entry in entries) {
      if (entry.isDirectory || !LocalVideoFileTypes.isVideoPath(entry.name)) {
        continue;
      }
      final seriesName = _episodeParser.parse(entry.remotePath)?.seriesName;
      if (seriesName != null && seriesName.trim().isNotEmpty) {
        return seriesName.trim();
      }
    }
    final directoryName = p.posix.basename(directory.path).trim();
    if (_isSeasonDirectoryName(directoryName)) {
      final parentName =
          p.posix.basename(p.posix.dirname(directory.path)).trim();
      if (parentName.isNotEmpty && parentName != '/') return parentName;
    }
    return directoryName;
  }

  static bool _isSeasonDirectoryName(String value) => RegExp(
        r'^(?:season|s)\s*\d{1,2}$|^第\s*\d{1,2}\s*[季部]$',
        caseSensitive: false,
        unicode: true,
      ).hasMatch(value);

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _tmdbCoordinator?.removeListener(_notify);
    super.dispose();
  }
}
