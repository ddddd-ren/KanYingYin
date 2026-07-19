import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_series_identity_resolver.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:path/path.dart' as p;

class CloudResourceCollection {
  CloudResourceCollection({required List<CloudResourceMediaGroup> groups})
      : groups = List<CloudResourceMediaGroup>.unmodifiable(groups);

  final List<CloudResourceMediaGroup> groups;

  /// 兼容旧调用方；来源级海报墙不再暴露文件夹入口。
  List<CloudFileEntry> get folders => const <CloudFileEntry>[];
}

class CloudResourceSeasonGroup {
  CloudResourceSeasonGroup({
    required this.seasonNumber,
    required List<CloudFileEntry> videos,
    this.metadata,
  }) : videos = List<CloudFileEntry>.unmodifiable(videos);

  final int? seasonNumber;
  final List<CloudFileEntry> videos;
  final TmdbSeasonMetadata? metadata;
}

class CloudResourceMediaGroup {
  CloudResourceMediaGroup({
    required this.stableKey,
    required this.seriesName,
    required this.isSeries,
    required List<CloudFileEntry> videos,
    required List<CloudResourceSeasonGroup> seasons,
    required this.record,
  })  : videos = List<CloudFileEntry>.unmodifiable(videos),
        seasons = List<CloudResourceSeasonGroup>.unmodifiable(seasons);

  final String stableKey;
  final String seriesName;
  final bool isSeries;
  final List<CloudFileEntry> videos;
  final List<CloudResourceSeasonGroup> seasons;
  final CloudResourceTmdbRecord? record;

  CloudFileEntry get anchor => videos.first;
}

class CloudResourceCollectionGrouper {
  CloudResourceCollectionGrouper({
    CloudSeriesIdentityResolver? identityResolver,
  }) : _identityResolver = identityResolver ?? CloudSeriesIdentityResolver();

  final CloudSeriesIdentityResolver _identityResolver;

  CloudResourceCollection group({
    required String sourceId,
    required List<CloudFileEntry> entries,
    required Map<String, CloudResourceTmdbRecord> records,
    required int minSizeBytes,
    required String query,
  }) {
    final candidates = <_CloudResourceCandidate>[];
    for (final entry in entries) {
      if (entry.isDirectory ||
          !LocalVideoFileTypes.isRecognizedVideo(
            entry.name,
            size: entry.size,
            minSizeBytes: minSizeBytes,
          )) {
        continue;
      }
      final resourceKey = cloudResourceTmdbKey(
        sourceId: sourceId,
        remoteId: entry.id,
        remotePath: entry.remotePath,
      );
      candidates.add(
        _CloudResourceCandidate(
          entry: entry,
          resourceKey: resourceKey,
          identity: _identityResolver.resolve(
            sourceId: sourceId,
            remotePath: entry.remotePath,
            size: entry.size,
            minSizeBytes: minSizeBytes,
          ),
          record: records[resourceKey],
        ),
      );
    }

    final tmdbKeysBySeries = <String, Set<String>>{};
    final recordsByGroupKey = <String, CloudResourceTmdbRecord>{};
    for (final candidate in candidates) {
      final record = candidate.record;
      final identity = candidate.identity;
      final groupKey = _matchedGroupKey(sourceId, record);
      if (groupKey == null) continue;
      recordsByGroupKey[groupKey] = record!;
      if (identity != null && record.mediaType == TmdbMediaType.tv) {
        tmdbKeysBySeries
            .putIfAbsent(identity.normalizedSeriesName, () => <String>{})
            .add(groupKey);
      }
    }

    final builders = <String, _CloudResourceMediaGroupBuilder>{};
    for (final candidate in candidates) {
      final identity = candidate.identity;
      var stableKey = _matchedGroupKey(sourceId, candidate.record);
      if (stableKey == null && identity != null) {
        final matchedKeys = tmdbKeysBySeries[identity.normalizedSeriesName];
        stableKey = matchedKeys?.length == 1
            ? matchedKeys!.single
            : '$sourceId|series|${identity.normalizedSeriesName}';
      }
      stableKey ??= candidate.resourceKey;
      final resolvedStableKey = stableKey;
      final inheritedRecord = recordsByGroupKey[stableKey];
      final builder = builders.putIfAbsent(
        resolvedStableKey,
        () => _CloudResourceMediaGroupBuilder(
          stableKey: resolvedStableKey,
          seriesName: identity?.seriesName.trim().isNotEmpty == true
              ? identity!.seriesName.trim()
              : p.basenameWithoutExtension(candidate.entry.name),
          isSeries: identity != null ||
              candidate.record?.mediaType == TmdbMediaType.tv ||
              inheritedRecord?.mediaType == TmdbMediaType.tv,
        ),
      );
      builder
        ..videos.add(candidate.entry)
        ..identities[_entryKey(candidate.entry)] = identity
        ..considerRecord(candidate.record ?? inheritedRecord);
    }

    final keyword = query.trim().toLowerCase();
    final groups = <CloudResourceMediaGroup>[];
    for (final builder in builders.values) {
      final group = builder.build();
      if (_matches(group, keyword)) groups.add(group);
    }
    groups.sort((first, second) {
      final firstTitle = first.record?.effectiveTitle ?? first.seriesName;
      final secondTitle = second.record?.effectiveTitle ?? second.seriesName;
      return firstTitle.toLowerCase().compareTo(secondTitle.toLowerCase());
    });
    return CloudResourceCollection(groups: groups);
  }

