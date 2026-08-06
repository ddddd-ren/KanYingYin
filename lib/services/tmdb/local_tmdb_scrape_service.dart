import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/services/poster_service.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_subject_builder.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_metadata_merge_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_poster_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_engine.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_cache.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scraper.dart';
import 'package:path/path.dart' as p;

typedef TmdbPosterDownloader = Future<String?> Function(
  String posterUrl,
  String savePath,
);
typedef TmdbScrapeEngineFactory = TmdbScrapeEngine Function(
  ITmdbClient client,
);
typedef TmdbScrapeCacheFactory = TmdbScrapeCache Function(String apiKey);

class LocalTmdbScrapeService {
  LocalTmdbScrapeService({
    required this.indexRepository,
    required this.metadataRepository,
    required this.clientFactory,
    TmdbPosterDownloader? posterDownloader,
    this.subjectBuilder = const LocalTmdbSubjectBuilder(),
    this.mergePolicy = const TmdbMetadataMergePolicy(),
    this.posterPolicy = const TmdbPosterPolicy(),
    this.engineFactory,
    this.cacheFactory,
  }) : posterDownloader = posterDownloader ??
            ((url, path) =>
                PosterService().downloadPosterTo(url, path, overwrite: true));

  final ILocalMediaIndexRepository indexRepository;
  final ITmdbMetadataRepository metadataRepository;
  final ITmdbClient Function(String apiKey) clientFactory;
  final TmdbPosterDownloader posterDownloader;
  final LocalTmdbSubjectBuilder subjectBuilder;
  final TmdbMetadataMergePolicy mergePolicy;
  final TmdbPosterPolicy posterPolicy;
  final TmdbScrapeEngineFactory? engineFactory;
  final TmdbScrapeCacheFactory? cacheFactory;
  final Map<String, TmdbScrapeCache> _fallbackCaches =
      <String, TmdbScrapeCache>{};

  TmdbScrapeEngine _engineFor(ITmdbClient client, String apiKey) {
    final custom = engineFactory;
    if (custom != null) return custom(client);
    final cache = cacheFactory?.call(apiKey) ??
        (_fallbackCaches[apiKey] ??= TmdbScrapeCache());
    return TmdbScrapeEngine(client: client, cache: cache);
  }

  Future<TmdbPreparedSearchOutcome> searchPrepared({
    required String apiKey,
    required String seriesName,
    required TmdbPreparedSearchRequest request,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw StateError('请先在设置中填写 TMDB API Key');
    }
    final normalizedSeries = seriesName.trim().toLowerCase();
    final items = indexRepository
        .getAll()
        .where(
          (item) => item.seriesName.trim().toLowerCase() == normalizedSeries,
        )
        .toList(growable: false);
    if (items.isEmpty) {
      throw StateError('本地媒体索引中没有该作品');
    }
    final base = subjectBuilder.build(seriesName: seriesName, items: items);
    final subject = TmdbScrapeSubject(
      stableKey: base.stableKey,
      titleCandidates: <String>[request.queryTitle],
      manualSearchTitle: request.queryTitle,
      year: request.queryYear,
      seasonNumbers: base.seasonNumbers,
      episodeNumbers: base.episodeNumbers,
      mediaEvidence: base.mediaEvidence,
      existingMetadata: base.existingMetadata,
      fieldLocks: base.fieldLocks,
      matchOrigin: base.matchOrigin,
      ruleVersion: base.ruleVersion,
    );
    final client = clientFactory(key);
    final engine = _engineFor(client, key);
    final outcome = await engine.search(
      subject,
      request.options.copyWith(mediaTypeMode: request.mediaTypeMode),
    );
    return TmdbPreparedSearchOutcome(ranked: outcome.ranked);
  }

  Future<TmdbPreparedSearchOutcome> searchItemPrepared({
    required String apiKey,
    required String itemId,
    required TmdbPreparedSearchRequest request,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw StateError('请先在设置中填写 TMDB API Key');
    }
    final item = _findItem(itemId);
    if (item == null) {
      throw StateError('本地媒体索引中不存在该视频');
    }
    final base = subjectBuilder.build(
      seriesName: item.seriesName,
      items: <LocalMediaIndexItem>[item],
    );
    final subject = TmdbScrapeSubject(
      stableKey: item.id,
      titleCandidates: <String>[request.queryTitle],
      manualSearchTitle: request.queryTitle,
      year: request.queryYear,
      seasonNumbers: base.seasonNumbers,
      episodeNumbers: base.episodeNumbers,
      mediaEvidence: base.mediaEvidence,
      existingMetadata: item.tmdb,
      fieldLocks: base.fieldLocks,
      matchOrigin: item.tmdbMatchOrigin,
      ruleVersion: item.tmdbRuleVersion,
    );
    final client = clientFactory(key);
    final engine = _engineFor(client, key);
    final outcome = await engine.search(
      subject,
      request.options.copyWith(mediaTypeMode: request.mediaTypeMode),
    );
    return TmdbPreparedSearchOutcome(ranked: outcome.ranked);
  }

