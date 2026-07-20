import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

typedef CloudWorkTmdbServiceFactory = FutureOr<CloudWorkTmdbService> Function(
  String apiKey,
);

class CloudWorkTmdbCoordinator extends ChangeNotifier {
  CloudWorkTmdbCoordinator({
    required CloudWorkTmdbRepository repository,
    required CloudResourceTmdbRepository legacyRepository,
    required CloudMediaIndexRepository indexRepository,
    required CloudWorkTmdbServiceFactory serviceFactory,
    required String Function() apiKeyProvider,
    TmdbScrapeOptions Function()? optionsProvider,
    DateTime Function()? now,
  })  : _repository = repository,
        _legacyRepository = legacyRepository,
        _indexRepository = indexRepository,
        _serviceFactory = serviceFactory,
        _apiKeyProvider = apiKeyProvider,
        _optionsProvider =
            optionsProvider ?? (() => const TmdbScrapeOptions.defaults()),
        _now = now ?? DateTime.now;

  static const int maximumConcurrentScrapes = 2;
  static const Duration unmatchedRetryInterval = Duration(days: 7);

  final CloudWorkTmdbRepository _repository;
  final CloudResourceTmdbRepository _legacyRepository;
  final CloudMediaIndexRepository _indexRepository;
  final CloudWorkTmdbServiceFactory _serviceFactory;
  final String Function() _apiKeyProvider;
  final TmdbScrapeOptions Function() _optionsProvider;
  final DateTime Function() _now;
  final Map<String, CloudWorkTmdbRecord> _records =
      <String, CloudWorkTmdbRecord>{};
  final Set<String> _scrapingWorkKeys = <String>{};

  int _generation = 0;
  int _completedCount = 0;
  int _totalCount = 0;
  String? _serviceApiKey;
  Future<CloudWorkTmdbService>? _service;

  Map<String, CloudWorkTmdbRecord> get recordsByWorkKey =>
      UnmodifiableMapView<String, CloudWorkTmdbRecord>(_records);

  Set<String> get scrapingWorkKeys =>
      UnmodifiableSetView<String>(_scrapingWorkKeys);

  int get completedCount => _completedCount;
  int get totalCount => _totalCount;
  bool get isScraping => _scrapingWorkKeys.isNotEmpty;
  bool get hasApiKey => _apiKeyProvider().trim().isNotEmpty;
  TmdbScrapeOptions get options => _optionsProvider();

  Future<void> loadAndSchedule(CloudMediaTree tree) async {
    final generation = ++_generation;
    final uniqueWorks = <String, CloudWorkIdentity>{
      for (final work in tree.works) work.workKey: work,
    };
    final stored = await _repository.getBySource(tree.sourceId);
    if (generation != _generation) return;
    _records
      ..clear()
      ..addEntries(stored.map((record) => MapEntry(record.workKey, record)));
    _scrapingWorkKeys.clear();
    _completedCount = 0;
    _totalCount = 0;

    final migrations = await _migrateLegacyRecords(
      tree.sourceId,
      uniqueWorks.values,
    );
    if (generation != _generation) return;
    if (migrations.isNotEmpty) {
      await _repository.upsertAll(migrations);
      for (final record in migrations) {
        _records[record.workKey] = record;
      }
    }
    notifyListeners();

    final apiKey = _apiKeyProvider().trim();
    if (apiKey.isEmpty) return;
    final now = _now();
    final works = uniqueWorks.values.where((work) {
      final cached = _records[work.workKey];
      if (cached == null || cached.status == CloudWorkTmdbStatus.unchecked) {
        return true;
      }
      if (cached.status == CloudWorkTmdbStatus.matched ||
          cached.status == CloudWorkTmdbStatus.conflict) {
        return false;
      }
      return cached.status != CloudWorkTmdbStatus.unmatched ||
          !cached.checkedAt.add(unmatchedRetryInterval).isAfter(now);
    }).toList(growable: false);
    _totalCount = works.length;
    notifyListeners();
    if (works.isEmpty) return;

    var nextIndex = 0;
    Future<void> worker() async {
      while (generation == _generation && nextIndex < works.length) {
        final work = works[nextIndex++];
        await _autoScrape(work, apiKey, generation);
      }
    }

    final workerCount = works.length < maximumConcurrentScrapes
        ? works.length
        : maximumConcurrentScrapes;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
  }

