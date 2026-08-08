import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';

typedef TmdbClientFactory = ITmdbClient Function(String apiKey);

class LibraryGenreBackfillResult {
  const LibraryGenreBackfillResult({
    required this.updatedWorks,
    required this.failedWorks,
  });

  final int updatedWorks;
  final int failedWorks;
}

class LibraryGenreBackfillService {
  const LibraryGenreBackfillService({
    required ILocalMediaIndexRepository localRepository,
    required CloudMediaIndexRepository cloudRepository,
    required CloudWorkTmdbRepository workRepository,
    required TmdbClientFactory clientFactory,
  })  : _localRepository = localRepository,
        _cloudRepository = cloudRepository,
        _workRepository = workRepository,
        _clientFactory = clientFactory;

  final ILocalMediaIndexRepository _localRepository;
  final CloudMediaIndexRepository _cloudRepository;
  final CloudWorkTmdbRepository _workRepository;
  final TmdbClientFactory _clientFactory;

  Future<LibraryGenreBackfillResult> backfill({
    required String apiKey,
    required List<LocalMediaIndexItem> localItems,
    required List<CloudMediaIndexItem> cloudItems,
    void Function(int current, int total)? onProgress,
  }) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      return const LibraryGenreBackfillResult(
        updatedWorks: 0,
        failedWorks: 0,
      );
    }

    final targets = <(TmdbMediaType, int), _GenreTargets>{};
    for (final item in localItems) {
      final metadata = item.tmdb;
      if (metadata == null ||
          metadata.id <= 0 ||
          metadata.genres.isNotEmpty ||
          item.scrapeStatus != TmdbScrapeStatus.matched) {
        continue;
      }
      targets
          .putIfAbsent(
            (metadata.mediaType, metadata.id),
            _GenreTargets.new,
          )
          .localItems
          .add(item);
    }
    for (final item in cloudItems) {
      final key = _cloudKey(item);
      if (key == null || item.tmdbGenres.isNotEmpty) continue;
      targets
          .putIfAbsent(key, _GenreTargets.new)
          .cloudSourceIds
          .add(item.sourceId);
    }
    for (final record in await _workRepository.getAll()) {
      final metadata = record.metadata;
      if (record.status != CloudWorkTmdbStatus.matched ||
          metadata == null ||
          metadata.id <= 0 ||
          metadata.genres.isNotEmpty) {
        continue;
      }
      targets
          .putIfAbsent(
            (metadata.mediaType, metadata.id),
            _GenreTargets.new,
          )
          .workRecords
          .add(record);
    }
    if (targets.isEmpty) {
      return const LibraryGenreBackfillResult(
        updatedWorks: 0,
        failedWorks: 0,
      );
    }

    final client = _clientFactory(normalizedKey);
    final localUpdates = <String, LocalMediaIndexItem>{};
    final workUpdates = <String, CloudWorkTmdbRecord>{};
    var updatedWorks = 0;
    var failedWorks = 0;
    var current = 0;
    for (final entry in targets.entries) {
      try {
        final details = await client.details(
          entry.key.$2,
          entry.key.$1,
          language: 'zh-CN',
        );
        if (details.genres.isEmpty) continue;
        for (final item in entry.value.localItems) {
          localUpdates[item.id] = item.copyWith(
            tmdb: item.tmdb!.copyWith(genres: details.genres),
          );
        }
        for (final sourceId in entry.value.cloudSourceIds) {
          await _cloudRepository.updateMatching(
            sourceId,
            (item) => _cloudKey(item) == entry.key,
            (item) => item.copyWith(tmdbGenres: details.genres),
          );
        }
        for (final record in entry.value.workRecords) {
          workUpdates[record.workKey] = record.withMetadata(
            record.metadata!.copyWith(genres: details.genres),
          );
        }
        updatedWorks++;
      } on Object {
        failedWorks++;
      } finally {
        current++;
        onProgress?.call(current, targets.length);
      }
    }
    await _localRepository.updateItems(localUpdates);
    await _workRepository.upsertAll(workUpdates.values);
    return LibraryGenreBackfillResult(
      updatedWorks: updatedWorks,
      failedWorks: failedWorks,
    );
  }

  static (TmdbMediaType, int)? _cloudKey(CloudMediaIndexItem item) {
    final id = item.tmdbId;
    if (id == null || id <= 0) return null;
    final type = switch (item.mediaType) {
      CloudMediaType.movie => TmdbMediaType.movie,
      CloudMediaType.series ||
      CloudMediaType.episode ||
      CloudMediaType.special =>
        TmdbMediaType.tv,
      CloudMediaType.unknown => null,
    };
    return type == null ? null : (type, id);
  }
}

class _GenreTargets {
  final List<LocalMediaIndexItem> localItems = <LocalMediaIndexItem>[];
  final Set<String> cloudSourceIds = <String>{};
  final List<CloudWorkTmdbRecord> workRecords = <CloudWorkTmdbRecord>[];
}