  Future<TmdbScrapeResult> scrapeSeries({
    required String apiKey,
    required String seriesName,
    TmdbMediaType? mediaType,
    bool force = false,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final normalizedKey = seriesName.trim().toLowerCase();
    final seriesItems = indexRepository
        .getAll()
        .where((item) => item.seriesName.trim().toLowerCase() == normalizedKey)
        .toList(growable: false);
    if (apiKey.trim().isEmpty || seriesItems.isEmpty) {
      return const TmdbScrapeResult(status: TmdbScrapeStatus.none);
    }

    final resolvedOptions = mediaType == null
        ? options
        : options.copyWith(
            mediaTypeMode: mediaType == TmdbMediaType.movie
                ? TmdbMediaTypeMode.movie
                : TmdbMediaTypeMode.tv,
          );
    final subject = subjectBuilder.build(
      seriesName: seriesName,
      items: seriesItems,
    );
    final allMatched = seriesItems.every(
      (item) =>
          item.scrapeStatus == TmdbScrapeStatus.matched && item.tmdb != null,
    );
    final needsEpisodeHydration = seriesItems.any(_needsEpisodeHydration);
    final protected = subject.matchOrigin == TmdbMatchOrigin.manual ||
        subject.fieldLocks.title ||
        subject.fieldLocks.overview ||
        subject.fieldLocks.poster;
    if (!force &&
        allMatched &&
        !needsEpisodeHydration &&
        (subject.ruleVersion >= currentTmdbRuleVersion || protected)) {
      if (subject.ruleVersion < currentTmdbRuleVersion) {
        for (final item in seriesItems) {
          await indexRepository.updateItem(
            item.copyWith(tmdbRuleVersion: currentTmdbRuleVersion),
          );
        }
      }
      final failures = await _downloadPosters(seriesItems, resolvedOptions);
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.matched,
        metadata: subject.existingMetadata,
        posterDownloadFailures: failures,
      );
    }

    try {
      final key = apiKey.trim();
      final client = clientFactory(key);
      final engine = _engineFor(client, key);
      final search = await engine.search(
        subject,
        resolvedOptions,
      );
      final candidates = search.ranked.candidates
          .map((candidate) => candidate.metadata)
          .toList(growable: false);
      final best = search.ranked.best;
      if (!search.ranked.shouldAutoMatch || best == null) {
        final isolated = await _markPending(
          seriesItems,
          clearAutomaticMatches: force,
        );
        return TmdbScrapeResult(
          status: TmdbScrapeStatus.pending,
          metadata: subject.existingMetadata,
          candidates: candidates,
          isolatedItemIds: isolated,
        );
      }

      final details = await engine.details(
        best.metadata.id,
        best.metadata.mediaType,
        language: resolvedOptions.language,
      );
      final hydratedDetails = await engine.hydrateSeasons(
        details,
        seasonNumbers: subject.seasonNumbers,
        language: resolvedOptions.language,
      );
      final merged = <TmdbMetadata>[];
      final isolatedItemIds = <String>[];
      for (final item in seriesItems) {
        if (_isProtectedConflict(item, best.metadata)) {
          isolatedItemIds.add(item.id);
          if (!_hasProtectedMatch(item)) {
            await indexRepository.updateItem(
              item.copyWith(
                scrapeStatus: TmdbScrapeStatus.pending,
                tmdbRuleVersion: currentTmdbRuleVersion,
              ),
            );
          }
          continue;
        }
        final metadata = mergePolicy.merge(
          existing: item.tmdb,
          fetched: hydratedDetails,
          options: resolvedOptions,
          locks: TmdbFieldLocks(
            title: item.titleLocked,
            overview: item.overviewLocked,
            poster: item.posterLocked,
          ),
          matchConfidence: best.score,
          // 本地索引按季度选海报，但保存的作品资料必须包含全部季度。
          existingSeasons: hydratedDetails.mediaType == TmdbMediaType.tv
              ? const <int>{}
              : subject.seasonNumbers,
        );
        merged.add(metadata);
        await indexRepository.updateItem(
          item.copyWith(
            tmdb: metadata,
            tmdbIdentity: _tmdbIdentity(metadata),
            scrapeStatus: TmdbScrapeStatus.matched,
            tmdbMatchOrigin: item.tmdbMatchOrigin == TmdbMatchOrigin.manual
                ? TmdbMatchOrigin.manual
                : TmdbMatchOrigin.automatic,
            tmdbRuleVersion: currentTmdbRuleVersion,
          ),
        );
      }
      if (merged.isEmpty) {
        return TmdbScrapeResult(
          status: TmdbScrapeStatus.pending,
          metadata: subject.existingMetadata,
          candidates: candidates,
          isolatedItemIds: isolatedItemIds,
        );
      }
      await metadataRepository.save(normalizedKey, merged.first);
      final failures = await _downloadPosters(
        seriesItems
            .where((item) => !isolatedItemIds.contains(item.id))
            .toList(growable: false),
        resolvedOptions,
      );
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.matched,
        metadata: merged.first,
        candidates: candidates,
        posterDownloadFailures: failures,
        isolatedItemIds: isolatedItemIds,
      );
    } catch (error) {
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.failed,
        metadata: subject.existingMetadata,
        error: error,
      );
    }
  }

  Future<TmdbScrapeResult> scrapeItem({
    required String apiKey,
    required String itemId,
    bool force = true,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const TmdbScrapeResult(status: TmdbScrapeStatus.none);
    }
    final item = _findItem(itemId);
    if (item == null) {
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.failed,
        error: StateError('本地媒体索引中不存在该视频'),
      );
    }
    final subject = subjectBuilder.build(
      seriesName: item.seriesName,
      items: <LocalMediaIndexItem>[item],
    );
    final resolvedOptions = item.episodeInfo == null
        ? options
        : options.copyWith(mediaTypeMode: TmdbMediaTypeMode.tv);
    try {
      final client = clientFactory(key);
      final engine = _engineFor(client, key);
      final search = await engine.search(subject, resolvedOptions);
      final candidates = search.ranked.candidates
          .map((candidate) => candidate.metadata)
          .toList(growable: false);
      final best = search.ranked.best;
      if (!search.ranked.shouldAutoMatch || best == null) {
        final isolated = force && !_hasProtectedMatch(item)
            ? await _resetAutomaticMatchToPending(item)
            : await _markPending(<LocalMediaIndexItem>[item]);
        return TmdbScrapeResult(
          status: TmdbScrapeStatus.pending,
          metadata: item.tmdb,
          candidates: candidates,
          isolatedItemIds: isolated,
        );
      }
      if (_isProtectedConflict(item, best.metadata,
          allowAutomaticReplacement: force)) {
        return TmdbScrapeResult(
          status: TmdbScrapeStatus.pending,
          metadata: item.tmdb,
          candidates: candidates,
          isolatedItemIds: <String>[item.id],
        );
      }
      final details = await engine.details(
        best.metadata.id,
        best.metadata.mediaType,
        language: resolvedOptions.language,
      );
      final hydrated = await engine.hydrateSeasons(
        details,
        seasonNumbers: <int>[
          if ((item.seasonNumber ?? 0) > 0) item.seasonNumber!
        ],
        language: resolvedOptions.language,
      );
      final metadata = mergePolicy.merge(
        existing: item.tmdb,
        fetched: hydrated,
        options: resolvedOptions,
        locks: TmdbFieldLocks(
          title: item.titleLocked,
          overview: item.overviewLocked,
          poster: item.posterLocked,
        ),
        matchConfidence: best.score,
        existingSeasons: hydrated.mediaType == TmdbMediaType.tv
            ? const <int>{}
            : subject.seasonNumbers,
      );
      final updated = item.copyWith(
        tmdb: metadata,
        tmdbIdentity: _tmdbIdentity(metadata),
        scrapeStatus: TmdbScrapeStatus.matched,
        tmdbMatchOrigin: TmdbMatchOrigin.automatic,
        tmdbRuleVersion: currentTmdbRuleVersion,
      );
      await indexRepository.updateItem(updated);
      await metadataRepository.save(
          item.seriesName.trim().toLowerCase(), metadata);
      final failures = await _downloadPosters(
        <LocalMediaIndexItem>[updated],
        resolvedOptions,
      );
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.matched,
        metadata: metadata,
        candidates: candidates,
        posterDownloadFailures: failures,
      );
    } catch (error) {
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.failed,
        metadata: item.tmdb,
        error: error,
      );
    }
  }

  Future<TmdbScrapeResult> selectItemCandidate({
    required String apiKey,
    required String itemId,
    required TmdbMetadata candidate,
    String? seriesNameOverride,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const TmdbScrapeResult(status: TmdbScrapeStatus.none);
    }
    final item = _findItem(itemId);
    if (item == null) {
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.failed,
        error: StateError('本地媒体索引中不存在该视频'),
      );
    }
    try {
      final client = clientFactory(key);
      final engine = _engineFor(client, key);
      final details = await engine.details(
        candidate.id,
        candidate.mediaType,
        language: options.language,
      );
      final subject = subjectBuilder.build(
        seriesName: item.seriesName,
        items: <LocalMediaIndexItem>[item],
      );
      final hydrated = await engine.hydrateSeasons(
        details,
        seasonNumbers: <int>[
          if ((item.seasonNumber ?? 0) > 0) item.seasonNumber!
        ],
        language: options.language,
      );
      final metadata = mergePolicy.merge(
        existing: item.tmdb,
        fetched: hydrated,
        options: options,
        locks: TmdbFieldLocks(
          title: item.titleLocked,
          overview: item.overviewLocked,
          poster: item.posterLocked,
        ),
        matchConfidence: 1,
        existingSeasons: hydrated.mediaType == TmdbMediaType.tv
            ? const <int>{}
            : subject.seasonNumbers,
      );
      final updated = item.copyWith(
        seriesName: seriesNameOverride?.trim().isEmpty == true
            ? item.seriesName
            : seriesNameOverride?.trim(),
        tmdb: metadata,
        tmdbIdentity: _tmdbIdentity(metadata),
        scrapeStatus: TmdbScrapeStatus.matched,
        tmdbMatchOrigin: TmdbMatchOrigin.manual,
        tmdbRuleVersion: currentTmdbRuleVersion,
      );
      await indexRepository.updateItem(updated);
      await metadataRepository.save(
          updated.seriesName.trim().toLowerCase(), metadata);
      final failures = await _downloadPosters(
        <LocalMediaIndexItem>[updated],
        options,
      );
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.matched,
        metadata: metadata,
        posterDownloadFailures: failures,
      );
    } catch (error) {
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.failed,
        metadata: item.tmdb,
        error: error,
      );
    }
  }

  Future<TmdbScrapeResult> selectCandidate({
    required String apiKey,
    required String seriesName,
    required TmdbMetadata candidate,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    if (apiKey.trim().isEmpty) {
      return const TmdbScrapeResult(status: TmdbScrapeStatus.none);
    }
    final normalizedKey = seriesName.trim().toLowerCase();
    final seriesItems = indexRepository
        .getAll()
        .where((item) => item.seriesName.trim().toLowerCase() == normalizedKey)
        .toList(growable: false);
    if (seriesItems.isEmpty) {
      return const TmdbScrapeResult(status: TmdbScrapeStatus.none);
    }

    try {
      final key = apiKey.trim();
      final client = clientFactory(key);
      final engine = _engineFor(client, key);
      final details = await engine.details(
        candidate.id,
        candidate.mediaType,
        language: options.language,
      );
      final subject = subjectBuilder.build(
        seriesName: seriesName,
        items: seriesItems,
      );
      final hydratedDetails = await engine.hydrateSeasons(
        details,
        seasonNumbers: subject.seasonNumbers,
        language: options.language,
      );
      final merged = <TmdbMetadata>[];
      for (final item in seriesItems) {
        final metadata = mergePolicy.merge(
          existing: item.tmdb,
          fetched: hydratedDetails,
          options: options,
          locks: TmdbFieldLocks(
            title: item.titleLocked,
            overview: item.overviewLocked,
            poster: item.posterLocked,
          ),
          matchConfidence: 1,
          // 本地索引按季度选海报，但保存的作品资料必须包含全部季度。
          existingSeasons: hydratedDetails.mediaType == TmdbMediaType.tv
              ? const <int>{}
              : subject.seasonNumbers,
        );
        merged.add(metadata);
        await indexRepository.updateItem(
          item.copyWith(
            tmdb: metadata,
            tmdbIdentity: _tmdbIdentity(metadata),
            scrapeStatus: TmdbScrapeStatus.matched,
            tmdbMatchOrigin: TmdbMatchOrigin.manual,
            tmdbRuleVersion: currentTmdbRuleVersion,
          ),
        );
      }
      await metadataRepository.save(normalizedKey, merged.first);
      final failures = await _downloadPosters(seriesItems, options);
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.matched,
        metadata: merged.first,
        posterDownloadFailures: failures,
      );
    } catch (error) {
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.failed,
        error: error,
      );
    }
  }

  bool _isProtectedConflict(
    LocalMediaIndexItem item,
    TmdbMetadata selected, {
    bool allowAutomaticReplacement = false,
  }) {
    final existing = item.tmdb;
    if (existing == null ||
        (existing.id == selected.id &&
            existing.mediaType == selected.mediaType)) {
      return false;
    }
    if (_hasProtectedMatch(item)) {
      return true;
    }
    return !allowAutomaticReplacement &&
        item.tmdbRuleVersion < currentTmdbRuleVersion;
  }

  bool _needsEpisodeHydration(LocalMediaIndexItem item) {
    final metadata = item.tmdb;
    if (metadata?.mediaType != TmdbMediaType.tv) return false;
    if ((item.seasonNumber ?? 0) <= 0 || (item.episodeNumber ?? 0) <= 0) {
      return false;
    }
    return !item.hasTmdbEpisodeTitle;
  }

  Future<List<String>> _markPending(
    List<LocalMediaIndexItem> items, {
    bool clearAutomaticMatches = false,
  }) async {
    final isolated = <String>[];
    for (final item in items) {
      if (_hasProtectedMatch(item)) {
        isolated.add(item.id);
        continue;
      }
      final clearAutomatic = clearAutomaticMatches &&
          item.tmdbMatchOrigin == TmdbMatchOrigin.automatic;
      await indexRepository.updateItem(
        item.copyWith(
          clearTmdb: clearAutomatic,
          clearTmdbIdentity: clearAutomatic,
          scrapeStatus: TmdbScrapeStatus.pending,
          tmdbMatchOrigin: clearAutomatic
              ? TmdbMatchOrigin.legacyUnknown
              : item.tmdbMatchOrigin,
          tmdbRuleVersion: currentTmdbRuleVersion,
        ),
      );
    }
    return isolated;
  }

  bool _hasProtectedMatch(LocalMediaIndexItem item) {
    return item.tmdbMatchOrigin == TmdbMatchOrigin.manual ||
        item.titleLocked ||
        item.overviewLocked ||
        item.posterLocked;
  }

  Future<List<String>> _resetAutomaticMatchToPending(
    LocalMediaIndexItem item,
  ) async {
    await indexRepository.updateItem(
      item.copyWith(
        clearTmdb: true,
        clearTmdbIdentity: true,
        scrapeStatus: TmdbScrapeStatus.pending,
        tmdbMatchOrigin: TmdbMatchOrigin.legacyUnknown,
        tmdbRuleVersion: currentTmdbRuleVersion,
      ),
    );
    return const <String>[];
  }

  LocalMediaIndexItem? _findItem(String itemId) {
    for (final item in indexRepository.getAll()) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  Future<int> _downloadPosters(
    List<LocalMediaIndexItem> seriesItems,
    TmdbScrapeOptions options,
  ) async {
    final itemsByDirectory = <String, List<LocalMediaIndexItem>>{};
    for (final original in seriesItems) {
      final item = indexRepository.getByPath(original.path) ?? original;
      if (item.posterLocked || !options.fetchPoster) continue;
      final metadata = item.tmdb;
      if (metadata == null) continue;
      final posterPath = posterPolicy.select(
        metadata,
        seasonNumber: item.seasonNumber,
        options: options,
        locks: TmdbFieldLocks(poster: item.posterLocked),
        existingPoster: item.cover,
      );
      if (posterPath == null) continue;
      (itemsByDirectory[p.dirname(item.path)] ??= <LocalMediaIndexItem>[])
          .add(item);
    }

    var failures = 0;
    for (final entry in itemsByDirectory.entries) {
      final first = entry.value.first;
      final posterPath = posterPolicy.select(
        first.tmdb!,
        seasonNumber: first.seasonNumber,
        options: options,
        existingPoster: first.cover,
      );
      if (posterPath == null) continue;
      final url = posterPath.startsWith('http')
          ? posterPath
          : 'https://image.tmdb.org/t/p/w780$posterPath';
      final target = p.join(entry.key, 'tmdb-poster.jpg');
      final savedPath = await posterDownloader(url, target);
      if (savedPath == null) {
        failures++;
        continue;
      }
      for (final item in entry.value) {
        final latest = indexRepository.getByPath(item.path) ?? item;
        await indexRepository.updateItem(latest.copyWith(cover: savedPath));
      }
    }
    return failures;
  }

  String _tmdbIdentity(TmdbMetadata metadata) {
    return '${metadata.mediaType.name}:${metadata.id}';
  }
}
