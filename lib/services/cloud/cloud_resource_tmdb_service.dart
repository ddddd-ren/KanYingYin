import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

class CloudResourceTmdbTarget {
  const CloudResourceTmdbTarget({
    required this.sourceId,
    required this.remote,
    required this.displayName,
    required this.resourceKind,
  });

  final String sourceId;
  final CloudRemoteRef remote;
  final String displayName;
  final CloudResourceKind resourceKind;

  String get stableKey => cloudResourceTmdbKey(
        sourceId: sourceId,
        remoteId: remote.id,
        remotePath: remote.path,
      );
}

class CloudResourceTmdbOutcome {
  const CloudResourceTmdbOutcome({required this.candidates, this.selected});

  final List<TmdbMetadata> candidates;
  final CloudResourceTmdbRecord? selected;
}

class CloudResourceTmdbService {
  CloudResourceTmdbService({
    required CloudResourceTmdbRepository repository,
    required CloudMediaIndexRepository indexRepository,
    required ITmdbClient client,
    CloudPosterCache? posterCache,
    DateTime Function()? now,
  })  : _repository = repository,
        _indexRepository = indexRepository,
        _client = client,
        _posterCache = posterCache,
        _now = now ?? DateTime.now;

  final CloudResourceTmdbRepository _repository;
  final CloudMediaIndexRepository _indexRepository;
  final ITmdbClient _client;
  final CloudPosterCache? _posterCache;
  final DateTime Function() _now;

  Future<CloudResourceTmdbOutcome> match(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final search = await _search(target, options);
    if (search.candidates.isEmpty) {
      final record = CloudResourceTmdbRecord.unmatched(
        sourceId: target.sourceId,
        remoteId: target.remote.id,
        remotePath: target.remote.path,
        displayName: target.displayName,
        resourceKind: target.resourceKind,
        checkedAt: _now(),
      );
      await _repository.upsert(record);
      return const CloudResourceTmdbOutcome(candidates: <TmdbMetadata>[]);
    }

    final parsed = _parseQuery(search.query);
    final result = const TmdbMatcher().choose(
      queryTitle: parsed.title,
      queryYear: parsed.year,
      expectedType: search.mediaType,
      candidates: search.candidates,
      minimumScore: options.minimumScore,
      minimumLead: options.minimumLead,
    );
    if (!result.shouldAutoMatch || result.best == null) {
      return CloudResourceTmdbOutcome(candidates: search.candidates);
    }
    final selected = await select(target, result.best!, options: options);
    return CloudResourceTmdbOutcome(
      candidates: search.candidates,
      selected: selected,
    );
  }

  Future<CloudResourceTmdbOutcome> searchCandidates(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final search = await _search(target, options);
    return CloudResourceTmdbOutcome(candidates: search.candidates);
  }

