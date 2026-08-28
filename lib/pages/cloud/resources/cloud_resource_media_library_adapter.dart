import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

class CloudResourceMediaLibraryAdapter {
  const CloudResourceMediaLibraryAdapter();

  List<MediaLibrarySeries> convert({
    required CloudSource source,
    required CloudResourceCollection collection,
    required Iterable<CloudMediaIndexItem> indexedItems,
  }) {
    final indexedByIdentity = <String, CloudMediaIndexItem>{
      for (final item in indexedItems)
        if (item.sourceId == source.id)
          _identity(item.remoteId, item.remotePath): item,
    };
    return collection.groups
        .map((group) => _series(source, group, indexedByIdentity))
        .toList(growable: false);
  }

  MediaLibrarySeries _series(
    CloudSource source,
    CloudResourceMediaGroup group,
    Map<String, CloudMediaIndexItem> indexedByIdentity,
  ) {
    final indexed = group.videos
        .map(
          (video) => indexedByIdentity[_identity(video.id, video.remotePath)],
        )
        .whereType<CloudMediaIndexItem>()
        .toList(growable: false);
    final firstItem = indexed.firstOrNull;
    final metadata = group.workRecord?.metadata;
    final legacy = group.record;
    final genres = _genres(
      metadata?.genres,
      legacy?.genres,
      indexed.expand((item) => item.tmdbGenres),
    );
    final posterUrl = group.seasonMetadata?.posterUrl ??
        metadata?.posterUrl ??
        legacy?.posterUrl ??
        firstItem?.tmdbPosterUrl;
    final posterCachePath = group.seasonMetadata?.posterCachePath ??
        group.workRecord?.posterCachePath ??
        legacy?.posterCachePath ??
        firstItem?.posterCachePath;

    return MediaLibrarySeries(
      key: group.stableKey,
      seriesKey: group.workKey,
      title: group.displayName,
      sourceKind: MediaSourceKind.cloud,
      sourceId: source.id,
      sourceName: source.name,
      isAvailable: source.enabled,
      mediaType: metadata?.mediaType ??
          legacy?.mediaType ??
          (group.isSeries ? TmdbMediaType.tv : TmdbMediaType.movie),
      genres: genres,
      tmdbTitle: metadata?.title ?? legacy?.title ?? firstItem?.tmdbTitle,
      tmdbOverview:
          metadata?.overview ?? legacy?.overview ?? firstItem?.tmdbOverview,
      tmdbRating: metadata?.rating ?? legacy?.rating ?? firstItem?.tmdbRating,
      tmdbReleaseDate: metadata?.releaseDate ?? legacy?.releaseDate,
      tmdbPosterUrl: posterUrl,
      posterCachePath: posterCachePath,
      episodes: group.videos
          .map(
            (video) => _episode(
              source,
              video,
              indexedByIdentity[_identity(video.id, video.remotePath)],
              metadata: metadata,
              legacy: legacy,
              posterUrl: posterUrl,
              posterCachePath: posterCachePath,
            ),
          )
          .toList(growable: false),
    );
  }

  MediaLibraryEpisode _episode(
    CloudSource source,
    CloudFileEntry video,
    CloudMediaIndexItem? item, {
    required TmdbMetadata? metadata,
    required CloudResourceTmdbRecord? legacy,
    required String? posterUrl,
    required String? posterCachePath,
  }) {
    final remoteId = video.id.trim().isEmpty ? video.remotePath : video.id;
    return MediaLibraryEpisode.cloud(
      stableId: remoteId,
      name: video.name,
      sourceId: source.id,
      sourceName: source.name,
      isAvailable: source.enabled,
      remoteId: remoteId,
      remotePath: video.remotePath,
      tmdbTitle: metadata?.title ?? legacy?.title ?? item?.tmdbTitle,
      tmdbOriginalTitle: metadata?.originalTitle ??
          legacy?.originalTitle ??
          item?.tmdbOriginalTitle,
      tmdbOverview:
          metadata?.overview ?? legacy?.overview ?? item?.tmdbOverview,
      tmdbRating: metadata?.rating ?? legacy?.rating ?? item?.tmdbRating,
      tmdbPosterUrl: posterUrl ?? item?.tmdbPosterUrl,
      tmdbBackdropUrl:
          metadata?.backdropUrl ?? legacy?.backdropUrl ?? item?.tmdbBackdropUrl,
      posterCachePath: posterCachePath ?? item?.posterCachePath,
      size: video.size,
      modifiedAt: video.modifiedAt,
      seasonNumber: video.seasonNumber ?? item?.seasonNumber,
      episodeNumber: video.episodeNumber ?? item?.episodeNumber,
      subtitleRemotePaths: item?.subtitlePaths ?? const <String>[],
      subtitleRemoteRefs: item?.subtitleRefs ?? const <CloudRemoteRef>[],
      releaseTags: video.releaseTags,
    );
  }

  List<String> _genres(
    List<String>? workGenres,
    List<String>? legacyGenres,
    Iterable<String> indexedGenres,
  ) {
    final preferred = workGenres?.isNotEmpty == true
        ? workGenres!
        : legacyGenres?.isNotEmpty == true
            ? legacyGenres!
            : indexedGenres;
    return preferred
        .map((genre) => genre.trim())
        .where((genre) => genre.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _identity(String remoteId, String remotePath) {
    final id = remoteId.trim();
    if (id.isNotEmpty) return 'id:$id';
    var path = remotePath.trim().replaceAll('\\', '/');
    path = path.replaceAll(RegExp(r'/+'), '/');
    if (!path.startsWith('/')) path = '/$path';
    return 'path:${path.toLowerCase()}';
  }
}