  static String? _matchedGroupKey(
    String sourceId,
    CloudResourceTmdbRecord? record,
  ) {
    final tmdbId = record?.tmdbId;
    final mediaType = record?.mediaType;
    if (record?.status != CloudResourceTmdbStatus.matched ||
        tmdbId == null ||
        mediaType == null) {
      return null;
    }
    return '$sourceId|tmdb|${mediaType.name}|$tmdbId';
  }

  static bool _matches(CloudResourceMediaGroup group, String keyword) {
    if (keyword.isEmpty) return true;
    final record = group.record;
    final values = <String?>[
      record?.effectiveTitle,
      record?.originalTitle,
      group.seriesName,
      group.stableKey,
    ];
    return values.any(
          (value) => value?.toLowerCase().contains(keyword) == true,
        ) ||
        group.videos.any(
          (video) => video.name.toLowerCase().contains(keyword),
        );
  }
}

class _CloudResourceCandidate {
  const _CloudResourceCandidate({
    required this.entry,
    required this.resourceKey,
    required this.identity,
    required this.record,
  });

  final CloudFileEntry entry;
  final String resourceKey;
  final CloudSeriesEpisodeIdentity? identity;
  final CloudResourceTmdbRecord? record;
}

class _CloudResourceMediaGroupBuilder {
  _CloudResourceMediaGroupBuilder({
    required this.stableKey,
    required this.seriesName,
    required this.isSeries,
  });

  final String stableKey;
  final String seriesName;
  final bool isSeries;
  final List<CloudFileEntry> videos = <CloudFileEntry>[];
  final Map<String, CloudSeriesEpisodeIdentity?> identities =
      <String, CloudSeriesEpisodeIdentity?>{};
  CloudResourceTmdbRecord? record;
  int _recordPriority = -1;

  void considerRecord(CloudResourceTmdbRecord? candidate) {
    final priority = _priority(candidate);
    if (priority <= _recordPriority) return;
    record = candidate;
    _recordPriority = priority;
  }

  CloudResourceMediaGroup build() {
    videos.sort(_compareVideos);
    return CloudResourceMediaGroup(
      stableKey: stableKey,
      seriesName: seriesName,
      isSeries: isSeries,
      videos: videos,
      seasons: isSeries ? _buildSeasons() : const <CloudResourceSeasonGroup>[],
      record: record,
    );
  }

  List<CloudResourceSeasonGroup> _buildSeasons() {
    final videosBySeason = <int?, List<CloudFileEntry>>{};
    for (final video in videos) {
      final identity = identities[_entryKey(video)];
      videosBySeason
          .putIfAbsent(identity?.seasonNumber, () => <CloudFileEntry>[])
          .add(video);
    }
    final seasonNumbers = videosBySeason.keys.toList(growable: false)
      ..sort((first, second) {
        if (first == null) return second == null ? 0 : 1;
        if (second == null) return -1;
        return first.compareTo(second);
      });
    return seasonNumbers.map((seasonNumber) {
      TmdbSeasonMetadata? metadata;
      if (seasonNumber != null) {
        for (final season in record?.seasons ?? const <TmdbSeasonMetadata>[]) {
          if (season.seasonNumber == seasonNumber) {
            metadata = season;
            break;
          }
        }
      }
      return CloudResourceSeasonGroup(
        seasonNumber: seasonNumber,
        videos: videosBySeason[seasonNumber]!,
        metadata: metadata,
      );
    }).toList(growable: false);
  }

  int _compareVideos(CloudFileEntry first, CloudFileEntry second) {
    if (!isSeries) return _compareEntriesByName(first, second);
    final firstIdentity = identities[_entryKey(first)];
    final secondIdentity = identities[_entryKey(second)];
    final season = (firstIdentity?.seasonNumber ?? (1 << 30))
        .compareTo(secondIdentity?.seasonNumber ?? (1 << 30));
    if (season != 0) return season;
    final episode = (firstIdentity?.episodeNumber ?? (1 << 30))
        .compareTo(secondIdentity?.episodeNumber ?? (1 << 30));
    return episode != 0 ? episode : _compareEntriesByName(first, second);
  }

  static int _priority(CloudResourceTmdbRecord? candidate) {
    if (candidate == null) return -1;
    final customTitle = candidate.customTitle?.trim();
    if (customTitle != null && customTitle.isNotEmpty) return 2;
    if (candidate.status == CloudResourceTmdbStatus.matched) return 1;
    return 0;
  }

  static int _compareEntriesByName(
    CloudFileEntry first,
    CloudFileEntry second,
  ) =>
      first.name.toLowerCase().compareTo(second.name.toLowerCase());
}

String _entryKey(CloudFileEntry entry) => '${entry.id}|${entry.remotePath}';
