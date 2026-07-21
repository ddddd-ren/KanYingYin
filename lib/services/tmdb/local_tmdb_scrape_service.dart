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
import 'package:kanyingyin/services/tmdb/tmdb_scraper.dart';
import 'package:path/path.dart' as p;

typedef TmdbPosterDownloader = Future<String?> Function(
  String posterUrl,
  String savePath,
);

class LocalTmdbScrapeService {
  LocalTmdbScrapeService({
    required this.indexRepository,
    required this.metadataRepository,
    required this.clientFactory,
    TmdbPosterDownloader? posterDownloader,
    this.subjectBuilder = const LocalTmdbSubjectBuilder(),
    this.mergePolicy = const TmdbMetadataMergePolicy(),
    this.posterPolicy = const TmdbPosterPolicy(),
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
      year: request.queryYear,
      seasonNumbers: base.seasonNumbers,
      episodeNumbers: base.episodeNumbers,
      mediaEvidence: base.mediaEvidence,
      existingMetadata: base.existingMetadata,
      fieldLocks: base.fieldLocks,
      matchOrigin: base.matchOrigin,
      ruleVersion: base.ruleVersion,
    );
    final outcome = await TmdbScrapeEngine(client: clientFactory(key)).search(
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
    final protected = subject.matchOrigin == TmdbMatchOrigin.manual ||
        subject.fieldLocks.title ||
        subject.fieldLocks.overview ||
        subject.fieldLocks.poster;
    if (!force &&
        allMatched &&
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
      final client = clientFactory(apiKey.trim());
      final search = await TmdbScrapeEngine(client: client).search(
        subject,
        resolvedOptions,
      );
      final candidates = search.ranked.candidates
          .map((candidate) => candidate.metadata)
          .toList(growable: false);
      final best = search.ranked.best;
      if (!search.ranked.shouldAutoMatch || best == null) {
        await _markPending(seriesItems);
        return TmdbScrapeResult(
          status: TmdbScrapeStatus.pending,
          metadata: subject.existingMetadata,
          candidates: candidates,
        );
      }
      if (_isProtectedConflict(subject, best.metadata)) {
        await _markPending(seriesItems);
        return TmdbScrapeResult(
          status: TmdbScrapeStatus.pending,
          metadata: subject.existingMetadata,
          candidates: candidates,
        );
      }

      final details = await client.details(
        best.metadata.id,
        best.metadata.mediaType,
        language: resolvedOptions.language,
      );
      final merged = <TmdbMetadata>[];
      for (final item in seriesItems) {
        final metadata = mergePolicy.merge(
          existing: item.tmdb,
          fetched: details,
          options: resolvedOptions,
          locks: TmdbFieldLocks(
            title: item.titleLocked,
            overview: item.overviewLocked,
            poster: item.posterLocked,
          ),
          matchConfidence: best.score,
          existingSeasons: subject.seasonNumbers,
        );
        merged.add(metadata);
        await indexRepository.updateItem(
          item.copyWith(
            tmdb: metadata,
            scrapeStatus: TmdbScrapeStatus.matched,
            tmdbMatchOrigin: TmdbMatchOrigin.automatic,
            tmdbRuleVersion: currentTmdbRuleVersion,
          ),
        );
      }
      await metadataRepository.save(normalizedKey, merged.first);
      final failures = await _downloadPosters(seriesItems, resolvedOptions);
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.matched,
        metadata: merged.first,
        candidates: candidates,
        posterDownloadFailures: failures,
      );
    } catch (error) {
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.failed,
        metadata: subject.existingMetadata,
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
      final details = await clientFactory(apiKey.trim()).details(
        candidate.id,
        candidate.mediaType,
        language: options.language,
      );
      final subject = subjectBuilder.build(
        seriesName: seriesName,
        items: seriesItems,
      );
      final merged = <TmdbMetadata>[];
      for (final item in seriesItems) {
        final metadata = mergePolicy.merge(
          existing: item.tmdb,
          fetched: details,
          options: options,
          locks: TmdbFieldLocks(
            title: item.titleLocked,
            overview: item.overviewLocked,
            poster: item.posterLocked,
          ),
          matchConfidence: 1,
          existingSeasons: subject.seasonNumbers,
        );
        merged.add(metadata);
        await indexRepository.updateItem(
          item.copyWith(
            tmdb: metadata,
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
    TmdbScrapeSubject subject,
    TmdbMetadata selected,
  ) {
    final existing = subject.existingMetadata;
    if (existing == null ||
        (existing.id == selected.id &&
            existing.mediaType == selected.mediaType)) {
      return false;
    }
    return subject.ruleVersion < currentTmdbRuleVersion ||
        subject.matchOrigin == TmdbMatchOrigin.manual ||
        subject.fieldLocks.title ||
        subject.fieldLocks.overview ||
        subject.fieldLocks.poster;
  }

  Future<void> _markPending(List<LocalMediaIndexItem> items) async {
    for (final item in items) {
      await indexRepository.updateItem(
        item.copyWith(
          scrapeStatus: TmdbScrapeStatus.pending,
          tmdbRuleVersion: currentTmdbRuleVersion,
        ),
      );
    }
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
}
