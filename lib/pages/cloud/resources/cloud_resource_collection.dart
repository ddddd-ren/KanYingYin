import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_series_identity_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_media_grouping_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_work_grouping_policy.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:kanyingyin/services/media_name_analyzer.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:kanyingyin/services/tmdb/tmdb_episode_title_resolver.dart';
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
    List<CloudResourceVersionGroup>? versions,
  })  : videos = List<CloudFileEntry>.unmodifiable(videos),
        versions = List<CloudResourceVersionGroup>.unmodifiable(
          versions ?? const <CloudResourceVersionGroup>[],
        ),
        uniqueEpisodeCount =
            uniqueEpisodeCount ?? metadata?.episodeCount ?? videos.length;

  final int? seasonNumber;
  final List<CloudFileEntry> videos;
  final int uniqueEpisodeCount;
  final TmdbSeasonMetadata? metadata;
  final List<CloudResourceVersionGroup> versions;
}

class CloudResourceVersionGroup {
  CloudResourceVersionGroup({
    required this.key,
    required this.label,
    required List<CloudFileEntry> videos,
  }) : videos = List<CloudFileEntry>.unmodifiable(videos);

  final String key;
  final String label;
  final List<CloudFileEntry> videos;

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
    List<String>? workKeys,
    this.seasonNumber,
    this.workRecord,
    this.seasonMetadata,
    this.isWorkScoped = false,
    List<CloudResourceVersionGroup>? versions,
  })  : videos = List<CloudFileEntry>.unmodifiable(videos),
        seasons = List<CloudResourceSeasonGroup>.unmodifiable(seasons),
        uniqueEpisodeCount =
            uniqueEpisodeCount ?? seasonMetadata?.episodeCount ?? videos.length,
        workKey = workKey ?? stableKey,
        workKeys = _normalizedWorkKeys(workKey ?? stableKey, workKeys),
        displayName = displayName ?? seriesName,
        versions = List<CloudResourceVersionGroup>.unmodifiable(
          versions ?? const <CloudResourceVersionGroup>[],
        );

  final String stableKey;
  final String workKey;
  final String displayName;
  final List<String> workKeys;
  final String seriesName;

  List<String> get legacySeriesTitles {
    final titles = <String>{
      displayName,
      seriesName,
      if (workRecord?.metadata?.title case final title?) title,
      if (record?.title case final title?) title,
    }.where((title) => title.trim().isNotEmpty);
    return [
      ...titles,
      if (seasonNumber case final season? when season > 0)
        for (final title in titles)
          '$title S${season.toString().padLeft(2, '0')}',
    ];
  }
  final bool isSeries;
  final int? seasonNumber;
  final List<CloudFileEntry> videos;
  final List<CloudResourceSeasonGroup> seasons;
  final int uniqueEpisodeCount;
  final CloudResourceTmdbRecord? record;
  final CloudWorkTmdbRecord? workRecord;
  final TmdbSeasonMetadata? seasonMetadata;
  final bool isWorkScoped;
  final List<CloudResourceVersionGroup> versions;

  CloudFileEntry get anchor => videos.first;
}

class CloudResourceCollectionGrouper {
  CloudResourceCollectionGrouper({
    CloudSeriesIdentityResolver? identityResolver,
    CloudWorkGroupingPolicy? workGroupingPolicy,
  })  : _identityResolver = identityResolver ?? CloudSeriesIdentityResolver(),
        _workGroupingPolicy =
            workGroupingPolicy ?? const CloudWorkGroupingPolicy();

