import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/cloud/application/cloud_source_coordinator.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_cache_directories.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_subtitle_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/quark/quark_transfer_target_policy.dart';
import 'package:kanyingyin/utils/logger.dart';

typedef CloudClientFactory = CloudDriveClient Function(
  CloudSource source,
  CloudCredentialStore credentialStore,
  bool allowSelfSignedCertificate,
);

typedef CloudSourceCacheCleaner = Future<void> Function(String sourceId);

final class CloudSourcesLoadException implements Exception {
  const CloudSourcesLoadException();

  @override
  String toString() => '网盘数据源加载失败';
}

class CloudLibraryController extends ChangeNotifier {
  CloudLibraryController({
    CloudSourceRepository? repository,
    CloudCredentialStore? credentialStore,
    CloudClientFactory? clientFactory,
    CloudProviderRegistry? providerRegistry,
    CloudMediaIndexer? mediaIndexer,
    CloudMediaIndexRepository? mediaIndexRepository,
    CloudResourceTmdbRepository? resourceTmdbRepository,
    CloudWorkTmdbRepository? workTmdbRepository,
    CloudSeriesMatchRuleRepository? seriesMatchRuleRepository,
    CloudCacheRootProvider? cacheRootProvider,
    CloudSourceCacheCleaner? posterCacheCleaner,
    CloudSourceCacheCleaner? subtitleCacheCleaner,
  })  : _credentialStore = credentialStore ?? SecureCloudCredentialStore(),
        _repository = repository ?? CloudSourceRepository(),
        _mediaIndexRepository =
            mediaIndexRepository ?? CloudMediaIndexRepository(),
        _resourceTmdbRepository = resourceTmdbRepository,
        _workTmdbRepository = workTmdbRepository,
        _seriesMatchRuleRepository = seriesMatchRuleRepository,
        _cacheRootProvider = cacheRootProvider ?? defaultCloudCacheRoot,
        _mediaIndexer = mediaIndexer ??
            CloudMediaIndexer(
              repository: mediaIndexRepository ?? CloudMediaIndexRepository(),
            ),
        _posterCacheCleaner = posterCacheCleaner,
        _subtitleCacheCleaner = subtitleCacheCleaner,
        _providerRegistry = providerRegistry ??
            CloudProviderRegistry(
              clientFactories: clientFactory == null
                  ? const <CloudSourceType, CloudProviderClientFactory>{}
                  : <CloudSourceType, CloudProviderClientFactory>{
                      for (final type in CloudSourceType.values)
                        type: clientFactory,
                    },
            );

  final CloudSourceRepository _repository;
  final CloudCredentialStore _credentialStore;
  final CloudMediaIndexRepository _mediaIndexRepository;
  final CloudResourceTmdbRepository? _resourceTmdbRepository;
  final CloudWorkTmdbRepository? _workTmdbRepository;
  final CloudSeriesMatchRuleRepository? _seriesMatchRuleRepository;
  final CloudCacheRootProvider _cacheRootProvider;
  final CloudProviderRegistry _providerRegistry;
  final CloudMediaIndexer _mediaIndexer;
  final CloudSourceCacheCleaner? _posterCacheCleaner;
  final CloudSourceCacheCleaner? _subtitleCacheCleaner;
  final CloudSourceCoordinator _sourceCoordinator = CloudSourceCoordinator();

