import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_metadata_merge_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_engine.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_cache.dart';

class CloudTmdbMatchOutcome {
  const CloudTmdbMatchOutcome({required this.candidates, this.selected});
  final List<TmdbMetadata> candidates;
  final TmdbMetadata? selected;
}

/// 兼容旧控制器的门面，搜索统一委托给共享刮削引擎。
class CloudTmdbMetadataService {
  CloudTmdbMetadataService({
    required CloudMediaIndexRepository repository,
    required ITmdbClient client,
    CloudPosterCache? posterCache,
    TmdbScrapeEngine? engine,
    TmdbScrapeCache? cache,
  })  : _repository = repository,
        _engine = engine ?? TmdbScrapeEngine(client: client, cache: cache),
        _posterCache = posterCache;

  final CloudMediaIndexRepository _repository;
  final TmdbScrapeEngine _engine;
  final CloudPosterCache? _posterCache;

  Future<CloudTmdbMatchOutcome> match({
    required String sourceId,
    required String seriesName,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final subject = await _subjectFor(sourceId, seriesName, options);
    final outcome = await _engine.search(subject, options);
    final candidates = outcome.ranked.candidates
        .map((candidate) => candidate.metadata)
        .toList(growable: false);
    final best = outcome.ranked.best;
    if (!outcome.ranked.shouldAutoMatch || best == null) {
      return CloudTmdbMatchOutcome(candidates: candidates);
    }
    final selected = await select(
      sourceId: sourceId,
      seriesName: seriesName,
      candidate: best.metadata,
      options: options,
    );
    return CloudTmdbMatchOutcome(candidates: candidates, selected: selected);
  }

  Future<CloudTmdbMatchOutcome> searchCandidates({
    required String seriesName,
    String? sourceId,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final subject = await _subjectFor(sourceId ?? '', seriesName, options);
    final outcome = await _engine.search(subject, options);
    return CloudTmdbMatchOutcome(
      candidates: outcome.ranked.candidates
          .map((candidate) => candidate.metadata)
          .toList(growable: false),
    );
  }

  Future<TmdbMetadata> select({
    required String sourceId,
    required String seriesName,
    required TmdbMetadata candidate,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final items = await _repository.getBySource(sourceId);
    final normalizedSeries = seriesName.trim().toLowerCase();
    final existing = items
        .where(
          (item) => item.seriesName.trim().toLowerCase() == normalizedSeries,
        )
        .map(_metadataFromItem)
        .nonNulls
        .firstOrNull;
    final details = await _engine.details(
      candidate.id,
      candidate.mediaType,
      language: options.language,
    );
    final subject = _subjectFromItems(
      sourceId,
      seriesName,
      items,
      options,
    );
    final metadata = await _engine.hydrateSeasons(
      details,
      seasonNumbers: subject.seasonNumbers,
      language: options.language,
    );
    final merged = const TmdbMetadataMergePolicy().merge(
      existing: existing,
      fetched: metadata,
      options: options,
      matchConfidence: candidate.matchConfidence,
      existingSeasons: const <int>{},
    );
    String? cachePath;
    final poster = merged.posterUrl;
    if (_posterCache != null && options.fetchPoster && poster != null) {
      cachePath = await _posterCache.resolve(
        sourceId: sourceId,
        stableId: seriesName.toLowerCase(),
        url: _imageUrl(poster),
      );
      if (cachePath == _imageUrl(poster)) cachePath = null;
    }
    final matchedCount = await _repository.updateMatching(
      sourceId,
      (item) => item.seriesName.trim().toLowerCase() == normalizedSeries,
      (item) => item.replaceTmdb(
        tmdbId: merged.id,
        tmdbTitle: merged.title,
        tmdbOriginalTitle: merged.originalTitle,
        tmdbOverview: merged.overview,
        tmdbRating: merged.rating,
        tmdbPosterUrl: merged.posterUrl,
        tmdbBackdropUrl: merged.backdropUrl,
        posterCachePath: cachePath,
        tmdbGenres: merged.genres,
      ),
    );
    if (matchedCount == 0) {
      throw StateError('网盘系列已变化，请刷新媒体库后重试');
    }
    return merged;
  }

  Future<TmdbScrapeSubject> _subjectFor(
    String sourceId,
    String seriesName,
    TmdbScrapeOptions options,
  ) async {
    final items = sourceId.isEmpty
        ? const <CloudMediaIndexItem>[]
        : await _repository.getBySource(sourceId);
    return _subjectFromItems(sourceId, seriesName, items, options);
  }

  TmdbScrapeSubject _subjectFromItems(
    String sourceId,
    String seriesName,
    List<CloudMediaIndexItem> allItems,
    TmdbScrapeOptions options,
  ) {
    final normalized = seriesName.trim().toLowerCase();
    final items = allItems
        .where((item) => item.seriesName.trim().toLowerCase() == normalized)
        .toList(growable: false);
    final candidates = <String>[seriesName.trim()];
    for (final item in items) {
      for (final value in <String>[
        item.seriesName,
        item.name,
        item.displayName
      ]) {
        final text = value.trim();
        if (text.isNotEmpty &&
            !candidates.any(
                (current) => current.toLowerCase() == text.toLowerCase())) {
          candidates.add(text);
        }
      }
    }
    final seasons = items
        .map((item) => item.seasonNumber)
        .whereType<int>()
        .where((number) => number > 0)
        .toSet();
    final episodes = items
        .map((item) => item.episodeNumber)
        .whereType<int>()
        .where((number) => number > 0)
        .toSet();
    final evidence = seasons.isNotEmpty || episodes.isNotEmpty
        ? TmdbMediaEvidence.tv
        : options.mediaTypeMode == TmdbMediaTypeMode.movie
            ? TmdbMediaEvidence.movie
            : TmdbMediaEvidence.unknown;
    return TmdbScrapeSubject(
      stableKey: '$sourceId|${seriesName.trim().toLowerCase()}',
      titleCandidates: candidates,
      seasonNumbers: seasons,
      episodeNumbers: episodes,
      mediaEvidence: evidence,
    );
  }

  static String _imageUrl(String value) => value.startsWith('http')
      ? value
      : 'https://image.tmdb.org/t/p/w500$value';

  static TmdbMetadata? _metadataFromItem(CloudMediaIndexItem item) {
    final id = item.tmdbId;
    final title = item.tmdbTitle?.trim();
    if (id == null || title == null || title.isEmpty) return null;
    final mediaType = item.mediaType == CloudMediaType.movie ||
            item.mediaType == CloudMediaType.special
        ? TmdbMediaType.movie
        : TmdbMediaType.tv;
    return TmdbMetadata(
      id: id,
      mediaType: mediaType,
      title: title,
      originalTitle: item.tmdbOriginalTitle,
      overview: item.tmdbOverview,
      rating: item.tmdbRating,
      posterUrl: item.tmdbPosterUrl,
      backdropUrl: item.tmdbBackdropUrl,
      genres: item.tmdbGenres,
      language: 'zh-CN',
      matchedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      matchConfidence: 1,
    );
  }
}