  final CloudSeriesIdentityResolver _identityResolver;
  final CloudWorkGroupingPolicy _workGroupingPolicy;

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
    final uniqueWorks = <String, CloudWorkIdentity>{
      for (final work in works) work.workKey: work,
    };
    for (final entry in itemsByWorkKey.entries) {
      uniqueWorks.putIfAbsent(
        entry.key,
        () => _syntheticWork(entry.value),
      );
    }
    final matchedKeysByTitle = <String, Set<String>>{};
    for (final work in uniqueWorks.values) {
      final record = recordsByWorkKey[work.workKey];
      final matchedKey =
          _workGroupingPolicy.matchedGroupKey(work.sourceId, record);
      if (matchedKey == null) continue;
      for (final title in _workTitleAliases(work, record)) {
        matchedKeysByTitle.putIfAbsent(title, () => <String>{}).add(matchedKey);
      }
    }
    final aggregates = <String, _CloudWorkAggregate>{};
    for (final work in uniqueWorks.values) {
      final workItems = itemsByWorkKey[work.workKey];
      if (workItems == null || workItems.isEmpty) continue;
      final record = recordsByWorkKey[work.workKey];
      var aggregateKey =
          _workGroupingPolicy.matchedGroupKey(work.sourceId, record);
      final effectiveSeasonNumbers = workItems
          .map(CloudMediaGroupingMetadata.seasonNumber)
          .whereType<int>()
          .toSet();
      if (aggregateKey == null && effectiveSeasonNumbers.isNotEmpty) {
        final inheritedKeys = <String>{};
        for (final title in _workTitleAliases(work, record)) {
          inheritedKeys.addAll(matchedKeysByTitle[title] ?? const <String>{});
        }
        if (inheritedKeys.length == 1) {
          aggregateKey = inheritedKeys.single;
        }
      }
      final resolvedAggregateKey = aggregateKey ?? work.workKey;
      final aggregate = aggregates.putIfAbsent(
        resolvedAggregateKey,
        () => _CloudWorkAggregate(key: resolvedAggregateKey),
      );
      aggregate.works.add(work);
      aggregate.items.addAll(workItems);
      if (record != null) aggregate.records.add(record);
    }

