import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_image_metadata.dart';
import 'package:kanyingyin/modules/local/tmdb_image_override.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';
import 'package:kanyingyin/services/tmdb/tmdb_image_selection_logger.dart';
import 'package:kanyingyin/services/tmdb/tmdb_poster_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

class LocalTmdbImageSelectionService {
  LocalTmdbImageSelectionService({
    required ILocalMediaIndexRepository indexRepository,
    required ITmdbMetadataRepository metadataRepository,
    required ITmdbClient client,
  })  : _indexRepository = indexRepository,
        _metadataRepository = metadataRepository,
        _client = client;

  final ILocalMediaIndexRepository _indexRepository;
  final ITmdbMetadataRepository _metadataRepository;
  final ITmdbClient _client;

  Future<TmdbImageSet> imagesForSeries(
    String seriesName, {
    TmdbImageKind? kind,
    int? seasonNumber,
    int? episodeNumber,
    String language = 'zh-CN',
  }) async {
    final startedAt = DateTime.now();
    final target = _targetFor(seasonNumber, episodeNumber);
    final logKind = kind ?? TmdbImageKind.poster;
    try {
      final metadata = _metadataForSeries(seriesName);
      if (metadata == null) throw StateError('该本地剧集尚未完成 TMDB 刮削');
      TmdbImageSelectionLogger.write(
        scope: 'local',
        phase: 'load_start',
        target: target,
        kind: logKind,
        identity: seriesName,
        tmdbId: metadata.id,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
      final images = await _imageCapabilities.images(
        metadata.id,
        metadata.mediaType,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        language: language,
      );
      final count = switch (logKind) {
        TmdbImageKind.poster => images.posters.length,
        TmdbImageKind.backdrop => images.backdrops.length,
        TmdbImageKind.still => images.stills.length,
      };
      TmdbImageSelectionLogger.write(
        scope: 'local',
        phase: 'load_success',
        target: target,
        kind: logKind,
        identity: seriesName,
        tmdbId: metadata.id,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        candidateCount: count,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        result: 'success',
      );
      return images;
    } catch (error, stackTrace) {
      TmdbImageSelectionLogger.write(
        scope: 'local',
        phase: 'load_failed',
        target: target,
        kind: logKind,
        identity: seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        result: 'error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> selectSeriesImage({
    required String seriesName,
    required TmdbImageKind kind,
    required String filePath,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final startedAt = DateTime.now();
    final target = _targetFor(seasonNumber, episodeNumber);
    final normalized = normalizeTmdbImagePath(filePath);
    if (normalized == null) {
      TmdbImageSelectionLogger.write(
        scope: 'local',
        phase: 'save_failed',
        target: target,
        kind: kind,
        identity: seriesName,
        selectedPath: filePath,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        result: 'error',
        error: ArgumentError.value(filePath, 'filePath'),
      );
      throw ArgumentError.value(filePath, 'filePath');
    }
    try {
      final matching = _matchingItems(seriesName);
      if (matching.isEmpty) throw StateError('本地剧集不存在');
      final metadata = matching.map((item) => item.tmdb).nonNulls.firstOrNull;
      if (metadata == null) throw StateError('该本地剧集尚未完成 TMDB 刮削');
      final previousPath = _overridePath(
        metadata.imageOverride,
        kind: kind,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
      TmdbImageSelectionLogger.write(
        scope: 'local',
        phase: 'save_start',
        target: target,
        kind: kind,
        identity: seriesName,
        tmdbId: metadata.id,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        previousPath: previousPath,
        selectedPath: normalized,
      );
      final override = _updateOverride(
        metadata.imageOverride,
        kind: kind,
        filePath: normalized,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
      final updated = metadata.copyWith(imageOverride: override);
      final updates = <String, LocalMediaIndexItem>{
        for (final item in matching) item.id: item.copyWith(tmdb: updated),
      };
      await _indexRepository.updateItems(updates);
      final key = seriesName.trim().toLowerCase();
      await _metadataRepository.save(key, updated);
      final readBack = _metadataRepository.get(key);
      final indexItems = _matchingItems(seriesName);
      final indexSynced = indexItems.isNotEmpty &&
          indexItems.every((item) => item.tmdb?.imageOverride == override);
      TmdbImageSelectionLogger.write(
        scope: 'local',
        phase: 'save_success',
        target: target,
        kind: kind,
        identity: seriesName,
        tmdbId: metadata.id,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        previousPath: previousPath,
        selectedPath: normalized,
        savedPath: normalized,
        repositoryReadBack: _overridePath(
          readBack?.imageOverride,
          kind: kind,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        ),
        displayPath: _displayPath(
          updated,
          kind: kind,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        ),
        indexSynced: indexSynced,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        result: 'success',
      );
    } catch (error, stackTrace) {
      TmdbImageSelectionLogger.write(
        scope: 'local',
        phase: 'save_failed',
        target: target,
        kind: kind,
        identity: seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        selectedPath: normalized,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        result: 'error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> clearSeriesImage({
    required String seriesName,
    required TmdbImageKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final startedAt = DateTime.now();
    final target = _targetFor(seasonNumber, episodeNumber);
    try {
      final matching = _matchingItems(seriesName);
      final metadata = matching.map((item) => item.tmdb).nonNulls.firstOrNull;
      if (matching.isEmpty || metadata == null) {
        throw StateError('该本地剧集尚未完成 TMDB 刮削');
      }
      final previousPath = _overridePath(
        metadata.imageOverride,
        kind: kind,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
      TmdbImageSelectionLogger.write(
        scope: 'local',
        phase: 'clear_start',
        target: target,
        kind: kind,
        identity: seriesName,
        tmdbId: metadata.id,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        previousPath: previousPath,
      );
      final override = switch (kind) {
        TmdbImageKind.poster when seasonNumber != null =>
          metadata.imageOverride.clearSeasonPoster(seasonNumber),
        TmdbImageKind.poster => metadata.imageOverride.clearPoster(),
        TmdbImageKind.backdrop => metadata.imageOverride.clearBackdrop(),
        TmdbImageKind.still
            when seasonNumber != null && episodeNumber != null =>
          metadata.imageOverride.clearEpisodeStill(seasonNumber, episodeNumber),
        TmdbImageKind.still => throw ArgumentError('清除单集剧照时必须提供季度号和集数'),
      };
      final updated = metadata.copyWith(imageOverride: override);
      await _indexRepository.updateItems(
        <String, LocalMediaIndexItem>{
          for (final item in matching) item.id: item.copyWith(tmdb: updated),
        },
      );
      final key = seriesName.trim().toLowerCase();
      await _metadataRepository.save(key, updated);
      final readBack = _metadataRepository.get(key);
      final indexItems = _matchingItems(seriesName);
      final indexSynced = indexItems.isNotEmpty &&
          indexItems.every((item) => item.tmdb?.imageOverride == override);
      TmdbImageSelectionLogger.write(
        scope: 'local',
        phase: 'clear_success',
        target: target,
        kind: kind,
        identity: seriesName,
        tmdbId: metadata.id,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        previousPath: previousPath,
        repositoryReadBack: _overridePath(
          readBack?.imageOverride,
          kind: kind,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        ),
        displayPath: _displayPath(
          updated,
          kind: kind,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        ),
        indexSynced: indexSynced,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        result: 'success',
      );
    } catch (error, stackTrace) {
      TmdbImageSelectionLogger.write(
        scope: 'local',
        phase: 'clear_failed',
        target: target,
        kind: kind,
        identity: seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        result: 'error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  ITmdbImageCapabilities get _imageCapabilities {
    final client = _client;
    if (client is! ITmdbImageCapabilities) {
      throw StateError('当前 TMDB 客户端不支持图片选择');
    }
    return client as ITmdbImageCapabilities;
  }

  TmdbMetadata? _metadataForSeries(String seriesName) {
    final key = seriesName.trim().toLowerCase();
    return _indexRepository
        .getAll()
        .where((item) => item.seriesName.trim().toLowerCase() == key)
        .map((item) => item.tmdb)
        .nonNulls
        .firstOrNull;
  }

  List<LocalMediaIndexItem> _matchingItems(String seriesName) {
    final key = seriesName.trim().toLowerCase();
    return _indexRepository
        .getAll()
        .where((item) => item.seriesName.trim().toLowerCase() == key)
        .toList(growable: false);
  }

  String _targetFor(int? seasonNumber, int? episodeNumber) {
    if (episodeNumber != null) return 'episode';
    if (seasonNumber != null) return 'season';
    return 'series';
  }

  String? _overridePath(
    TmdbImageOverride? override, {
    required TmdbImageKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    if (override == null) return null;
    return switch (kind) {
      TmdbImageKind.poster when seasonNumber != null =>
        override.seasonPosters[seasonNumber],
      TmdbImageKind.poster => override.poster,
      TmdbImageKind.backdrop => override.backdrop,
      TmdbImageKind.still when seasonNumber != null && episodeNumber != null =>
        override.episodeStills['$seasonNumber:$episodeNumber'],
      TmdbImageKind.still => null,
    };
  }

  String? _displayPath(
    TmdbMetadata metadata, {
    required TmdbImageKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    if (kind == TmdbImageKind.poster) {
      return const TmdbPosterPolicy().select(
        metadata,
        seasonNumber: seasonNumber,
        options: const TmdbScrapeOptions.defaults(),
      );
    }
    return _overridePath(
      metadata.imageOverride,
      kind: kind,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
  }

  TmdbImageOverride _updateOverride(
    TmdbImageOverride current, {
    required TmdbImageKind kind,
    required String filePath,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    switch (kind) {
      case TmdbImageKind.poster:
        if (seasonNumber != null) {
          return current.copyWith(
            seasonPosters: <int, String>{
              ...current.seasonPosters,
              seasonNumber: filePath,
            },
          );
        }
        return current.copyWith(poster: filePath);
      case TmdbImageKind.backdrop:
        return current.copyWith(backdrop: filePath);
      case TmdbImageKind.still:
        if (seasonNumber == null || episodeNumber == null) {
          throw ArgumentError('选择单集剧照时必须提供季度号和集数');
        }
        return current.copyWith(
          episodeStills: <String, String>{
            ...current.episodeStills,
            '$seasonNumber:$episodeNumber': filePath,
          },
        );
    }
  }
}