  Future<CloudResourceTmdbRecord> select(
    CloudResourceTmdbTarget target,
    TmdbMetadata candidate, {
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final metadata = await _client.details(
      candidate.id,
      candidate.mediaType,
      language: options.language,
    );
    String? posterCachePath;
    if (_posterCache != null &&
        options.fetchPoster &&
        metadata.posterUrl != null) {
      final imageUrl = _imageUrl(metadata.posterUrl!);
      final resolved = await _posterCache.resolve(
        sourceId: target.sourceId,
        stableId: target.stableKey,
        url: imageUrl,
      );
      if (resolved != imageUrl) posterCachePath = resolved;
    }
    final record = CloudResourceTmdbRecord.matched(
      sourceId: target.sourceId,
      remoteId: target.remote.id,
      remotePath: target.remote.path,
      displayName: target.displayName,
      resourceKind: target.resourceKind,
      metadata: metadata,
      posterCachePath: posterCachePath,
      checkedAt: _now(),
    );
    await _repository.upsert(record);
    await _syncIndex(target, metadata, posterCachePath);
    return record;
  }

  static String queryName(String displayName, {required bool isDirectory}) {
    var value = displayName.trim();
    if (!isDirectory) {
      value = value.replaceFirst(RegExp(r'\.[^.\\/]+$'), '');
    }
    value = value
        .replaceAll(RegExp(r'【[^】]*】|\[[^\]]*\]'), ' ')
        .replaceAll(
          RegExp(
            r'\b(?:2160p|1080p|720p|4k|8k|uhd|hdr10?|bluray|web-?dl|x26[45]|h26[45])\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'全\s*\d+\s*集|全集|完结'), ' ')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return value;
  }

  Future<_SearchResult> _search(
    CloudResourceTmdbTarget target,
    TmdbScrapeOptions options,
  ) async {
    final query = queryName(
      target.displayName,
      isDirectory: target.resourceKind == CloudResourceKind.directory,
    );
    final types = switch (options.mediaTypeMode) {
      TmdbMediaTypeMode.movie => const <TmdbMediaType>[TmdbMediaType.movie],
      TmdbMediaTypeMode.tv => const <TmdbMediaType>[TmdbMediaType.tv],
      TmdbMediaTypeMode.auto =>
        target.resourceKind == CloudResourceKind.directory
            ? const <TmdbMediaType>[TmdbMediaType.tv, TmdbMediaType.movie]
            : const <TmdbMediaType>[TmdbMediaType.movie, TmdbMediaType.tv],
    };
    for (final type in types) {
      final candidates = await _client.search(
        query,
        type,
        language: options.language,
      );
      if (candidates.isNotEmpty) {
        return _SearchResult(
          query: query,
          mediaType: type,
          candidates: candidates,
        );
      }
    }
    return _SearchResult(
      query: query,
      mediaType: types.first,
      candidates: const <TmdbMetadata>[],
    );
  }

  Future<void> _syncIndex(
    CloudResourceTmdbTarget target,
    TmdbMetadata metadata,
    String? posterCachePath,
  ) async {
    final targetPath = _normalizePath(target.remote.path);
    await _indexRepository.updateMatching(
      target.sourceId,
      (item) {
        final itemPath = _normalizePath(item.remotePath);
        return target.resourceKind == CloudResourceKind.directory
            ? itemPath.startsWith(targetPath == '/' ? '/' : '$targetPath/')
            : itemPath == targetPath;
      },
      (item) => _replaceMetadata(item, metadata, posterCachePath),
    );
  }

  static CloudMediaIndexItem _replaceMetadata(
    CloudMediaIndexItem item,
    TmdbMetadata metadata,
    String? posterCachePath,
  ) {
    return item.replaceTmdb(
      tmdbId: metadata.id,
      tmdbTitle: metadata.title,
      tmdbOriginalTitle: metadata.originalTitle,
      tmdbOverview: metadata.overview,
      tmdbRating: metadata.rating,
      tmdbPosterUrl: metadata.posterUrl,
      tmdbBackdropUrl: metadata.backdropUrl,
      posterCachePath: posterCachePath,
    );
  }

  static _ParsedQuery _parseQuery(String query) {
    final match = RegExp(r'(?:^|\s)[(（](\d{4})[)）](?:\s|$)').firstMatch(query);
    final title = query.replaceAll(RegExp(r'\s*[(（]\d{4}[)）]\s*'), ' ').trim();
    return _ParsedQuery(
      title: title,
      year: match == null ? null : int.tryParse(match.group(1)!),
    );
  }

  static String _normalizePath(String value) {
    var path = value.trim().replaceAll('\\', '/');
    path = path.replaceAll(RegExp(r'/+'), '/');
    if (path.isEmpty) return '/';
    if (!path.startsWith('/')) path = '/$path';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  static String _imageUrl(String value) => value.startsWith('http')
      ? value
      : 'https://image.tmdb.org/t/p/w500$value';
}

class _SearchResult {
  const _SearchResult({
    required this.query,
    required this.mediaType,
    required this.candidates,
  });

  final String query;
  final TmdbMediaType mediaType;
  final List<TmdbMetadata> candidates;
}

class _ParsedQuery {
  const _ParsedQuery({required this.title, required this.year});

  final String title;
  final int? year;
}