    final groups = <CloudResourceMediaGroup>[];
    for (final aggregate in aggregates.values) {
      final representative = _representativeWork(aggregate, recordsByWorkKey);
      final record = _mergeWorkRecords(
        representative,
        aggregate.records,
        aggregate.items,
      );
      final title = record?.effectiveTitle(representative.displayTitle) ??
          representative.displayTitle;
      final workKeys = aggregate.works.map((work) => work.workKey).toList(
            growable: false,
          );
      final seasonNumbers = aggregate.items
          .map(CloudMediaGroupingMetadata.seasonNumber)
          .whereType<int>()
          .where((season) => season > 0)
          .toSet()
          .toList(growable: false)
        ..sort();
      if (seasonNumbers.isEmpty) {
        final videos = _virtualEntries(
          aggregate.items,
          labelMovieVariants: true,
          metadata: record?.metadata,
          seriesTitle: title,
        );
        if (videos.isEmpty) continue;
        final group = CloudResourceMediaGroup(
          stableKey: aggregate.key,
          workKey: representative.workKey,
          workKeys: workKeys,
          displayName: title,
          seriesName: title,
          isSeries: false,
          videos: videos,
          seasons: const <CloudResourceSeasonGroup>[],
          record: null,
          workRecord: record,
          isWorkScoped: true,
        );
        if (_matchesWork(group, aggregate.works, aggregate.items, query)) {
          groups.add(group);
        }
        continue;
      }

      final declaredSeasonNumbers = aggregate.works
          .expand((work) => work.seasons.map((season) => season.seasonNumber))
          .where((season) => season > 0)
          .toSet();
      final matchedSeasonNumbers = record?.metadata?.seasons
              .map((season) => season.seasonNumber)
              .where((season) => season > 0)
              .toSet() ??
          const <int>{};
      final effectiveSeasonNumbers = seasonNumbers.toSet();
      final declaredSeasonsMatch =
          declaredSeasonNumbers.length == effectiveSeasonNumbers.length &&
              declaredSeasonNumbers.containsAll(effectiveSeasonNumbers);
      final displaySeasonNumbers = declaredSeasonNumbers.isEmpty
          ? effectiveSeasonNumbers
          : declaredSeasonsMatch || matchedSeasonNumbers.isEmpty
              ? declaredSeasonNumbers
              : matchedSeasonNumbers;
      final omitOnlyFirstSeasonSuffix =
          displaySeasonNumbers.length == 1 && displaySeasonNumbers.single == 1;
      for (final seasonNumber in seasonNumbers) {
        final seasonItems = aggregate.items
            .where(
              (item) =>
                  CloudMediaGroupingMetadata.seasonNumber(item) == seasonNumber,
            )
            .toList(growable: false);
        if (seasonItems.isEmpty) continue;
        final seasonMetadata = _seasonMetadata(record, seasonNumber);
        final videos = _virtualEntries(
          seasonItems,
          metadata: record?.metadata,
          seriesTitle: title,
        );
        final origins = <String, String>{
          for (final item in seasonItems)
            '${item.remoteId}|${item.remotePath}':
                '${item.sourceId}|${item.workRootId ?? item.workRootPath ?? item.workKey}',
        };
        final directories = <String, String>{
          for (final item in seasonItems)
            '${item.remoteId}|${item.remotePath}': _versionDirectory(item),
        };
        final versions = _buildEpisodeVersions(
          videos,
          originFor: (video) => origins[_entryKey(video)]!,
          directoryFor: (video) => directories[_entryKey(video)]!,
        );
        final seasonGroup = CloudResourceSeasonGroup(
          seasonNumber: seasonNumber,
          videos: videos,
          uniqueEpisodeCount: _uniqueEpisodeCount(seasonItems),
          metadata: seasonMetadata,
          versions: versions,
        );
        final group = CloudResourceMediaGroup(
          stableKey: '${aggregate.key}|season:$seasonNumber',
          workKey: representative.workKey,
          workKeys: workKeys,
          displayName:
              omitOnlyFirstSeasonSuffix ? title : '$title 第 $seasonNumber 季',
          seriesName: title,
          isSeries: true,
          seasonNumber: seasonNumber,
          videos: videos,
          seasons: <CloudResourceSeasonGroup>[seasonGroup],
          record: null,
          uniqueEpisodeCount: seasonGroup.uniqueEpisodeCount,
          workRecord: record,
          seasonMetadata: seasonMetadata,
          isWorkScoped: true,
          versions: versions,
        );
        if (_matchesWork(group, aggregate.works, seasonItems, query)) {
          groups.add(group);
        }
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

  CloudWorkIdentity _syntheticWork(List<CloudMediaIndexItem> items) {
    final anchor = items.firstWhere(
      (item) => item.seriesName.trim().isNotEmpty,
      orElse: () => items.first,
    );
    final workKey = anchor.workKey!;
    final rootPath = anchor.workRootPath?.trim().isNotEmpty == true
        ? anchor.workRootPath!.trim()
        : p.posix.dirname(anchor.remotePath);
    final rootName = anchor.remoteName.trim().isNotEmpty
        ? anchor.remoteName.trim()
        : p.basename(rootPath);
    final displayTitle = <String?>[
      anchor.seriesName,
      anchor.tmdbTitle,
      anchor.tmdbOriginalTitle,
      rootName,
      anchor.name,
    ].map((value) => value?.trim() ?? '').firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => workKey,
        );
    final titleCandidates = <String>{};
    final seasonNumbers = <int>{};
    for (final item in items) {
      for (final value in <String?>[
        item.seriesName,
        item.tmdbTitle,
        item.tmdbOriginalTitle,
        item.remoteName,
        item.displayName,
        item.name,
      ]) {
        final normalized = value?.trim() ?? '';
        if (normalized.isNotEmpty) titleCandidates.add(normalized);
      }
      final season = item.seasonNumber;
      if (season != null && season > 0) seasonNumbers.add(season);
    }
    final sortedSeasons = seasonNumbers.toList()..sort();
    return CloudWorkIdentity(
      sourceId: anchor.sourceId,
      workKey: workKey,
      root: CloudFileEntry(
        id: anchor.workRootId?.trim().isNotEmpty == true
            ? anchor.workRootId!.trim()
            : workKey,
        remotePath: rootPath.isEmpty ? '/' : rootPath,
        name: rootName.isEmpty ? displayTitle : rootName,
        size: 0,
        modifiedAt: anchor.modifiedAt,
        isDirectory: true,
      ),
      remoteName: rootName.isEmpty ? displayTitle : rootName,
      displayTitle: displayTitle,
      titleCandidates: titleCandidates.toList(growable: false),
      seasons: <CloudSeasonIdentity>[
        for (final season in sortedSeasons)
          CloudSeasonIdentity(
            workKey: workKey,
            seasonNumber: season,
            displayName: '$displayTitle 第 $season 季',
            remoteDirectories: const <CloudFileEntry>[],
            episodes: const <CloudEpisodeIdentity>[],
          ),
      ],
    );
  }

  List<CloudFileEntry> _virtualEntries(
    List<CloudMediaIndexItem> items, {
    bool labelMovieVariants = false,
    TmdbMetadata? metadata,
    required String seriesTitle,
  }) {
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
    var movieVariantIndex = 0;
    return sorted.map((item) {
      var displayName = _episodeDisplayName(
        item,
        metadata,
        seriesTitle: seriesTitle,
      );
      final episode = item.episodeNumber;
      String? variantLabel;
      if (episode != null && (duplicateCounts[episode] ?? 0) > 1) {
        final index = (duplicateIndexes[episode] ?? 0) + 1;
        duplicateIndexes[episode] = index;
        final summary = _releaseSummary(item);
        variantLabel = summary.isEmpty ? '版本 $index' : summary;
        final extension = p.extension(displayName);
        final base = p.basenameWithoutExtension(displayName);
        displayName = '$base [$variantLabel]$extension';
      } else if (episode == null && labelMovieVariants && sorted.length > 1) {
        movieVariantIndex++;
        final summary = _releaseSummary(item);
        variantLabel = summary.isEmpty ? '版本 $movieVariantIndex' : summary;
        final extension = p.extension(displayName);
        final base = p.basenameWithoutExtension(displayName);
        displayName = '$base [$variantLabel]$extension';
      }
      return CloudFileEntry(
        id: item.remoteId,
        remotePath: item.remotePath,
        name: displayName,
        size: item.size,
        modifiedAt: item.modifiedAt,
        isDirectory: false,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        variantLabel: variantLabel,
        releaseTags: item.releaseTags,
      );
    }).toList(growable: false);
  }

  String _episodeDisplayName(
    CloudMediaIndexItem item,
    TmdbMetadata? metadata, {
    required String seriesTitle,
  }) {
    final episode = item.episodeNumber;
    final effectiveTitle = seriesTitle.trim();
    final title = effectiveTitle.isNotEmpty
        ? effectiveTitle
        : metadata?.title.trim() ?? item.tmdbTitle?.trim() ?? '';
    if (episode == null || episode <= 0 || title.isEmpty) {
      return item.displayName;
    }
    final episodeName = _episodeName(
      metadata,
      item.seasonNumber,
      episode,
    );
    return const TmdbEpisodeTitleResolver().resolveWithExtension(
      seriesTitle: title,
      seasonNumber: item.seasonNumber,
      episodeNumber: episode,
      episodeName: episodeName,
      originalFileName: item.displayName,
    );
  }

  String? _episodeName(
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
    List<CloudWorkIdentity> works,
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
      ...works.expand(
        (work) => <String?>[work.remoteName, ...work.titleCandidates],
      ),
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

  CloudWorkIdentity _representativeWork(
    _CloudWorkAggregate aggregate,
    Map<String, CloudWorkTmdbRecord> recordsByWorkKey,
  ) {
    return aggregate.works.reduce((first, second) {
      final firstRecord = recordsByWorkKey[first.workKey];
      final secondRecord = recordsByWorkKey[second.workKey];
      final firstKey =
          _workGroupingPolicy.matchedGroupKey(first.sourceId, firstRecord);
      final secondKey =
          _workGroupingPolicy.matchedGroupKey(second.sourceId, secondRecord);
      if (firstKey == null && secondKey != null) return second;
      return first;
    });
  }

  Set<String> _workTitleAliases(
    CloudWorkIdentity work,
    CloudWorkTmdbRecord? record,
  ) =>
      _workGroupingPolicy.titleAliases(
        candidates: <String?>[
          ...work.titleCandidates,
          work.displayTitle,
          work.remoteName,
          record?.metadata?.title,
          record?.metadata?.originalTitle,
        ],
        seasonNumbers: work.seasons.map((season) => season.seasonNumber),
      );

  CloudWorkTmdbRecord? _mergeWorkRecords(
    CloudWorkIdentity representative,
    List<CloudWorkTmdbRecord> records,
    List<CloudMediaIndexItem> items,
  ) {
    if (records.isEmpty) return null;
    final matched = records
        .where(
          (record) =>
              record.status == CloudWorkTmdbStatus.matched &&
              record.metadata != null,
        )
        .toList(growable: false);
    if (matched.isEmpty) return records.first;

    final base = matched.reduce((first, second) {
      final firstPriority = _workRecordPriority(first);
      final secondPriority = _workRecordPriority(second);
      return secondPriority > firstPriority ? second : first;
    });
    final metadata = base.metadata!;
    final genres = <String>[];
    final seasonsByNumber = <int, TmdbSeasonMetadata>{};
    final seasonOwners = <int, Set<String>>{};
    for (final item in items) {
      final number = CloudMediaGroupingMetadata.seasonNumber(item);
      final key = item.workKey;
      if (number != null && key != null) {
        seasonOwners.putIfAbsent(number, () => <String>{}).add(key);
      }
    }
    final ownedSeasons = <int>{};
    for (final record in matched) {
      final current = record.metadata!;
      for (final genre in current.genres) {
        final normalized = genre.trim();
        if (normalized.isNotEmpty && !genres.contains(normalized)) {
          genres.add(normalized);
        }
      }
      for (final season in current.seasons) {
        final previous = seasonsByNumber[season.seasonNumber];
        final owned =
            seasonOwners[season.seasonNumber]?.contains(record.workKey) == true;
        seasonsByNumber[season.seasonNumber] = previous == null
            ? season
            : owned && !ownedSeasons.contains(season.seasonNumber)
                ? _mergeSeasonMetadata(season, previous)
                : _mergeSeasonMetadata(previous, season);
        if (owned) ownedSeasons.add(season.seasonNumber);
      }
    }
    final seasons = seasonsByNumber.values.toList(growable: false)
      ..sort(
        (first, second) => first.seasonNumber.compareTo(second.seasonNumber),
      );
    final mergedMetadata = metadata.copyWith(
      genres: genres,
      seasons: seasons,
    );
    final customTitle = matched
        .map((record) => record.scrapeTitleOverride?.trim())
        .whereType<String>()
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );
    final checkedAt = matched
        .map((record) => record.checkedAt)
        .reduce((first, second) => first.isAfter(second) ? first : second);
    final posterCachePath = matched
        .map((record) => record.posterCachePath?.trim())
        .whereType<String>()
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );
    final origin = matched.any(
      (record) => record.tmdbMatchOrigin == TmdbMatchOrigin.manual,
    )
        ? TmdbMatchOrigin.manual
        : base.tmdbMatchOrigin;
    return CloudWorkTmdbRecord.matched(
      sourceId: representative.sourceId,
      workKey: representative.workKey,
      workRootId: representative.root.id,
      workRootPath: representative.root.remotePath,
      remoteName: representative.remoteName,
      metadata: mergedMetadata,
      checkedAt: checkedAt,
      scrapeTitleOverride: customTitle.isEmpty ? null : customTitle,
      posterCachePath: posterCachePath.isEmpty ? null : posterCachePath,
      tmdbMatchOrigin: origin,
      tmdbRuleVersion: matched
          .map((record) => record.tmdbRuleVersion)
          .reduce((first, second) => first < second ? first : second),
    );
  }

