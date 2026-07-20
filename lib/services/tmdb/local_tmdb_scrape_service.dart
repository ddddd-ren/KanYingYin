import 'package:path/path.dart' as p;
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scraper.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/poster_service.dart';

typedef TmdbPosterDownloader = Future<String?> Function(
  String posterUrl,
  String savePath,
);

class LocalTmdbScrapeService {
  final ILocalMediaIndexRepository indexRepository;
  final ITmdbMetadataRepository metadataRepository;
  final ITmdbClient Function(String apiKey) clientFactory;
  final TmdbPosterDownloader posterDownloader;

  LocalTmdbScrapeService({
    required this.indexRepository,
    required this.metadataRepository,
    required this.clientFactory,
    TmdbPosterDownloader? posterDownloader,
  }) : posterDownloader = posterDownloader ??
            ((url, path) =>
                PosterService().downloadPosterTo(url, path, overwrite: true));

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
    if (!force &&
        seriesItems.every((item) =>
            item.scrapeStatus == TmdbScrapeStatus.matched &&
            item.tmdb != null)) {
      final failures = await _downloadPosters(seriesItems);
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.matched,
        metadata: seriesItems.first.tmdb,
        posterDownloadFailures: failures,
      );
    }

    final effectiveType = mediaType ?? _resolveType(options, seriesItems);
    final scraper = TmdbScraper(
      client: clientFactory(apiKey.trim()),
      repository: metadataRepository,
    );
    final result = await scraper.scrape(
      mediaKey: normalizedKey,
      title: seriesName,
      year: _extractYear(seriesName),
      mediaType: effectiveType,
      language: options.language,
      minimumScore: options.minimumScore,
      minimumLead: options.minimumLead,
    );

    for (final item in seriesItems) {
      final metadata = result.metadata == null
          ? item.tmdb
          : _mergeMetadata(item, result.metadata!, options);
      await indexRepository.updateItem(item.copyWith(
        tmdb: metadata,
        scrapeStatus: result.status,
      ));
    }
    final failures = result.status == TmdbScrapeStatus.matched
        ? await _downloadPosters(seriesItems)
        : 0;
    return TmdbScrapeResult(
      status: result.status,
      metadata: result.metadata,
      candidates: result.candidates,
      error: result.error,
      posterDownloadFailures: failures,
    );
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

    final details = await clientFactory(apiKey.trim()).details(
      candidate.id,
      candidate.mediaType,
      language: options.language,
    );
    await metadataRepository.save(normalizedKey, details);
    for (final item in seriesItems) {
      await indexRepository.updateItem(item.copyWith(
        tmdb: _mergeMetadata(item, details, options),
        scrapeStatus: TmdbScrapeStatus.matched,
      ));
    }
    final failures = await _downloadPosters(seriesItems);
    return TmdbScrapeResult(
      status: TmdbScrapeStatus.matched,
      metadata: details,
      posterDownloadFailures: failures,
    );
  }

  Future<int> _downloadPosters(List<LocalMediaIndexItem> seriesItems) async {
    final itemsByDirectory = <String, List<LocalMediaIndexItem>>{};
    for (final original in seriesItems) {
      final item = indexRepository.getByPath(original.path) ?? original;
      if (_posterPathFor(item) == null) continue;
      (itemsByDirectory[p.dirname(item.path)] ??= []).add(item);
    }
    var failures = 0;
    for (final entry in itemsByDirectory.entries) {
      final posterPath = _posterPathFor(entry.value.first)!;
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

  String? _posterPathFor(LocalMediaIndexItem item) {
    final metadata = item.tmdb;
    if (metadata == null) return null;
    final seasonNumber = item.seasonNumber;
    if (metadata.mediaType == TmdbMediaType.tv && seasonNumber != null) {
      for (final season in metadata.seasons) {
        final poster = season.posterUrl?.trim() ?? '';
        if (season.seasonNumber == seasonNumber && poster.isNotEmpty) {
          return poster;
        }
      }
    }
    final fallback = metadata.posterUrl?.trim() ?? '';
    return fallback.isEmpty ? null : fallback;
  }

  TmdbMediaType _inferType(List<LocalMediaIndexItem> items) {
    return items.any((item) => item.episodeNumber != null)
        ? TmdbMediaType.tv
        : TmdbMediaType.movie;
  }

  TmdbMediaType _resolveType(
    TmdbScrapeOptions options,
    List<LocalMediaIndexItem> items,
  ) {
    return switch (options.mediaTypeMode) {
      TmdbMediaTypeMode.movie => TmdbMediaType.movie,
      TmdbMediaTypeMode.tv => TmdbMediaType.tv,
      TmdbMediaTypeMode.auto => _inferType(items),
    };
  }

  int? _extractYear(String value) {
    final match = RegExp(r'(?<!\d)(19|20)\d{2}(?!\d)').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  TmdbMetadata _mergeMetadata(
    LocalMediaIndexItem item,
    TmdbMetadata fetched,
    TmdbScrapeOptions options,
  ) {
    final existing = item.tmdb;
    final preserveTitle =
        existing != null && (item.titleLocked || !options.overwriteTitle);
    final preserveOverview =
        existing != null && (item.overviewLocked || !options.overwriteOverview);
    final preservePoster =
        existing != null && (item.posterLocked || !options.overwritePoster);
    return TmdbMetadata(
      id: fetched.id,
      mediaType: fetched.mediaType,
      title: preserveTitle ? existing.title : fetched.title,
      originalTitle:
          preserveTitle ? existing.originalTitle : fetched.originalTitle,
      overview: preserveOverview ? existing.overview : fetched.overview,
      releaseDate: fetched.releaseDate,
      rating: fetched.rating,
      posterUrl: options.fetchPoster
          ? (preservePoster ? existing.posterUrl : fetched.posterUrl)
          : existing?.posterUrl,
      backdropUrl:
          options.fetchBackdrop ? fetched.backdropUrl : existing?.backdropUrl,
      language: fetched.language,
      matchedAt: fetched.matchedAt,
      matchConfidence: fetched.matchConfidence,
      seasons: fetched.seasons,
    );
  }
}
