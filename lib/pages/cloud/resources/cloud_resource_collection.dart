import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
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
    int? uniqueEpisodeCount,
    this.metadata,
  })  : videos = List<CloudFileEntry>.unmodifiable(videos),
        uniqueEpisodeCount =
            uniqueEpisodeCount ?? metadata?.episodeCount ?? videos.length;

  final int? seasonNumber;
  final List<CloudFileEntry> videos;
  final int uniqueEpisodeCount;
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
    int? uniqueEpisodeCount,
    String? workKey,
    String? displayName,
    this.seasonNumber,
    this.workRecord,
    this.seasonMetadata,
    this.isWorkScoped = false,
  })  : videos = List<CloudFileEntry>.unmodifiable(videos),
        seasons = List<CloudResourceSeasonGroup>.unmodifiable(seasons),
        uniqueEpisodeCount =
            uniqueEpisodeCount ?? seasonMetadata?.episodeCount ?? videos.length,
        workKey = workKey ?? stableKey,
        displayName = displayName ?? seriesName;

  final String stableKey;
  final String workKey;
  final String displayName;
  final String seriesName;
  final bool isSeries;
  final int? seasonNumber;
  final List<CloudFileEntry> videos;
  final List<CloudResourceSeasonGroup> seasons;
  final int uniqueEpisodeCount;
  final CloudResourceTmdbRecord? record;
  final CloudWorkTmdbRecord? workRecord;
  final TmdbSeasonMetadata? seasonMetadata;
  final bool isWorkScoped;

  CloudFileEntry get anchor => videos.first;
}

class CloudResourceCollectionGrouper {
  CloudResourceCollectionGrouper({
    CloudSeriesIdentityResolver? identityResolver,
  }) : _identityResolver = identityResolver ?? CloudSeriesIdentityResolver();

  final CloudSeriesIdentityResolver _identityResolver;

