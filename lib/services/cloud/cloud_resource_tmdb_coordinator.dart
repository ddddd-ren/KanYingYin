import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

typedef CloudResourceTmdbServiceFactory = FutureOr<CloudResourceTmdbService>
    Function(String apiKey);

class CloudResourceDirectoryContext {
  const CloudResourceDirectoryContext({
    required this.source,
    required this.directory,
    required this.entries,
    required this.isConfiguredRoot,
  });

  final CloudSource source;
  final CloudRemoteRef directory;
  final List<CloudFileEntry> entries;
  final bool isConfiguredRoot;
}

class CloudResourceTmdbCoordinator extends ChangeNotifier {
  CloudResourceTmdbCoordinator({
    required CloudResourceTmdbRepository repository,
    required CloudResourceTmdbServiceFactory serviceFactory,
    required String Function() apiKeyProvider,
    TmdbScrapeOptions Function()? optionsProvider,
    DateTime Function()? now,
  })  : _repository = repository,
        _serviceFactory = serviceFactory,
        _apiKeyProvider = apiKeyProvider,
        _optionsProvider =
            optionsProvider ?? (() => const TmdbScrapeOptions.defaults()),
        _now = now ?? DateTime.now;

  static const Duration unmatchedRetryInterval = Duration(days: 7);
  static const int maximumConcurrentScrapes = 2;

  final CloudResourceTmdbRepository _repository;
  final CloudResourceTmdbServiceFactory _serviceFactory;
  final String Function() _apiKeyProvider;
  final TmdbScrapeOptions Function() _optionsProvider;
  final DateTime Function() _now;
  final Map<String, CloudResourceTmdbRecord> _records =
      <String, CloudResourceTmdbRecord>{};
  final Set<String> _scrapingKeys = <String>{};

  int _generation = 0;
  int _completedCount = 0;
  int _totalCount = 0;
  String? _serviceApiKey;
  Future<CloudResourceTmdbService>? _service;

  Map<String, CloudResourceTmdbRecord> get records =>
      UnmodifiableMapView<String, CloudResourceTmdbRecord>(_records);

  Set<String> get scrapingKeys => UnmodifiableSetView<String>(_scrapingKeys);

  int get completedCount => _completedCount;
  int get totalCount => _totalCount;
  bool get isScraping => _scrapingKeys.isNotEmpty;
  TmdbScrapeOptions get options => _optionsProvider();

  Future<void> loadAndSchedule(CloudResourceDirectoryContext context) async {
    final generation = ++_generation;
    final stored = await _repository.getBySource(context.source.id);
    if (generation != _generation) return;
    _records
      ..clear()
      ..addEntries(stored.map((record) => MapEntry(record.stableKey, record)));
    _scrapingKeys.clear();
    _completedCount = 0;
    _totalCount = 0;
    notifyListeners();

    final apiKey = _apiKeyProvider().trim();
    if (apiKey.isEmpty) return;
    final targets = _targetsToSchedule(context, _now());
    _totalCount = targets.length;
    if (targets.isEmpty) {
      notifyListeners();
      return;
    }
    notifyListeners();

    var nextIndex = 0;
    Future<void> worker() async {
      while (generation == _generation && nextIndex < targets.length) {
        final target = targets[nextIndex++];
        await _autoScrape(target, apiKey, generation);
      }
    }

    final workerCount = targets.length < maximumConcurrentScrapes
        ? targets.length
        : maximumConcurrentScrapes;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
  }

