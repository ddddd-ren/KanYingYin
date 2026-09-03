part of '../cloud_resources_controller.dart';

/// 条目级 TMDB：单视频刮削入口与索引详情查询。
mixin _CloudTmdbEntryMixin on _CloudResourcesControllerBase {
  CloudRemoteRef? subtitleFor(CloudFileEntry video) =>
      _indexedItemFor(video)?.subtitleRefs.firstOrNull;

  bool hasSubtitle(CloudFileEntry video) =>
      _indexedItemFor(video)?.subtitleRefs.isNotEmpty == true;

  @override
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

  @override
  CloudMediaIndexItem? _indexedItemFor(CloudFileEntry entry) {
    final source = selectedSource;
    if (source == null) return null;
    return _indexedItems[cloudResourceTmdbKey(
      sourceId: source.id,
      remoteId: entry.id,
      remotePath: entry.remotePath,
    )];
  }
}