  CloudResourceCollection group({
    String? sourceId,
    List<CloudFileEntry> entries = const <CloudFileEntry>[],
    Map<String, CloudResourceTmdbRecord> records =
        const <String, CloudResourceTmdbRecord>{},
    int minSizeBytes = 0,
    List<CloudMediaIndexItem> items = const <CloudMediaIndexItem>[],
    List<CloudWorkIdentity> works = const <CloudWorkIdentity>[],
    Map<String, CloudWorkTmdbRecord> recordsByWorkKey =
        const <String, CloudWorkTmdbRecord>{},
    required String query,
  }) {
    if (items.isNotEmpty || works.isNotEmpty || recordsByWorkKey.isNotEmpty) {
      return _groupWorks(
        items: items,
        works: works,
        recordsByWorkKey: recordsByWorkKey,
        query: query,
      );
    }
    if (sourceId == null || sourceId.trim().isEmpty) {
      throw ArgumentError.value(sourceId, 'sourceId');
    }
    final legacySourceId = sourceId;
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
        sourceId: legacySourceId,
        remoteId: entry.id,
        remotePath: entry.remotePath,
      );
      candidates.add(
        _CloudResourceCandidate(
          entry: entry,
          resourceKey: resourceKey,
          identity: _identityResolver.resolve(
            sourceId: legacySourceId,
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
      final groupKey = _matchedGroupKey(legacySourceId, record);
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
      var stableKey = _matchedGroupKey(legacySourceId, candidate.record);
      if (stableKey == null && identity != null) {
        final matchedKeys = tmdbKeysBySeries[identity.normalizedSeriesName];
        stableKey = matchedKeys?.length == 1
            ? matchedKeys!.single
            : '$legacySourceId|series|${identity.normalizedSeriesName}';
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

  CloudResourceCollection _groupWorks({
    required List<CloudMediaIndexItem> items,
    required List<CloudWorkIdentity> works,
    required Map<String, CloudWorkTmdbRecord> recordsByWorkKey,
    required String query,
  }) {
    final itemsByWorkKey = <String, List<CloudMediaIndexItem>>{};
    for (final item in items) {
      final workKey = item.workKey;
      if (workKey == null || workKey.isEmpty) continue;
      itemsByWorkKey.putIfAbsent(workKey, () => <CloudMediaIndexItem>[]).add(
            item,
          );
    }
    final groups = <CloudResourceMediaGroup>[];
    final uniqueWorks = <String, CloudWorkIdentity>{
      for (final work in works) work.workKey: work,
    };
    for (final work in uniqueWorks.values) {
      final workItems = itemsByWorkKey[work.workKey];
      if (workItems == null || workItems.isEmpty) continue;
      final record = recordsByWorkKey[work.workKey];
      final title =
          record?.effectiveTitle(work.displayTitle) ?? work.displayTitle;
      if (work.seasons.isEmpty) {
        final videos = _virtualEntries(workItems);
        if (videos.isEmpty) continue;
        final group = CloudResourceMediaGroup(
          stableKey: work.workKey,
          workKey: work.workKey,
          displayName: title,
          seriesName: title,
          isSeries: false,
          videos: videos,
          seasons: const <CloudResourceSeasonGroup>[],
          record: null,
          workRecord: record,
          isWorkScoped: true,
        );
        if (_matchesWork(group, work, workItems, query)) groups.add(group);
        continue;
      }
      for (final season in work.seasons) {
        final seasonItems = workItems
            .where((item) => item.seasonNumber == season.seasonNumber)
            .toList(growable: false);
        if (seasonItems.isEmpty) continue;
        final seasonMetadata = _seasonMetadata(
          record,
          season.seasonNumber,
        );
        final videos = _virtualEntries(seasonItems);
        final seasonGroup = CloudResourceSeasonGroup(
          seasonNumber: season.seasonNumber,
          videos: videos,
          uniqueEpisodeCount: _uniqueEpisodeCount(seasonItems),
          metadata: seasonMetadata,
        );
        final group = CloudResourceMediaGroup(
          stableKey: '${work.workKey}|season:${season.seasonNumber}',
          workKey: work.workKey,
          displayName: '$title 第 ${season.seasonNumber} 季',
          seriesName: title,
          isSeries: true,
          seasonNumber: season.seasonNumber,
          videos: videos,
          seasons: <CloudResourceSeasonGroup>[seasonGroup],
          record: null,
          uniqueEpisodeCount: seasonGroup.uniqueEpisodeCount,
          workRecord: record,
          seasonMetadata: seasonMetadata,
          isWorkScoped: true,
        );
        if (_matchesWork(group, work, seasonItems, query)) groups.add(group);
      }
    }
    groups.sort((first, second) {
      final title = first.seriesName.toLowerCase().compareTo(
            second.seriesName.toLowerCase(),
          );
      if (title != 0) return title;
      return (first.seasonNumber ?? -1).compareTo(second.seasonNumber ?? -1);
    });
    return CloudResourceCollection(groups: groups);
  }

  List<CloudFileEntry> _virtualEntries(List<CloudMediaIndexItem> items) {
    final sorted = List<CloudMediaIndexItem>.from(items)
      ..sort((first, second) {
        final season = (first.seasonNumber ?? -1).compareTo(
          second.seasonNumber ?? -1,
        );
        if (season != 0) return season;
        final episode = (first.episodeNumber ?? -1).compareTo(
          second.episodeNumber ?? -1,
        );
        if (episode != 0) return episode;
        return first.remotePath.compareTo(second.remotePath);
      });
    final duplicateCounts = <int, int>{};
    for (final item in sorted) {
      final episode = item.episodeNumber;
      if (episode != null) {
        duplicateCounts[episode] = (duplicateCounts[episode] ?? 0) + 1;
      }
    }
    final duplicateIndexes = <int, int>{};
    return sorted.map((item) {
      var displayName = item.displayName;
      final episode = item.episodeNumber;
      if (episode != null && (duplicateCounts[episode] ?? 0) > 1) {
        final index = (duplicateIndexes[episode] ?? 0) + 1;
        duplicateIndexes[episode] = index;
        final summary = _releaseSummary(item);
        if (summary.isNotEmpty || index > 1) {
          final suffix = summary.isEmpty ? '版本 $index' : summary;
          final extension = p.extension(displayName);
          final base = p.basenameWithoutExtension(displayName);
          displayName = '$base [$suffix]$extension';
        }
      }
      return CloudFileEntry(
        id: item.remoteId,
        remotePath: item.remotePath,
        name: displayName,
        size: item.size,
        modifiedAt: item.modifiedAt,
        isDirectory: false,
      );
    }).toList(growable: false);
  }

  String _releaseSummary(CloudMediaIndexItem item) {
    final tags = item.releaseTags;
    return <String?>[
      tags.resolution,
      tags.bitrate,
      tags.source,
      tags.codec,
      ...tags.dynamicRange,
      ...tags.audio,
      ...tags.subtitles,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
  }

  int _uniqueEpisodeCount(List<CloudMediaIndexItem> items) {
    final episodeNumbers =
        items.map((item) => item.episodeNumber).whereType<int>().toSet();
    return episodeNumbers.isEmpty ? items.length : episodeNumbers.length;
  }

  TmdbSeasonMetadata? _seasonMetadata(
    CloudWorkTmdbRecord? record,
    int seasonNumber,
  ) {
    for (final season in record?.seasons ?? const <TmdbSeasonMetadata>[]) {
      if (season.seasonNumber == seasonNumber) return season;
    }
    return null;
  }

  bool _matchesWork(
    CloudResourceMediaGroup group,
    CloudWorkIdentity work,
    List<CloudMediaIndexItem> items,
    String query,
  ) {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return true;
    final metadata = group.workRecord?.metadata;
    final values = <String?>[
      group.displayName,
      group.seriesName,
      metadata?.title,
      metadata?.originalTitle,
      work.remoteName,
      ...work.titleCandidates,
      ...items.expand((item) => <String>[item.remoteName, item.displayName]),
    ];
    return values.any(
      (value) => value?.toLowerCase().contains(keyword) == true,
    );
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