  Future<CloudWorkTmdbRecord> saveScrapeTitle(
    CloudWorkIdentity work,
    String title,
  ) async {
    final normalized = title.trim();
    if (normalized.isEmpty) throw ArgumentError.value(title, 'title');
    final current = _records[work.workKey] ??
        await _repository.get(work.workKey) ??
        CloudWorkTmdbRecord.uncheckedFromWork(work, checkedAt: _now());
    final updated = current.copyWithScrapeTitle(normalized);
    await _repository.upsert(updated);
    await _indexRepository.updateMatching(
      work.sourceId,
      (item) => item.workKey == work.workKey,
      (item) => item.withEffectiveWorkTitle(normalized),
    );
    _records[work.workKey] = updated;
    notifyListeners();
    return updated;
  }

  Future<CloudWorkTmdbRecord> clearScrapeTitle(CloudWorkIdentity work) async {
    final current = _records[work.workKey] ??
        await _repository.get(work.workKey) ??
        CloudWorkTmdbRecord.uncheckedFromWork(work, checkedAt: _now());
    final updated = current.clearScrapeTitle();
    await _repository.upsert(updated);
    _records[work.workKey] = updated;
    notifyListeners();
    return updated;
  }

  Future<CloudWorkTmdbOutcome> scrape(
    CloudWorkIdentity work, {
    TmdbScrapeOptions? options,
  }) async {
    final apiKey = _requiredApiKey();
    return _tracked(work, () async {
      final service = await _serviceFor(apiKey);
      final outcome = await service.match(
        work,
        record: _records[work.workKey],
        options: options ?? _optionsProvider(),
      );
      await _refreshRecord(work.workKey);
      return outcome;
    });
  }

  Future<List<TmdbMetadata>> rematch(
    CloudWorkIdentity work, {
    TmdbScrapeOptions? options,
  }) async {
    final apiKey = _requiredApiKey();
    return _tracked(work, () async {
      final service = await _serviceFor(apiKey);
      return service.searchCandidates(
        work,
        record: _records[work.workKey],
        options: options ?? _optionsProvider(),
      );
    });
  }

  Future<TmdbRankedResult> searchPrepared(
    CloudWorkIdentity work,
    CloudResourceTmdbSearchRequest request,
  ) async {
    final apiKey = _requiredApiKey();
    return _tracked(work, () async {
      final service = await _serviceFor(apiKey);
      return service.searchPrepared(work, request);
    });
  }

  Future<CloudWorkTmdbSelectionOutcome> selectPrepared(
    CloudWorkIdentity work,
    TmdbRankedCandidate candidate, {
    required TmdbScrapeOptions options,
  }) {
    return selectCandidate(work, candidate.metadata, options: options);
  }

  Future<CloudWorkTmdbSelectionOutcome> selectCandidate(
    CloudWorkIdentity work,
    TmdbMetadata candidate, {
    TmdbScrapeOptions? options,
  }) async {
    final apiKey = _requiredApiKey();
    return _tracked(work, () async {
      final service = await _serviceFor(apiKey);
      final outcome = await service.select(
        work,
        candidate,
        existingSeasons:
            work.seasons.map((season) => season.seasonNumber).toSet(),
        options: options ?? _optionsProvider(),
      );
      _records[work.workKey] = outcome.record;
      notifyListeners();
      return outcome;
    });
  }