  static int _workRecordPriority(CloudWorkTmdbRecord record) {
    final customTitle = record.scrapeTitleOverride?.trim();
    if (customTitle != null && customTitle.isNotEmpty) return 2;
    if (record.tmdbMatchOrigin == TmdbMatchOrigin.manual) return 1;
    return 0;
  }

  static TmdbSeasonMetadata _mergeSeasonMetadata(
    TmdbSeasonMetadata primary,
    TmdbSeasonMetadata fallback,
  ) {
    return primary.copyWith(
      name: primary.name.trim().isNotEmpty ? primary.name : fallback.name,
      episodeCount: primary.episodeCount > 0
          ? primary.episodeCount
          : fallback.episodeCount,
      overview: primary.overview?.trim().isNotEmpty == true
          ? primary.overview
          : fallback.overview,
      airDate: primary.airDate?.trim().isNotEmpty == true
          ? primary.airDate
          : fallback.airDate,
      posterUrl: primary.posterUrl?.trim().isNotEmpty == true
          ? primary.posterUrl
          : fallback.posterUrl,
      posterCachePath: primary.posterCachePath?.trim().isNotEmpty == true
          ? primary.posterCachePath
          : fallback.posterCachePath,
      episodes: _mergeEpisodes(primary.episodes, fallback.episodes),
    );
  }

