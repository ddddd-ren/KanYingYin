import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_image_metadata.dart';
import 'package:kanyingyin/modules/local/tmdb_image_override.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';

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
    int? seasonNumber,
    int? episodeNumber,
    String language = 'zh-CN',
  }) async {
    final metadata = _metadataForSeries(seriesName);
    if (metadata == null) throw StateError('该本地剧集尚未完成 TMDB 刮削');
    final capabilities = _imageCapabilities;
    return capabilities.images(
      metadata.id,
      metadata.mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      language: language,
    );
  }

  Future<void> selectSeriesImage({
    required String seriesName,
    required TmdbImageKind kind,
    required String filePath,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final normalized = filePath.trim();
    if (normalized.isEmpty) throw ArgumentError.value(filePath, 'filePath');
    final matching = _indexRepository
        .getAll()
        .where(
          (item) =>
              item.seriesName.trim().toLowerCase() ==
              seriesName.trim().toLowerCase(),
        )
        .toList(growable: false);
    if (matching.isEmpty) throw StateError('本地剧集不存在');
    final metadata = matching.map((item) => item.tmdb).nonNulls.firstOrNull;
    if (metadata == null) throw StateError('该本地剧集尚未完成 TMDB 刮削');

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
    await _metadataRepository.save(seriesName.trim().toLowerCase(), updated);
  }

  Future<void> clearSeriesImage({
    required String seriesName,
    required TmdbImageKind kind,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final matching = _indexRepository
        .getAll()
        .where(
          (item) =>
              item.seriesName.trim().toLowerCase() ==
              seriesName.trim().toLowerCase(),
        )
        .toList(growable: false);
    final metadata = matching.map((item) => item.tmdb).nonNulls.firstOrNull;
    if (matching.isEmpty || metadata == null) {
      throw StateError('该本地剧集尚未完成 TMDB 刮削');
    }
    final override = switch (kind) {
      TmdbImageKind.poster when seasonNumber != null =>
        metadata.imageOverride.clearSeasonPoster(seasonNumber),
      TmdbImageKind.poster => metadata.imageOverride.clearPoster(),
      TmdbImageKind.backdrop => metadata.imageOverride.clearBackdrop(),
      TmdbImageKind.still when seasonNumber != null && episodeNumber != null =>
        metadata.imageOverride.clearEpisodeStill(seasonNumber, episodeNumber),
      TmdbImageKind.still => throw ArgumentError('清除单集剧照时必须提供季度号和集数'),
    };
    final updated = metadata.copyWith(imageOverride: override);
    await _indexRepository.updateItems(
      <String, LocalMediaIndexItem>{
        for (final item in matching) item.id: item.copyWith(tmdb: updated),
      },
    );
    await _metadataRepository.save(seriesName.trim().toLowerCase(), updated);
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
