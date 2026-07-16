import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';

enum MediaSourceKind { local, cloud }

class MediaLibraryEpisode {
  const MediaLibraryEpisode._({
    required this.stableId,
    required this.name,
    required this.sourceKind,
    required this.sourceId,
    required this.sourceName,
    required this.isAvailable,
    this.localItem,
    this.remotePath,
    this.tmdbTitle,
    this.tmdbOriginalTitle,
    this.tmdbOverview,
    this.tmdbRating,
    this.tmdbPosterUrl,
    this.tmdbBackdropUrl,
    this.posterCachePath,
    this.subtitleRemotePaths = const <String>[],
  });

  factory MediaLibraryEpisode.local({
    required String stableId,
    required String name,
    required LocalMediaIndexItem localItem,
  }) {
    if (stableId.isEmpty) throw ArgumentError.value(stableId, 'stableId');
    return MediaLibraryEpisode._(
      stableId: stableId,
      name: name,
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      isAvailable: true,
      localItem: localItem,
    );
  }

  factory MediaLibraryEpisode.cloud({
    required String stableId,
    required String name,
    required String sourceId,
    required String sourceName,
    required bool isAvailable,
    required String remotePath,
    String? tmdbTitle,
    String? tmdbOriginalTitle,
    String? tmdbOverview,
    double? tmdbRating,
    String? tmdbPosterUrl,
    String? tmdbBackdropUrl,
    String? posterCachePath,
    List<String> subtitleRemotePaths = const <String>[],
  }) {
    if (sourceId.isEmpty || remotePath.isEmpty || stableId.isEmpty) {
      throw ArgumentError('云媒体必须提供来源、稳定标识和远程路径');
    }
    return MediaLibraryEpisode._(
      stableId: '$sourceId|$stableId',
      name: name,
      sourceKind: MediaSourceKind.cloud,
      sourceId: sourceId,
      sourceName: sourceName,
      isAvailable: isAvailable,
      remotePath: remotePath,
      tmdbTitle: tmdbTitle,
      tmdbOriginalTitle: tmdbOriginalTitle,
      tmdbOverview: tmdbOverview,
      tmdbRating: tmdbRating,
      tmdbPosterUrl: tmdbPosterUrl,
      tmdbBackdropUrl: tmdbBackdropUrl,
      posterCachePath: posterCachePath,
      subtitleRemotePaths: subtitleRemotePaths,
    );
  }

  final String stableId;
  final String name;
  final MediaSourceKind sourceKind;
  final String sourceId;
  final String sourceName;
  final bool isAvailable;
  final LocalMediaIndexItem? localItem;
  final String? remotePath;
  final String? tmdbTitle;
  final String? tmdbOriginalTitle;
  final String? tmdbOverview;
  final double? tmdbRating;
  final String? tmdbPosterUrl;
  final String? tmdbBackdropUrl;
  final String? posterCachePath;
  final List<String> subtitleRemotePaths;
}

class MediaLibrarySeries {
  const MediaLibrarySeries({
    required this.key,
    required this.seriesKey,
    required this.title,
    required this.sourceKind,
    required this.sourceId,
    required this.sourceName,
    required this.isAvailable,
    required this.episodes,
    this.tmdbTitle,
    this.tmdbOverview,
    this.tmdbRating,
    this.tmdbPosterUrl,
    this.posterCachePath,
  });

  final String key;
  final String seriesKey;
  final String title;
  final MediaSourceKind sourceKind;
  final String sourceId;
  final String sourceName;
  final bool isAvailable;
  final List<MediaLibraryEpisode> episodes;
  final String? tmdbTitle;
  final String? tmdbOverview;
  final double? tmdbRating;
  final String? tmdbPosterUrl;
  final String? posterCachePath;
}

class MediaLibrarySourceFilter {
  const MediaLibrarySourceFilter(this.id, this.label, this.kind);
  final String id;
  final String label;
  final MediaSourceKind? kind;
}

class CloudMediaLibrary {
  const CloudMediaLibrary({required this.series, required this.filters});
  final List<MediaLibrarySeries> series;
  final List<MediaLibrarySourceFilter> filters;

  List<MediaLibrarySeries> filterBySource(String sourceId) => sourceId == 'all'
      ? List<MediaLibrarySeries>.unmodifiable(series)
      : series
          .where((item) => item.sourceId == sourceId)
          .toList(growable: false);
}

class CloudMediaLibraryAggregator {
  const CloudMediaLibraryAggregator();