  Future<List<CloudWorkTmdbRecord>> _migrateLegacyRecords(
    String sourceId,
    Iterable<CloudWorkIdentity> works,
  ) async {
    final legacy = await _legacyRepository.getBySource(sourceId);
    final migrations = <CloudWorkTmdbRecord>[];
    for (final work in works) {
      if (_records.containsKey(work.workKey)) continue;
      final rootPath = _normalizePath(work.root.remotePath);
      final prefix = rootPath == '/' ? '/' : '$rootPath/';
      final scoped = legacy.where((record) {
        final path = _normalizePath(record.remotePath);
        return path == rootPath || path.startsWith(prefix);
      }).toList(growable: false);
      if (scoped.isEmpty) continue;
      final matched = scoped
          .where(
            (record) =>
                record.status == CloudResourceTmdbStatus.matched &&
                record.tmdbId != null,
          )
          .toList(growable: false);
      final ids = matched.map((record) => record.tmdbId!).toSet();
      final customTitle = scoped
          .map((record) => record.customTitle?.trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .firstOrNull;
      final checkedAt = scoped
          .map((record) => record.checkedAt)
          .reduce((first, second) => first.isAfter(second) ? first : second);
      if (ids.length > 1) {
        migrations.add(
          CloudWorkTmdbRecord.conflict(
            sourceId: work.sourceId,
            workKey: work.workKey,
            workRootId: work.root.id,
            workRootPath: work.root.remotePath,
            remoteName: work.remoteName,
            checkedAt: checkedAt,
            scrapeTitleOverride: customTitle,
          ),
        );
      } else if (ids.length == 1) {
        final anchor = matched.firstWhere(
          (record) => record.tmdbId == ids.single,
        );
        final seasonsByNumber = <int, TmdbSeasonMetadata>{
          for (final record in matched)
            for (final season in record.seasons) season.seasonNumber: season,
        };
        final seasons = seasonsByNumber.values.toList(growable: false)
          ..sort(
            (first, second) =>
                first.seasonNumber.compareTo(second.seasonNumber),
          );
        migrations.add(
          CloudWorkTmdbRecord.matched(
            sourceId: work.sourceId,
            workKey: work.workKey,
            workRootId: work.root.id,
            workRootPath: work.root.remotePath,
            remoteName: work.remoteName,
            checkedAt: checkedAt,
            scrapeTitleOverride: customTitle,
            posterCachePath: anchor.posterCachePath,
            metadata: _metadataFromLegacy(
              anchor,
              work.displayTitle,
              seasons,
            ),
          ),
        );
      } else if (customTitle != null) {
        migrations.add(
          CloudWorkTmdbRecord.unchecked(
            sourceId: work.sourceId,
            workKey: work.workKey,
            workRootId: work.root.id,
            workRootPath: work.root.remotePath,
            remoteName: work.remoteName,
            checkedAt: checkedAt,
            scrapeTitleOverride: customTitle,
          ),
        );
      }
    }
    return migrations;
  }

  TmdbMetadata _metadataFromLegacy(
    CloudResourceTmdbRecord record,
    String fallbackTitle,
    List<TmdbSeasonMetadata> seasons,
  ) {
    return TmdbMetadata(
      id: record.tmdbId!,
      mediaType: record.mediaType ?? TmdbMediaType.tv,
      title: record.title?.trim().isNotEmpty == true
          ? record.title!.trim()
          : fallbackTitle,
      originalTitle: record.originalTitle,
      overview: record.overview,
      releaseDate: record.releaseDate,
      rating: record.rating,
      posterUrl: record.posterUrl,
      backdropUrl: record.backdropUrl,
      language: 'zh-CN',
      matchedAt: record.checkedAt,
      matchConfidence: 1,
      seasons: seasons,
    );
  }

  Future<void> _autoScrape(
    CloudWorkIdentity work,
    String apiKey,
    int generation,
  ) async {
    _scrapingWorkKeys.add(work.workKey);
    if (generation == _generation) notifyListeners();
    try {
      final service = await _serviceFor(apiKey);
      await service.match(
        work,
        record: _records[work.workKey],
        options: _optionsProvider(),
      );
      if (generation == _generation) await _refreshRecord(work.workKey);
    } on Object {
      final failed = CloudWorkTmdbRecord.failed(
        sourceId: work.sourceId,
        workKey: work.workKey,
        workRootId: work.root.id,
        workRootPath: work.root.remotePath,
        remoteName: work.remoteName,
        checkedAt: _now(),
        scrapeTitleOverride: _records[work.workKey]?.scrapeTitleOverride,
      );
      await _repository.upsert(failed);
      if (generation == _generation) _records[work.workKey] = failed;
    } finally {
      _scrapingWorkKeys.remove(work.workKey);
      if (generation == _generation) {
        _completedCount++;
        notifyListeners();
      }
    }
  }

  Future<T> _tracked<T>(
    CloudWorkIdentity work,
    Future<T> Function() operation,
  ) async {
    _scrapingWorkKeys.add(work.workKey);
    notifyListeners();
    try {
      return await operation();
    } finally {
      _scrapingWorkKeys.remove(work.workKey);
      notifyListeners();
    }
  }

  Future<void> _refreshRecord(String workKey) async {
    final record = await _repository.get(workKey);
    if (record != null) _records[workKey] = record;
  }

  String _requiredApiKey() {
    final apiKey = _apiKeyProvider().trim();
    if (apiKey.isEmpty) throw StateError('请先在设置中填写 TMDB API Key');
    return apiKey;
  }

  Future<CloudWorkTmdbService> _serviceFor(String apiKey) async {
    if (_service == null || _serviceApiKey != apiKey) {
      _service = Future<CloudWorkTmdbService>.sync(
        () => _serviceFactory(apiKey),
      );
      _serviceApiKey = apiKey;
    }
    final service = _service!;
    try {
      return await service;
    } on Object {
      if (identical(_service, service)) _service = null;
      rethrow;
    }
  }

  String _normalizePath(String value) {
    var path = value.trim().replaceAll('\\', '/');
    path = path.replaceAll(RegExp(r'/+'), '/');
    if (path.isEmpty) return '/';
    if (!path.startsWith('/')) path = '/$path';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }
}