  Future<CloudResourceTmdbOutcome> scrape(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions? options,
  }) async {
    final apiKey = _requiredApiKey();
    return _tracked(target, () async {
      final service = await _serviceFor(apiKey);
      final outcome = await service.match(
        target,
        options: options ?? _optionsProvider(),
      );
      await _refreshRecord(target);
      return outcome;
    });
  }

  Future<CloudResourceTmdbOutcome> rematch(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions? options,
  }) async {
    final apiKey = _requiredApiKey();
    return _tracked(target, () async {
      final service = await _serviceFor(apiKey);
      return service.searchCandidates(
        target,
        options: options ?? _optionsProvider(),
      );
    });
  }

  Future<CloudResourceTmdbRecord> select(
    CloudResourceTmdbTarget target,
    TmdbMetadata candidate, {
    TmdbScrapeOptions? options,
  }) async {
    final apiKey = _requiredApiKey();
    return _tracked(target, () async {
      final service = await _serviceFor(apiKey);
      final record = await service.select(
        target,
        candidate,
        options: options ?? _optionsProvider(),
      );
      _records[record.stableKey] = record;
      return record;
    });
  }

  Future<CloudResourceTmdbRecord> saveCustomTitle(
    CloudResourceTmdbTarget target,
    String title,
  ) async {
    final normalized = title.trim();
    if (normalized.isEmpty) throw ArgumentError.value(title, 'title');
    final existing = await _repository.get(target.stableKey);
    final record = (existing ?? _uncheckedRecord(target)).withCustomTitle(
      normalized,
    );
    await _repository.upsert(record);
    _records[record.stableKey] = record;
    notifyListeners();
    return record;
  }

  Future<CloudResourceTmdbRecord> clearCustomTitle(
    CloudResourceTmdbTarget target,
  ) async {
    final existing = await _repository.get(target.stableKey);
    final record = (existing ?? _uncheckedRecord(target)).clearCustomTitle();
    await _repository.upsert(record);
    _records[record.stableKey] = record;
    notifyListeners();
    return record;
  }

  List<CloudResourceTmdbTarget> _targetsToSchedule(
    CloudResourceDirectoryContext context,
    DateTime now,
  ) {
    final targets = <CloudResourceTmdbTarget>[];
    for (final entry in context.entries) {
      final kind = entry.isDirectory
          ? CloudResourceKind.directory
          : CloudResourceKind.standaloneVideo;
      if (!entry.isDirectory &&
          (!context.isConfiguredRoot ||
              !LocalVideoFileTypes.isVideoPath(entry.name))) {
        continue;
      }
      final cached = _records[cloudResourceTmdbKey(
        sourceId: context.source.id,
        remoteId: entry.id,
        remotePath: entry.remotePath,
      )];
      final target = CloudResourceTmdbTarget(
        sourceId: context.source.id,
        remote: CloudRemoteRef(id: entry.id, path: entry.remotePath),
        displayName: entry.name,
        resourceKind: kind,
        customTitle: cached?.customTitle,
      );
      if (cached != null && cached.displayName == target.displayName) {
        if (cached.status == CloudResourceTmdbStatus.matched) continue;
        if (cached.status == CloudResourceTmdbStatus.unmatched &&
            cached.checkedAt.add(unmatchedRetryInterval).isAfter(now)) {
          continue;
        }
      }
      targets.add(target);
    }
    return targets;
  }

  Future<void> _autoScrape(
    CloudResourceTmdbTarget target,
    String apiKey,
    int generation,
  ) async {
    _scrapingKeys.add(target.stableKey);
    if (generation == _generation) notifyListeners();
    try {
      final service = await _serviceFor(apiKey);
      await service.match(target, options: _optionsProvider());
      if (generation == _generation) await _refreshRecord(target);
    } on Object {
      final failed = CloudResourceTmdbRecord.failed(
        sourceId: target.sourceId,
        remoteId: target.remote.id,
        remotePath: target.remote.path,
        displayName: target.displayName,
        resourceKind: target.resourceKind,
        checkedAt: _now(),
        customTitle: target.customTitle,
      );
      await _repository.upsert(failed);
      if (generation == _generation) {
        _records[failed.stableKey] = failed;
      }
    } finally {
      _scrapingKeys.remove(target.stableKey);
      if (generation == _generation) {
        _completedCount++;
        notifyListeners();
      }
    }
  }

  Future<T> _tracked<T>(
    CloudResourceTmdbTarget target,
    Future<T> Function() operation,
  ) async {
    _scrapingKeys.add(target.stableKey);
    notifyListeners();
    try {
      return await operation();
    } finally {
      _scrapingKeys.remove(target.stableKey);
      notifyListeners();
    }
  }

  Future<void> _refreshRecord(CloudResourceTmdbTarget target) async {
    final record = await _repository.get(target.stableKey);
    if (record != null) _records[record.stableKey] = record;
  }

  CloudResourceTmdbRecord _uncheckedRecord(
    CloudResourceTmdbTarget target,
  ) {
    return CloudResourceTmdbRecord.unchecked(
      sourceId: target.sourceId,
      remoteId: target.remote.id,
      remotePath: target.remote.path,
      displayName: target.displayName,
      resourceKind: target.resourceKind,
      checkedAt: _now(),
      customTitle: target.customTitle,
    );
  }

  String _requiredApiKey() {
    final apiKey = _apiKeyProvider().trim();
    if (apiKey.isEmpty) throw StateError('请先在设置中填写 TMDB API Key');
    return apiKey;
  }

  Future<CloudResourceTmdbService> _serviceFor(String apiKey) async {
    if (_service == null || _serviceApiKey != apiKey) {
      _service = Future<CloudResourceTmdbService>.sync(
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
}