  static List<TmdbEpisodeMetadata> _mergeEpisodes(
    List<TmdbEpisodeMetadata> primary,
    List<TmdbEpisodeMetadata> fallback,
  ) {
    final byNumber = <int, TmdbEpisodeMetadata>{
      for (final episode in fallback) episode.episodeNumber: episode,
    };
    for (final episode in primary) {
      final previous = byNumber[episode.episodeNumber];
      byNumber[episode.episodeNumber] = previous == null
          ? episode
          : episode.copyWith(
              name: previous.name.trim().isNotEmpty
                  ? previous.name
                  : episode.name,
              overview: previous.overview?.trim().isNotEmpty == true
                  ? previous.overview
                  : episode.overview,
              airDate: previous.airDate?.trim().isNotEmpty == true
                  ? previous.airDate
                  : episode.airDate,
              stillUrl: previous.stillUrl?.trim().isNotEmpty == true
                  ? previous.stillUrl
                  : episode.stillUrl,
              rating: episode.rating ?? previous.rating,
            );
    }
    final result = byNumber.values.toList(growable: false)
      ..sort(
        (first, second) => first.episodeNumber.compareTo(second.episodeNumber),
      );
    return result;
  }
}

List<String> _normalizedWorkKeys(String primary, List<String>? values) {
  final result = <String>[];
  for (final value in <String>[primary, ...?values]) {
    final normalized = value.trim();
    if (normalized.isNotEmpty && !result.contains(normalized)) {
      result.add(normalized);
    }
  }
  return List<String>.unmodifiable(result);
}

