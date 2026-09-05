part of '../cloud_resources_controller.dart';

/// 作品级 TMDB：作品刮削、TMDB 变更同步与后台调度。
mixin _CloudTmdbWorkMixin on _CloudResourcesControllerBase {
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

  Future<TmdbRankedResult> searchWorkTmdb(
    CloudResourceMediaGroup group,
    CloudResourceTmdbSearchRequest request,
  ) {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 刮削服务不可用');
    return coordinator.searchPrepared(workForGroup(group), request,
        seasonNumber: group.seasonNumber);
  }

  Future<CloudWorkTmdbSelectionOutcome> applyWorkTmdbCandidate(
    CloudResourceMediaGroup group,
    TmdbRankedCandidate candidate, {
    required TmdbScrapeOptions options,
    bool wholeWork = false,
  }) async {
    final coordinator = _workTmdbCoordinator;
    if (coordinator == null) throw StateError('作品级 TMDB 刮削服务不可用');
    final seasonNumber = wholeWork ? null : group.seasonNumber;
    final works = worksForGroup(group);
    if (seasonNumber != null) {
      final metadata = group.workRecord?.metadata;
      if (metadata != null &&
          (metadata.id != candidate.metadata.id ||
              metadata.mediaType != candidate.metadata.mediaType)) {
        throw CloudWorkTmdbIdentityChangeException();
      }
    }
    final selectedWorkKeys = group.videos
        .map(_indexedItemFor)
        .whereType<CloudMediaIndexItem>()
        .map((item) => item.workKey)
        .toSet();
    CloudWorkTmdbSelectionOutcome? first;
    for (final work in works) {
      if (seasonNumber != null && !selectedWorkKeys.contains(work.workKey)) {
        continue;
      }
      final outcome = await coordinator.selectPrepared(
        work,
        candidate,
        options: options,
        seasonNumber: seasonNumber,
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

  @override
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

  @override
  void _handleTmdbChange() {
    final resourceRevision = _tmdbCoordinator?.recordsRevision ?? 0;
    final workRevision = _workTmdbCoordinator?.recordsRevision ?? 0;
    final recordsChanged = resourceRevision != _resourceTmdbRecordsRevision ||
        workRevision != _workTmdbRecordsRevision;
    if (recordsChanged) {
      _resourceTmdbRecordsRevision = resourceRevision;
      _workTmdbRecordsRevision = workRevision;
      _syncIndexedTmdbMetadata();
      _reconcileSelectedGenres();
      _invalidateCollection();
      unawaited(reloadMediaLibrarySnapshot().catchError((_) {}));
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
}