  List<CloudSource> sources = <CloudSource>[];
  final Set<String> _usableQuarkSourceIds = <String>{};
  bool loading = false;
  bool saving = false;
  bool testing = false;
  bool browsing = false;
  bool deleting = false;
  String? errorMessage;
  String? scanningSourceId;
  int scanProgress = 0;
  String? currentScanPath;
  List<String> scanFailedPaths = <String>[];
  CloudMediaScanResult? lastScanResult;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    _notify();
    try {
      sources = await _repository.getAll();
      _usableQuarkSourceIds.clear();
      for (final source in sources) {
        if (source.type != CloudSourceType.quark || !source.enabled) continue;
        try {
          final credential = await _credentialStore.read(source.id);
          if (credential?.cookie?.trim().isNotEmpty == true) {
            _usableQuarkSourceIds.add(source.id);
          }
        } on Object {
          // 单个来源凭据损坏不能阻止其他来源和本地媒体库工作。
        }
      }
      errorMessage = null;
    } catch (_) {
      errorMessage = '网盘数据源加载失败';
    } finally {
      loading = false;
      _notify();
    }
  }

  bool isQuarkSourceUsable(String sourceId) =>
      _usableQuarkSourceIds.contains(sourceId);

  Future<void> testConnection({
    required CloudSource source,
    required CloudCredential credential,
    required bool allowSelfSignedCertificate,
  }) async {
    testing = true;
    errorMessage = null;
    _notify();
    final temporaryCredentialStore = MemoryCloudCredentialStore();
    CloudDriveClient? client;
    try {
      final normalized = _providerRegistry.normalizeSource(source.copyWith(
        allowSelfSignedCertificate: allowSelfSignedCertificate,
      ));
      client = _providerRegistry.createClient(
        normalized,
        temporaryCredentialStore,
      );
      final testCredential = await _testCredential(source, credential);
      await client.authenticate(source, testCredential);
      await client.listDirectory(source.remoteRoots.isEmpty
          ? const CloudRemoteRef(id: '/', path: '/')
          : source.remoteRoots.first);
    } on CloudDriveException catch (error) {
      errorMessage = _providerRegistry.errorMessage(source.type, error);
      rethrow;
    } finally {
      try {
        await client?.close();
      } finally {
        testing = false;
        _notify();
      }
    }
  }

  Future<CloudCredential> _testCredential(
    CloudSource source,
    CloudCredential formCredential,
  ) async {
    final existingSource = await _repository.getById(source.id);
    final existingCredential = await _credentialStore.read(source.id);
    final addressUnchanged = existingSource != null &&
        _providerRegistry.normalizeEndpoint(existingSource) ==
            _providerRegistry.normalizeEndpoint(source);
    return _providerRegistry.mergeCredential(
      source: source,
      form: formCredential,
      existing: existingCredential,
      endpointUnchanged: addressUnchanged,
    );
  }

  Future<List<CloudFileEntry>> browseDirectories(
      CloudSource source, String remotePath,
      {CloudCredential? credential}) async {
    return browseRemoteDirectories(
      source,
      CloudRemoteRef(id: remotePath, path: remotePath),
      credential: credential,
    );
  }

  Future<List<CloudFileEntry>> browseRemoteDirectories(
    CloudSource source,
    CloudRemoteRef directory, {
    CloudCredential? credential,
  }) async {
    browsing = true;
    errorMessage = null;
    _notify();
    CloudDriveClient? client;
    try {
      final credentialStore =
          credential == null ? _credentialStore : MemoryCloudCredentialStore();
      if (credential != null) {
        await credentialStore.write(source.id, credential);
      }
      client = _providerRegistry.createClient(source, credentialStore);
      final entries = await client.listDirectory(directory);
      final directories = entries.where((entry) => entry.isDirectory).toList()
        ..sort((first, second) => first.name.compareTo(second.name));
      return directories;
    } on CloudDriveException catch (error) {
      errorMessage = _providerRegistry.errorMessage(source.type, error);
      rethrow;
    } finally {
      try {
        await client?.close();
      } finally {
        browsing = false;
        _notify();
      }
    }
  }

  Future<void> save(
    CloudSource source, {
    CloudCredential? credential,
  }) async {
    saving = true;
    _notify();
    try {
      final existingSource = await _repository.getById(source.id);
      final normalizedSource = _providerRegistry.normalizeSource(source);
      await _repository.save(normalizedSource);
      if (credential != null) {
        final existing = await _credentialStore.read(source.id);
        final endpointUnchanged = existingSource == null ||
            _providerRegistry.normalizeEndpoint(existingSource) ==
                _providerRegistry.normalizeEndpoint(normalizedSource);
        final merged = _providerRegistry.mergeCredential(
          source: normalizedSource,
          form: credential,
          existing: existing,
          endpointUnchanged: endpointUnchanged,
        );
        if (!merged.isEmpty) {
          await _credentialStore.write(source.id, merged);
        }
      }
      await load();
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> delete(String sourceId) async {
    deleting = true;
    errorMessage = null;
    _notify();
    CloudMediaIndexSnapshot? removedIndex;
    List<CloudResourceTmdbRecord>? removedTmdbRecords;
    List<CloudWorkTmdbRecord>? removedWorkTmdbRecords;
    List<CloudSeriesMatchRule>? removedSeriesRules;
    try {
      cancelScan(sourceId);
      await _sourceCoordinator.waitFor(sourceId);
      removedIndex = await _mediaIndexRepository.removeSource(sourceId);
      final resourceTmdbRepository = _resourceTmdbRepository;
      if (resourceTmdbRepository != null) {
        removedTmdbRecords = await resourceTmdbRepository.getBySource(sourceId);
        await resourceTmdbRepository.removeSource(sourceId);
      }
      final workTmdbRepository = _workTmdbRepository;
      if (workTmdbRepository != null) {
        removedWorkTmdbRecords = await workTmdbRepository.getBySource(sourceId);
        await workTmdbRepository.removeSource(sourceId);
      }
      final seriesMatchRuleRepository = _seriesMatchRuleRepository;
      if (seriesMatchRuleRepository != null) {
        removedSeriesRules = await seriesMatchRuleRepository.removeSource(
          sourceId,
        );
      }
      var cacheCleanupFailed = false;
      try {
        await _clearPosterCache(sourceId);
      } on Object {
        cacheCleanupFailed = true;
      }
      try {
        await _clearSubtitleCache(sourceId);
      } on Object {
        cacheCleanupFailed = true;
      }
      await _repository.delete(sourceId);
      await load();
      if (cacheCleanupFailed) {
        errorMessage = '网盘数据源已删除，但部分本地缓存清理失败';
      }
    } catch (_) {
      var tmdbRestored = true;
      var seriesRulesRestored = true;
      final resourceTmdbRepository = _resourceTmdbRepository;
      if (removedTmdbRecords != null && resourceTmdbRepository != null) {
        try {
          for (final record in removedTmdbRecords) {
            await resourceTmdbRepository.upsert(record);
          }
        } on Object {
          tmdbRestored = false;
        }
      }
      final workTmdbRepository = _workTmdbRepository;
      if (removedWorkTmdbRecords != null && workTmdbRepository != null) {
        try {
          await workTmdbRepository.replaceSource(
            sourceId,
            removedWorkTmdbRecords,
          );
        } on Object {
          tmdbRestored = false;
        }
      }
      final removedAnyTmdb =
          removedTmdbRecords != null || removedWorkTmdbRecords != null;
      final seriesMatchRuleRepository = _seriesMatchRuleRepository;
      if (removedSeriesRules != null && seriesMatchRuleRepository != null) {
        try {
          await seriesMatchRuleRepository.replaceSource(
            sourceId,
            removedSeriesRules,
          );
        } on Object {
          seriesRulesRestored = false;
        }
      }
      if (removedIndex == null) {
        if (!tmdbRestored && !seriesRulesRestored) {
          errorMessage = '删除网盘数据源失败，TMDB 信息和系列规则恢复失败';
        } else if (!tmdbRestored) {
          errorMessage = '删除网盘数据源失败，TMDB 信息恢复失败';
        } else if (!seriesRulesRestored) {
          errorMessage = '删除网盘数据源失败，系列规则恢复失败';
        } else {
          errorMessage = '删除网盘数据源失败，原有数据未被删除';
        }
      } else {
        try {
          await _mediaIndexRepository.replaceSource(
            sourceId,
            removedIndex.items,
            removedIndex.fingerprints,
            removedIndex.directoryEntries,
            removedIndex.indexedRoots,
          );
          if (!tmdbRestored && !seriesRulesRestored) {
            errorMessage = '删除网盘数据源失败，媒体索引已恢复，但 TMDB 信息和系列规则恢复失败';
          } else if (!tmdbRestored) {
            errorMessage = '删除网盘数据源失败，媒体索引已恢复但 TMDB 信息恢复失败';
          } else if (!seriesRulesRestored) {
            errorMessage = '删除网盘数据源失败，媒体索引已恢复但系列规则恢复失败';
          } else if (removedAnyTmdb && removedSeriesRules != null) {
            errorMessage = '删除网盘数据源失败，原有索引、刮削信息和系列规则已恢复';
          } else if (removedAnyTmdb) {
            errorMessage = '删除网盘数据源失败，原有索引和刮削信息已恢复';
          } else if (removedSeriesRules != null) {
            errorMessage = '删除网盘数据源失败，原有索引和系列规则已恢复';
          } else {
            errorMessage = '删除网盘数据源失败，原有媒体索引已恢复';
          }
        } on Object {
          errorMessage = '删除网盘数据源失败，媒体索引恢复失败，请重新扫描';
        }
      }
      rethrow;
    } finally {
      deleting = false;
      _notify();
    }
  }

  Future<void> _clearPosterCache(String sourceId) async {
    final cleaner = _posterCacheCleaner;
    if (cleaner != null) return cleaner(sourceId);
    await CloudPosterCache.clearSourceFromRoot(
        cacheRoot: await _cacheRootProvider(), sourceId: sourceId);
  }

  Future<void> _clearSubtitleCache(String sourceId) async {
    final cleaner = _subtitleCacheCleaner;
    if (cleaner != null) return cleaner(sourceId);
    await CloudSubtitleCache.clearSourceFromRoot(
        cacheRoot: await _cacheRootProvider(), sourceId: sourceId);
  }

  bool isScanningSource(String sourceId) =>
      _sourceCoordinator.activeSourceId == sourceId;

  Future<int> scanAllSources() async {
    await load();
    if (errorMessage != null) throw const CloudSourcesLoadException();
    final sourceSnapshot = List<CloudSource>.of(sources);
    var completedCount = 0;
    var failedCount = 0;
    for (final source in sourceSnapshot) {
      try {
        final result = await scanSource(source.id);
        if (!result.cancelled) completedCount++;
      } catch (_) {
        failedCount++;
      }
    }
    if (!_disposed && failedCount > 0) {
      errorMessage = '部分网盘媒体扫描失败（$failedCount/${sourceSnapshot.length}）';
      _notify();
    }
    return completedCount;
  }

  Future<CloudMediaScanResult> scanSource(String sourceId) async {
    if (_disposed) return _cancelledScanResult();
    final scanHandle = _sourceCoordinator.beginScan(sourceId);
    final token = scanHandle.token;
    scanningSourceId = sourceId;
    scanProgress = 0;
    currentScanPath = null;
    scanFailedPaths = <String>[];
    errorMessage = null;
    _notify();
    CloudDriveClient? client;
    try {
      var source = await _repository.getById(sourceId);
      if (_disposed || token.isCancelled) return _cancelledScanResult();
      if (source == null) throw StateError('网盘数据源不存在');
      var repairedTransferRoot = false;
      source = await _repository.updateSource(sourceId, (latest) {
        final transferDirectory = latest.defaultTransferDirectory;
        if (latest.type != CloudSourceType.quark || transferDirectory == null) {
          return latest;
        }
        final updated =
            QuarkTransferTargetPolicy.apply(latest, transferDirectory);
        repairedTransferRoot = updated != latest;
        return updated;
      });
      if (source == null) throw StateError('网盘数据源不存在');
      if (_disposed || token.isCancelled) return _cancelledScanResult();
      AppLogger().i(
        'CloudLibraryController: scan started source=$sourceId '
        'type=${source.type.name} roots=${source.remoteRoots.length} '
        'transferRootRepaired=$repairedTransferRoot',
      );
      await _repository.updateScanSummary(
        sourceId,
        status: CloudScanStatus.scanning,
      );
      if (_disposed || token.isCancelled) {
        await _repository.updateScanSummary(
          sourceId,
          status: source.scanStatus,
        );
        return _cancelledScanResult();
      }
      client = _providerRegistry.createClient(source, _credentialStore);
      if (_disposed || token.isCancelled) {
        await _repository.updateScanSummary(
          sourceId,
          status: source.scanStatus,
        );
        return _cancelledScanResult();
      }
      final result = await _mediaIndexer.scan(
        source: source,
        client: client,
        cancellationToken: token,
        onProgress: (progress) {
          if (_disposed) return;
          scanProgress = progress.scanned;
          currentScanPath = progress.currentPath;
          _notify();
        },
      );
      if (!_disposed) {
        lastScanResult = result;
        _lastScanResultSourceId = sourceId;
        scanFailedPaths = result.failedPaths;
      }
      if (result.cancelled) {
        await _repository.updateScanSummary(
          sourceId,
          status: source.lastScannedAt == null
              ? CloudScanStatus.never
              : CloudScanStatus.completed,
        );
      } else {
        await _repository.updateScanSummary(
          sourceId,
          status: CloudScanStatus.completed,
          scannedAt: DateTime.now(),
          videoCount: result.videoCount,
          subtitleCount: result.matchedSubtitleCount,
          failureCount: result.failures,
        );
      }
      if (!_disposed) sources = await _repository.getAll();
      AppLogger().i(
        'CloudLibraryController: scan finished source=$sourceId '
        'scanned=${result.scanned} videos=${result.videoCount} '
        'subtitles=${result.matchedSubtitleCount} '
        'failures=${result.failures} cancelled=${result.cancelled}',
      );
      return result;
    } catch (error) {
      AppLogger().w(
        'CloudLibraryController: scan failed source=$sourceId '
        'errorType=${error.runtimeType}',
      );
      if (!_disposed) {
        errorMessage = '网盘媒体扫描失败，请稍后重试';
        await _repository.updateScanSummary(
          sourceId,
          status: CloudScanStatus.failed,
          failureCount: 1,
        );
        sources = await _repository.getAll();
      }
      rethrow;
    } finally {
      if (!_disposed) {
        if (scanningSourceId == sourceId) scanningSourceId = null;
        _notify();
      }
      try {
        await client?.close();
      } finally {
        scanHandle.complete();
      }
    }
  }

  void cancelScan(String sourceId) {
    _sourceCoordinator.cancel(sourceId);
  }

  Future<CloudMediaScanResult> retryFailedScan() {
    final sourceId = scanningSourceId ?? lastScanResultSourceId;
    if (sourceId == null || scanFailedPaths.isEmpty) {
      throw StateError('没有可重试的扫描');
    }
    return scanSource(sourceId);
  }

  String? get lastScanResultSourceId => _lastScanResultSourceId;
  String? _lastScanResultSourceId;

  static CloudMediaScanResult _cancelledScanResult() =>
      const CloudMediaScanResult(
        scanned: 0,
        skipped: 0,
        failures: 0,
        failedPaths: <String>[],
        cancelled: true,
      );

  @override
  void dispose() {
    _sourceCoordinator.cancelActive();
    _disposed = true;
    super.dispose();
  }
}