class _CloudWorkAggregate {
  _CloudWorkAggregate({required this.key});

  final String key;
  final List<CloudWorkIdentity> works = <CloudWorkIdentity>[];
  final List<CloudMediaIndexItem> items = <CloudMediaIndexItem>[];
  final List<CloudWorkTmdbRecord> records = <CloudWorkTmdbRecord>[];
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
    for (var index = 0; index < videos.length; index += 1) {
      videos[index] = _withTmdbEpisodeTitle(videos[index]);
    }
    return CloudResourceMediaGroup(
      stableKey: stableKey,
      seriesName: seriesName,
      isSeries: isSeries,
      videos: videos,
      seasons: isSeries ? _buildSeasons() : const <CloudResourceSeasonGroup>[],
      record: record,
    );
  }

  /// 资源记录路径没有建立云索引时，也只替换界面标题，不改变远程身份。
  CloudFileEntry _withTmdbEpisodeTitle(CloudFileEntry entry) {
    final currentRecord = record;
    if (currentRecord?.status != CloudResourceTmdbStatus.matched) {
      return entry;
    }
    final title = currentRecord!.effectiveTitle.trim();
    final identity = identities[_entryKey(entry)];
    final seasonNumber = identity?.seasonNumber ?? entry.seasonNumber;
    final episodeNumber = identity?.episodeNumber ?? entry.episodeNumber;
    if (title.isEmpty || episodeNumber == null || episodeNumber <= 0) {
      return entry;
    }
    final episodeName = _episodeName(
      currentRecord.seasons,
      seasonNumber,
      episodeNumber,
    );
    if (episodeName == null || episodeName.trim().isEmpty) return entry;
    final displayName = const TmdbEpisodeTitleResolver().resolveWithExtension(
      seriesTitle: title,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeName: episodeName,
      originalFileName: entry.name,
    );
    if (displayName == entry.name) return entry;
    return CloudFileEntry(
      id: entry.id,
      remotePath: entry.remotePath,
      name: displayName,
      size: entry.size,
      modifiedAt: entry.modifiedAt,
      isDirectory: entry.isDirectory,
      seasonNumber: entry.seasonNumber,
      episodeNumber: entry.episodeNumber,
      variantLabel: entry.variantLabel,
      releaseTags: entry.releaseTags,
    );
  }

  String? _episodeName(
    List<TmdbSeasonMetadata> seasons,
    int? seasonNumber,
    int episodeNumber,
  ) {
    if (seasonNumber == null) return null;
    for (final season in seasons) {
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
        versions: seasonNumber == null
            ? const []
            : _buildEpisodeVersions([
                for (final video in videosBySeason[seasonNumber]!)
                  CloudFileEntry(
                    id: video.id,
                    remotePath: video.remotePath,
                    name: video.name,
                    size: video.size,
                    modifiedAt: video.modifiedAt,
                    isDirectory: false,
                    seasonNumber: seasonNumber,
                    episodeNumber:
                        identities[_entryKey(video)]?.episodeNumber ??
                            video.episodeNumber,
                    variantLabel: video.variantLabel,
                    releaseTags: video.releaseTags,
                  ),
              ], originFor: (_) => '$stableKey|season:$seasonNumber'),
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

List<CloudResourceVersionGroup> _buildEpisodeVersions(
  List<CloudFileEntry> videos, {
  required String Function(CloudFileEntry) originFor,
  String Function(CloudFileEntry)? directoryFor,
}) {
  final roots = <String, List<CloudFileEntry>>{};
  final specsByEntry = {
    for (final video in videos) _entryKey(video): _versionSpecs(video)
  };
  for (final video in videos) {
    roots.putIfAbsent(originFor(video), () => []).add(video);
  }
  final buckets = <String, List<CloudFileEntry>>{};
  for (final root in roots.entries) {
    final directories = <String, List<CloudFileEntry>>{};
    final episodeDirectories = <int, Set<String>>{};
    for (final video in root.value) {
      final directory = directoryFor?.call(video) ??
          p.posix.dirname(video.remotePath.replaceAll('\\', '/'));
      directories.putIfAbsent(directory, () => []).add(video);
      final number = video.episodeNumber;
      if (number != null && number > 0) {
        episodeDirectories.putIfAbsent(number, () => {}).add(directory);
      }
    }
    final splitDirectories =
        episodeDirectories.values.any((dirs) => dirs.length > 1);
    for (final directory
        in (splitDirectories ? directories : {'': root.value}).entries) {
      final prefix = '${root.key}|directory:${directory.key}';
      final byEpisode = <int, List<CloudFileEntry>>{};
      for (final video in directory.value) {
        final number = video.episodeNumber;
        if (number != null && number > 0) {
          byEpisode.putIfAbsent(number, () => []).add(video);
        }
      }
      // 仅同集的明确规格冲突触发拆版，单集缺标签不建立新版本。
      final dimensions = <int>[];
      for (var index = 0; index < 8; index++) {
        if (byEpisode.values.any((entries) =>
            entries
                .map((video) => specsByEntry[_entryKey(video)]![index])
                .where((value) => value.isNotEmpty)
                .toSet()
                .length >
            1)) {
          dimensions.add(index);
        }
      }
      final known = <String, List<CloudFileEntry>>{};
      final unspecified = <CloudFileEntry>[];
      for (final video in directory.value) {
        final specs = specsByEntry[_entryKey(video)]!;
        final signature = dimensions.map((index) => specs[index]).join('|');
        if (dimensions.any((index) => specs[index].isEmpty)) {
          unspecified.add(video);
        } else {
          known.putIfAbsent(signature, () => []).add(video);
        }
      }
      if (known.isEmpty) {
        // 规格互相缺失、没有完整签名时不猜测所属版本。
        buckets['$prefix|spec:'] = directory.value;
        continue;
      }
      final signatures = known.keys.toList()..sort();
      for (final video in unspecified) {
        final specs = specsByEntry[_entryKey(video)]!;
        final compatible = signatures.where((signature) {
          final values = signature.split('|');
          return List.generate(dimensions.length, (index) => index).every(
            (index) =>
                specs[dimensions[index]].isEmpty ||
                specs[dimensions[index]] == values[index],
          );
        });
        known[compatible.firstOrNull ?? signatures.first]!.add(video);
      }
      for (final signature in signatures) {
        buckets['$prefix|spec:$signature'] = known[signature]!;
      }
    }
  }
  if (buckets.length < 2) return const [];
  final keys = buckets.keys.toList()..sort();
  final labels = <String, String>{};
  for (var index = 0; index < keys.length; index++) {
    final key = keys[index];
    final directory = key.split('|directory:').last.split('|spec:').first;
    final spec = key.split('|spec:').last.replaceAll('|', ' · ');
    labels[key] = [
      '版本 ${index + 1}',
      if (directory.isNotEmpty) p.posix.basename(directory),
      if (spec.isNotEmpty) spec,
    ].join(' · ');
  }
  return [
    for (final key in keys)
      CloudResourceVersionGroup(
        key: key,
        label: labels[key]!,
        videos: () {
          final ownNumbers =
              buckets[key]!.map((video) => video.episodeNumber).toSet();
          final entries = <CloudFileEntry>[
            for (final owner in keys)
              for (final video in buckets[owner]!)
                if (owner == key ||
                    (video.episodeNumber != null &&
                        video.episodeNumber! > 0 &&
                        !ownNumbers.contains(video.episodeNumber)))
                  CloudFileEntry(
                    id: video.id,
                    remotePath: video.remotePath,
                    name: video.name,
                    size: video.size,
                    modifiedAt: video.modifiedAt,
                    isDirectory: video.isDirectory,
                    seasonNumber: video.seasonNumber,
                    episodeNumber: video.episodeNumber,
                    variantLabel: video.variantLabel,
                    releaseTags: video.releaseTags,
                    playbackVersionKey: key,
                    isShared: owner != key,
                    sharedFromVersionLabel: owner == key ? null : labels[owner],
                  ),
          ]..sort((first, second) {
              final number = (first.episodeNumber ?? (1 << 30))
                  .compareTo(second.episodeNumber ?? (1 << 30));
              if (number != 0) return number;
              final path = first.remotePath.compareTo(second.remotePath);
              return path != 0 ? path : first.id.compareTo(second.id);
            });
          return entries;
        }(),
      ),
  ];
}

List<String> _versionSpecs(CloudFileEntry video) {
  final tags = video.releaseTags;
  final originalTags = const MediaNameAnalyzer()
      .analyze(
        p.posix.basename(video.remotePath.replaceAll('\\', '/')),
        isDirectory: false,
      )
      .releaseTags;
  String normalize(String? value) {
    final token =
        (value ?? '').toUpperCase().replaceAll(RegExp(r'[\s._-]'), '');
    return switch (token) {
      '4K' || 'UHD' => '2160P',
      'H265' || 'X265' => 'HEVC',
      'H264' || 'X264' => 'AVC',
      _ => token,
    };
  }

  final ranges = (tags.dynamicRange.isNotEmpty
          ? tags.dynamicRange
          : originalTags.dynamicRange)
      .map(normalize)
      .toSet()
      .toList()
    ..sort();
  String normalizeList(List<String> values) {
    final sorted = values.map(normalize).toSet().toList()..sort();
    return sorted.join('+');
  }

  return [
    normalize(tags.resolution ?? originalTags.resolution),
    normalize(tags.source ?? originalTags.source),
    normalize(tags.codec ?? originalTags.codec),
    ranges.isEmpty ? '普通' : ranges.join('+'),
    normalize(tags.releaseGroup ?? originalTags.releaseGroup),
    normalize(tags.bitrate ?? originalTags.bitrate),
    normalizeList(tags.audio.isNotEmpty ? tags.audio : originalTags.audio),
    normalizeList(
        tags.subtitles.isNotEmpty ? tags.subtitles : originalTags.subtitles),
  ];
}

String _versionDirectory(CloudMediaIndexItem item) {
  final parent = p.posix.dirname(item.remotePath.replaceAll('\\', '/'));
  final root = item.workRootPath?.replaceAll('\\', '/');
  if (root == null || !p.posix.isWithin(root, parent)) return parent;
  final parts = p.posix.split(p.posix.relative(parent, from: root));
  // 按版本目录归并其下的季度、逐集子目录，避免一套资源被拆成很多版本。
  final versionParts = parts
      .where((part) => !RegExp(
            r'^(?:S\d+|Season[ ._-]*\d+|第?[\d一二三四五六七八九十]+季)$',
            caseSensitive: false,
          ).hasMatch(part))
      .toList();
  return versionParts.isEmpty ? root : p.posix.join(root, versionParts.first);
}