  CloudMediaLibrary build({
    required Iterable<LocalMediaIndexItem> localItems,
    required Iterable<CloudMediaIndexItem> cloudItems,
    required Iterable<CloudSource> cloudSources,
  }) {
    final sources = {for (final source in cloudSources) source.id: source};
    final result = <MediaLibrarySeries>[];
    for (final local
        in const LocalMediaLibraryBuilder().buildSeries(localItems)) {
      result.add(MediaLibrarySeries(
        key: 'local|${local.key}',
        seriesKey: local.key,
        title: local.title,
        sourceKind: MediaSourceKind.local,
        sourceId: 'local',
        sourceName: '本地',
        isAvailable: true,
        episodes: local.episodes
            .map((item) => MediaLibraryEpisode.local(
                  stableId: item.id,
                  name: item.name,
                  localItem: item,
                ))
            .toList(growable: false),
      ));
    }

    final groups = <String, List<CloudMediaIndexItem>>{};
    for (final item in cloudItems) {
      groups
          .putIfAbsent(
              '${item.sourceId}|${item.seriesName.trim().toLowerCase()}|${_groupVariant(item)}',
              () => [])
          .add(item);
    }
    for (final entry in groups.entries) {
      final items = entry.value..sort(_compareCloudEpisodes);
      final source = sources[items.first.sourceId];
      final metadata = _metadataItem(items);
      final title = _cloudGroupTitle(items.first, metadata?.tmdbTitle);
      result.add(MediaLibrarySeries(
        key: entry.key,
        seriesKey: items.first.seriesName.trim(),
        title: title,
        sourceKind: MediaSourceKind.cloud,
        sourceId: items.first.sourceId,
        sourceName: source?.name ?? items.first.sourceId,
        isAvailable: source?.enabled == true,
        tmdbTitle: metadata?.tmdbTitle,
        tmdbOverview: metadata?.tmdbOverview,
        tmdbRating: metadata?.tmdbRating,
        tmdbPosterUrl: metadata?.tmdbPosterUrl,
        posterCachePath: metadata?.posterCachePath,
        episodes: items
            .map((item) => MediaLibraryEpisode.cloud(
                  stableId: item.remoteId,
                  name: _cloudEpisodeTitle(item),
                  sourceId: item.sourceId,
                  sourceName: source?.name ?? item.sourceId,
                  isAvailable: source?.enabled == true,
                  remotePath: item.remotePath,
                  tmdbTitle: item.tmdbTitle,
                  tmdbOriginalTitle: item.tmdbOriginalTitle,
                  tmdbOverview: item.tmdbOverview,
                  tmdbRating: item.tmdbRating,
                  tmdbPosterUrl: item.tmdbPosterUrl,
                  tmdbBackdropUrl: item.tmdbBackdropUrl,
                  posterCachePath: item.posterCachePath,
                  subtitleRemotePaths: item.subtitlePaths,
                ))
            .toList(growable: false),
      ));
    }
    result.sort((a, b) {
      final source = a.sourceId.compareTo(b.sourceId);
      return source != 0 ? source : a.title.compareTo(b.title);
    });
    final filters = <MediaLibrarySourceFilter>[
      const MediaLibrarySourceFilter('all', '全部', null),
      const MediaLibrarySourceFilter('local', '本地', MediaSourceKind.local),
      ...sources.values.where((source) => source.enabled).map((source) =>
          MediaLibrarySourceFilter(
              source.id, source.name, MediaSourceKind.cloud))
    ];
    return CloudMediaLibrary(series: result, filters: filters);
  }

  static CloudMediaIndexItem? _metadataItem(
      List<CloudMediaIndexItem> items) {
    for (final item in items) {
      if (item.tmdbTitle?.trim().isNotEmpty == true ||
          item.tmdbOverview?.trim().isNotEmpty == true ||
          item.tmdbPosterUrl?.trim().isNotEmpty == true ||
          item.posterCachePath?.trim().isNotEmpty == true ||
          item.tmdbRating != null) {
        return item;
      }
    }
    return null;
  }

  static String _cloudGroupTitle(
      CloudMediaIndexItem item, String? tmdbTitle) {
    final scrapedName = tmdbTitle?.trim() ?? '';
    final name = scrapedName.isNotEmpty
        ? scrapedName
        : item.seriesName.trim().isEmpty
            ? item.name
            : item.seriesName.trim();
    if (item.mediaType == CloudMediaType.special) return '$name 特别篇';
    final season = item.seasonNumber;
    if (season != null && season > 0) {
      return '$name S${season.toString().padLeft(2, '0')}';
    }
    return name;
  }

  static String _cloudEpisodeTitle(CloudMediaIndexItem item) {
    final title = item.tmdbTitle?.trim() ?? '';
    if (title.isEmpty) return item.name;
    final season = item.seasonNumber;
    final episode = item.episodeNumber;
    if (episode == null || episode <= 0) return title;
    final episodeLabel = episode.toString().padLeft(2, '0');
    if (season == null || season <= 0) return '$title E$episodeLabel';
    return '$title S${season.toString().padLeft(2, '0')}E$episodeLabel';
  }

  static String _groupVariant(CloudMediaIndexItem item) =>
      item.mediaType == CloudMediaType.special
          ? 'special'
          : 'season:${item.seasonNumber ?? 0}';

  static int _compareCloudEpisodes(
      CloudMediaIndexItem a, CloudMediaIndexItem b) {
    final episode = (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
    return episode != 0 ? episode : a.name.compareTo(b.name);
  }
}
