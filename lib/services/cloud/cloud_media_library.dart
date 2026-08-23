import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/services/cloud/cloud_media_grouping_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_work_grouping_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_episode_title_resolver.dart';

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
    this.remoteId,
    this.remotePath,
    this.tmdbTitle,
    this.tmdbOriginalTitle,
    this.tmdbOverview,
    this.tmdbRating,
    this.tmdbPosterUrl,
    this.tmdbBackdropUrl,
    this.posterCachePath,
    this.size,
    this.modifiedAt,
    this.seasonNumber,
    this.episodeNumber,
    this.subtitleRemotePaths = const <String>[],
    this.subtitleRemoteRefs = const <CloudRemoteRef>[],
    this.releaseTags = const MediaReleaseTags(),
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
      size: localItem.size,
      modifiedAt: localItem.modified,
      seasonNumber: localItem.seasonNumber,
      episodeNumber: localItem.episodeNumber,
    );
  }

  factory MediaLibraryEpisode.cloud({
    required String stableId,
    required String name,
    required String sourceId,
    required String sourceName,
    required bool isAvailable,
    required String remoteId,
    required String remotePath,
    String? tmdbTitle,
    String? tmdbOriginalTitle,
    String? tmdbOverview,
    double? tmdbRating,
    String? tmdbPosterUrl,
    String? tmdbBackdropUrl,
    String? posterCachePath,
    int? size,
    DateTime? modifiedAt,
    int? seasonNumber,
    int? episodeNumber,
    List<String> subtitleRemotePaths = const <String>[],
    List<CloudRemoteRef> subtitleRemoteRefs = const <CloudRemoteRef>[],
    MediaReleaseTags releaseTags = const MediaReleaseTags(),
  }) {
    if (sourceId.isEmpty ||
        remoteId.isEmpty ||
        remotePath.isEmpty ||
        stableId.isEmpty) {
      throw ArgumentError('云媒体必须提供来源、稳定标识和远程路径');
    }
    return MediaLibraryEpisode._(
      stableId: '$sourceId|$stableId',
      name: name,
      sourceKind: MediaSourceKind.cloud,
      sourceId: sourceId,
      sourceName: sourceName,
      isAvailable: isAvailable,
      remoteId: remoteId,
      remotePath: remotePath,
      tmdbTitle: tmdbTitle,
      tmdbOriginalTitle: tmdbOriginalTitle,
      tmdbOverview: tmdbOverview,
      tmdbRating: tmdbRating,
      tmdbPosterUrl: tmdbPosterUrl,
      tmdbBackdropUrl: tmdbBackdropUrl,
      posterCachePath: posterCachePath,
      size: size,
      modifiedAt: modifiedAt,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      subtitleRemotePaths: subtitleRemotePaths,
      subtitleRemoteRefs: subtitleRemoteRefs,
      releaseTags: releaseTags,
    );
  }

  final String stableId;
  final String name;
  final MediaSourceKind sourceKind;
  final String sourceId;
  final String sourceName;
  final bool isAvailable;
  final LocalMediaIndexItem? localItem;
  final String? remoteId;
  final String? remotePath;
  final String? tmdbTitle;
  final String? tmdbOriginalTitle;
  final String? tmdbOverview;
  final double? tmdbRating;
  final String? tmdbPosterUrl;
  final String? tmdbBackdropUrl;
  final String? posterCachePath;
  final int? size;
  final DateTime? modifiedAt;
  final int? seasonNumber;
  final int? episodeNumber;
  final List<String> subtitleRemotePaths;
  final List<CloudRemoteRef> subtitleRemoteRefs;
  final MediaReleaseTags releaseTags;
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
    this.genres = const <String>[],
    this.tmdbTitle,
    this.tmdbOverview,
    this.tmdbRating,
    this.tmdbReleaseDate,
    this.tmdbPosterUrl,
    this.posterCachePath,
    this.mediaType,
  });

  final String key;
  final String seriesKey;
  final String title;
  final MediaSourceKind sourceKind;
  final String sourceId;
  final String sourceName;
  final bool isAvailable;
  final List<MediaLibraryEpisode> episodes;
  final List<String> genres;
  final String? tmdbTitle;
  final String? tmdbOverview;
  final double? tmdbRating;
  final String? tmdbReleaseDate;
  final String? tmdbPosterUrl;
  final String? posterCachePath;
  final TmdbMediaType? mediaType;
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
  const CloudMediaLibraryAggregator({
    CloudWorkGroupingPolicy workGroupingPolicy =
        const CloudWorkGroupingPolicy(),
  }) : _workGroupingPolicy = workGroupingPolicy;

  final CloudWorkGroupingPolicy _workGroupingPolicy;

  CloudMediaLibrary build({
    required Iterable<LocalMediaIndexItem> localItems,
    required Iterable<CloudMediaIndexItem> cloudItems,
    required Iterable<CloudSource> cloudSources,
    Map<String, CloudWorkTmdbRecord> workRecordsByKey =
        const <String, CloudWorkTmdbRecord>{},
  }) {
    final sources = {for (final source in cloudSources) source.id: source};
    final result = <MediaLibrarySeries>[];
    for (final local
        in const LocalMediaLibraryBuilder().buildSeries(localItems)) {
      final metadata = _localMetadata(local.episodes);
      final tmdbTitle = metadata?.title.trim() ?? '';
      final hasCustomTitle = local.episodes.any(
        (item) =>
            item.manualOverride &&
            item.seriesName.trim().toLowerCase() ==
                local.title.trim().toLowerCase(),
      );
      final effectiveTitle =
          hasCustomTitle || tmdbTitle.isEmpty ? local.title : tmdbTitle;
      result.add(MediaLibrarySeries(
        key: 'local|${local.key}',
        seriesKey: local.key,
        title: effectiveTitle,
        sourceKind: MediaSourceKind.local,
        sourceId: 'local',
        sourceName: '本地',
        isAvailable: true,
        mediaType: metadata?.mediaType ?? _localMediaType(local.episodes),
        genres: _uniqueGenres(
          local.episodes.expand(
            (item) => item.tmdb?.genres ?? const <String>[],
          ),
        ),
        tmdbTitle: metadata?.title,
        tmdbOverview: metadata?.overview,
        tmdbRating: metadata?.rating,
        tmdbReleaseDate: metadata?.releaseDate,
        tmdbPosterUrl: metadata?.posterUrl,
        posterCachePath: local.cover,
        episodes: local.episodes
            .map((item) => MediaLibraryEpisode.local(
                  stableId: item.id,
                  name: _episodeDisplayName(
                    item.name,
                    metadata ?? item.tmdb,
                    item.seasonNumber,
                    item.episodeNumber,
                    seriesTitle: effectiveTitle,
                  ),
                  localItem: item,
                ))
            .toList(growable: false),
      ));
    }

    final availableCloudItems = cloudItems
        .where((item) => sources[item.sourceId]?.enabled == true)
        .toList(growable: false);
    final matchedKeysByTitle = <String, Set<String>>{};
    for (final item in availableCloudItems) {
      final record = _recordForItem(item, workRecordsByKey);
      final matchedKey =
          _workGroupingPolicy.matchedGroupKey(item.sourceId, record);
      if (matchedKey == null) continue;
      for (final title in _cloudTitleAliases(item, record)) {
        matchedKeysByTitle
            .putIfAbsent('${item.sourceId}|$title', () => <String>{})
            .add(matchedKey);
      }
    }

    final groups = <String, List<CloudMediaIndexItem>>{};
    for (final item in availableCloudItems) {
      groups
          .putIfAbsent(
            _cloudGroupKey(item, workRecordsByKey, matchedKeysByTitle),
            () => [],
          )
          .add(item);
    }
    for (final entry in groups.entries) {
      final items = entry.value..sort(_compareCloudEpisodes);
      final source = sources[items.first.sourceId];
      final indexedMetadata = _metadataItem(items);
      final workRecord = _workRecord(items, workRecordsByKey);
      final workMetadata = workRecord?.metadata;
      final seasonMetadata = _seasonMetadata(
        workMetadata,
        CloudMediaGroupingMetadata.seasonNumber(items.first),
      );
      final recognizedTitle = indexedMetadata?.tmdbTitle ??
          (items.first.seriesName.trim().isEmpty
              ? items.first.name
              : items.first.seriesName.trim());
      final effectiveTitle =
          workRecord?.effectiveTitle(recognizedTitle) ?? recognizedTitle;
      final title = _cloudGroupTitle(items.first, effectiveTitle);
      final posterUrl = seasonMetadata?.posterUrl ??
          workMetadata?.posterUrl ??
          indexedMetadata?.tmdbPosterUrl;
      final posterCachePath = seasonMetadata?.posterCachePath ??
          workRecord?.posterCachePath ??
          indexedMetadata?.posterCachePath;
      final mediaType = workMetadata?.mediaType ?? _cloudMediaType(items);
      final genres = workMetadata?.genres.isNotEmpty == true
          ? workMetadata!.genres
          : _uniqueGenres(items.expand((item) => item.tmdbGenres));
      result.add(MediaLibrarySeries(
        key: entry.key,
        seriesKey: items.first.seriesName.trim(),
        title: title,
        sourceKind: MediaSourceKind.cloud,
        sourceId: items.first.sourceId,
        sourceName: source?.name ?? items.first.sourceId,
        isAvailable: source?.enabled == true,
        mediaType: mediaType,
        genres: _uniqueGenres(genres),
        tmdbTitle: workMetadata?.title ?? indexedMetadata?.tmdbTitle,
        tmdbOverview: workMetadata?.overview ?? indexedMetadata?.tmdbOverview,
        tmdbRating: workMetadata?.rating ?? indexedMetadata?.tmdbRating,
        tmdbReleaseDate: workMetadata?.releaseDate,
        tmdbPosterUrl: posterUrl,
        posterCachePath: posterCachePath,
        episodes: items
            .map((item) => MediaLibraryEpisode.cloud(
                  stableId: item.remoteId,
                  name: _cloudEpisodeTitle(
                    item,
                    workMetadata,
                    effectiveTitle: effectiveTitle,
                  ),
                  sourceId: item.sourceId,
                  sourceName: source?.name ?? item.sourceId,
                  isAvailable: source?.enabled == true,
                  remoteId: item.remoteId,
                  remotePath: item.remotePath,
                  tmdbTitle: workMetadata?.title ?? item.tmdbTitle,
                  tmdbOriginalTitle:
                      workMetadata?.originalTitle ?? item.tmdbOriginalTitle,
                  tmdbOverview: workMetadata?.overview ?? item.tmdbOverview,
                  tmdbRating: workMetadata?.rating ?? item.tmdbRating,
                  tmdbPosterUrl: posterUrl ?? item.tmdbPosterUrl,
                  tmdbBackdropUrl:
                      workMetadata?.backdropUrl ?? item.tmdbBackdropUrl,
                  posterCachePath: posterCachePath ?? item.posterCachePath,
                  size: item.size,
                  modifiedAt: item.modifiedAt,
                  seasonNumber: CloudMediaGroupingMetadata.seasonNumber(item),
                  episodeNumber: item.episodeNumber,
                  subtitleRemotePaths: item.subtitlePaths,
                  subtitleRemoteRefs: item.subtitleRefs,
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

  static CloudMediaIndexItem? _metadataItem(List<CloudMediaIndexItem> items) {
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

  static TmdbMetadata? _localMetadata(List<LocalMediaIndexItem> items) {
    for (final item in items) {
      if (item.tmdb != null) return item.tmdb;
    }
    return null;
  }

  static TmdbMediaType _localMediaType(List<LocalMediaIndexItem> items) {
    final isSeries = items.any(
      (item) =>
          (item.seasonNumber != null && item.seasonNumber! > 0) ||
          (item.episodeNumber != null && item.episodeNumber! > 0),
    );
    return isSeries ? TmdbMediaType.tv : TmdbMediaType.movie;
  }

  String _cloudGroupKey(
    CloudMediaIndexItem item,
    Map<String, CloudWorkTmdbRecord> records,
    Map<String, Set<String>> matchedKeysByTitle,
  ) {
    final workKey = item.workKey;
    final record = workKey == null ? null : records[workKey];
    var groupKey = _workGroupingPolicy.matchedGroupKey(item.sourceId, record);
    if (groupKey == null &&
        CloudMediaGroupingMetadata.seasonNumber(item) != null) {
      final inheritedKeys = <String>{};
      for (final title in _cloudTitleAliases(item, record)) {
        inheritedKeys.addAll(
          matchedKeysByTitle['${item.sourceId}|$title'] ?? const <String>{},
        );
      }
      if (inheritedKeys.length == 1) groupKey = inheritedKeys.single;
    }
    final normalizedWorkKey = workKey?.trim() ?? '';
    groupKey ??= normalizedWorkKey.isNotEmpty
        ? '${item.sourceId}|work|$normalizedWorkKey'
        : '${item.sourceId}|series|${item.seriesName.trim().toLowerCase()}';
    return '$groupKey|${_groupVariant(item)}';
  }

  CloudWorkTmdbRecord? _recordForItem(
    CloudMediaIndexItem item,
    Map<String, CloudWorkTmdbRecord> records,
  ) {
    final workKey = item.workKey;
    return workKey == null ? null : records[workKey];
  }

  Set<String> _cloudTitleAliases(
    CloudMediaIndexItem item,
    CloudWorkTmdbRecord? record,
  ) {
    return _workGroupingPolicy.titleAliases(
      candidates: <String?>[
        item.seriesName,
        item.tmdbTitle,
        item.tmdbOriginalTitle,
        record?.remoteName,
        record?.metadata?.title,
        record?.metadata?.originalTitle,
      ],
      seasonNumbers: <int>[
        if (CloudMediaGroupingMetadata.seasonNumber(item) case final season?)
          season,
      ],
    );
  }

  static CloudWorkTmdbRecord? _workRecord(
    List<CloudMediaIndexItem> items,
    Map<String, CloudWorkTmdbRecord> records,
  ) {
    for (final item in items) {
      final workKey = item.workKey;
      if (workKey == null || workKey.isEmpty) continue;
      final record = records[workKey];
      if (record?.metadata != null) return record;
    }
    return null;
  }

  static TmdbSeasonMetadata? _seasonMetadata(
    TmdbMetadata? metadata,
    int? seasonNumber,
  ) {
    if (metadata == null || seasonNumber == null) return null;
    for (final season in metadata.seasons) {
      if (season.seasonNumber == seasonNumber) return season;
    }
    return null;
  }

  static TmdbMediaType? _cloudMediaType(List<CloudMediaIndexItem> items) {
    if (items.any(
      (item) =>
          item.mediaType == CloudMediaType.series ||
          item.mediaType == CloudMediaType.episode,
    )) {
      return TmdbMediaType.tv;
    }
    if (items.any(
      (item) =>
          item.mediaType == CloudMediaType.movie ||
          item.mediaType == CloudMediaType.special,
    )) {
      return TmdbMediaType.movie;
    }
    return null;
  }

  static String _cloudGroupTitle(CloudMediaIndexItem item, String? tmdbTitle) {
    final scrapedName = tmdbTitle?.trim() ?? '';
    final name = scrapedName.isNotEmpty
        ? scrapedName
        : item.seriesName.trim().isEmpty
            ? item.name
            : item.seriesName.trim();
    if (item.mediaType == CloudMediaType.special) return '$name 特别篇';
    final season = CloudMediaGroupingMetadata.seasonNumber(item);
    if (season != null && season > 0) {
      return '$name S${season.toString().padLeft(2, '0')}';
    }
    return name;
  }

  static String _cloudEpisodeTitle(
    CloudMediaIndexItem item,
    TmdbMetadata? workMetadata, {
    required String effectiveTitle,
  }) {
    final metadata = workMetadata ??
        (item.tmdbTitle?.trim().isNotEmpty == true
            ? TmdbMetadata(
                id: item.tmdbId ?? 0,
                mediaType: TmdbMediaType.tv,
                title: item.tmdbTitle!.trim(),
                originalTitle: item.tmdbOriginalTitle,
                language: 'zh-CN',
                matchedAt: DateTime.fromMillisecondsSinceEpoch(0),
                matchConfidence: 0,
              )
            : null);
    return _episodeDisplayName(
      item.name,
      metadata,
      item.seasonNumber,
      item.episodeNumber,
      seriesTitle: effectiveTitle,
    );
  }

  static String _episodeDisplayName(String originalName, TmdbMetadata? metadata,
      int? seasonNumber, int? episodeNumber,
      {String? seriesTitle}) {
    final episodeName = _episodeName(metadata, seasonNumber, episodeNumber);
    return const TmdbEpisodeTitleResolver().resolveWithExtension(
      seriesTitle: seriesTitle ?? metadata?.title,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeName: episodeName,
      originalFileName: originalName,
    );
  }

  static String? _episodeName(
    TmdbMetadata? metadata,
    int? seasonNumber,
    int? episodeNumber,
  ) {
    if (metadata == null || seasonNumber == null || episodeNumber == null) {
      return null;
    }
    for (final season in metadata.seasons) {
      if (season.seasonNumber != seasonNumber) continue;
      for (final episode in season.episodes) {
        if (episode.episodeNumber == episodeNumber &&
            episode.name.trim().isNotEmpty) {
          return episode.name;
        }
      }
    }
    return null;
  }

  static String _groupVariant(CloudMediaIndexItem item) =>
      item.mediaType == CloudMediaType.special
          ? 'special'
          : 'season:${CloudMediaGroupingMetadata.seasonNumber(item) ?? 0}';

  static int _compareCloudEpisodes(
      CloudMediaIndexItem a, CloudMediaIndexItem b) {
    final episode = (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
    return episode != 0 ? episode : a.name.compareTo(b.name);
  }
}

List<String> _uniqueGenres(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    final genre = value.trim();
    if (genre.isNotEmpty && !result.contains(genre)) result.add(genre);
  }
  return List<String>.unmodifiable(result);
}
