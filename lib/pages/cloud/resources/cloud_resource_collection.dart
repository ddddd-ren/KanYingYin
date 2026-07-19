import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/services/cloud/cloud_series_identity_resolver.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:path/path.dart' as p;

class CloudResourceCollection {
  CloudResourceCollection({
    required List<CloudFileEntry> folders,
    required List<CloudResourceMediaGroup> groups,
  })  : folders = List<CloudFileEntry>.unmodifiable(folders),
        groups = List<CloudResourceMediaGroup>.unmodifiable(groups);

  final List<CloudFileEntry> folders;
  final List<CloudResourceMediaGroup> groups;
}

class CloudResourceMediaGroup {
  CloudResourceMediaGroup({
    required this.stableKey,
    required this.seriesName,
    required this.isSeries,
    required List<CloudFileEntry> videos,
    required this.record,
  }) : videos = List<CloudFileEntry>.unmodifiable(videos);

  final String stableKey;
  final String seriesName;
  final bool isSeries;
  final List<CloudFileEntry> videos;
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
    final keyword = query.trim().toLowerCase();
    final folders = entries
        .where(
          (entry) =>
              entry.isDirectory &&
              (keyword.isEmpty || entry.name.toLowerCase().contains(keyword)),
        )
        .toList(growable: false)
      ..sort(_compareEntriesByName);
    final builders = <String, _CloudResourceMediaGroupBuilder>{};
    for (final entry in entries) {
      if (entry.isDirectory ||
          !LocalVideoFileTypes.isRecognizedVideo(
            entry.name,
            size: entry.size,
            minSizeBytes: minSizeBytes,
          )) {
        continue;
      }
      final identity = _identityResolver.resolve(
        sourceId: sourceId,
        remotePath: entry.remotePath,
        size: entry.size,
        minSizeBytes: minSizeBytes,
      );
      final resourceKey = cloudResourceTmdbKey(
        sourceId: sourceId,
        remoteId: entry.id,
        remotePath: entry.remotePath,
      );
      final stableKey = identity?.stableKey ?? resourceKey;
      final builder = builders.putIfAbsent(
        stableKey,
        () => _CloudResourceMediaGroupBuilder(
          stableKey: stableKey,
          seriesName: identity?.seriesName.trim().isNotEmpty == true
              ? identity!.seriesName.trim()
              : p.basenameWithoutExtension(entry.name),
          isSeries: identity != null,
        ),
      );
      builder
        ..videos.add(entry)
        ..considerRecord(records[resourceKey]);
    }

    final groups = <CloudResourceMediaGroup>[];
    for (final builder in builders.values) {
      builder.videos.sort((first, second) {
        if (!builder.isSeries) return _compareEntriesByName(first, second);
        final firstIdentity = _identityResolver.resolve(
          sourceId: sourceId,
          remotePath: first.remotePath,
          size: first.size,
          minSizeBytes: minSizeBytes,
        );
        final secondIdentity = _identityResolver.resolve(
          sourceId: sourceId,
          remotePath: second.remotePath,
          size: second.size,
          minSizeBytes: minSizeBytes,
        );
        final season = (firstIdentity?.seasonNumber ?? 0)
            .compareTo(secondIdentity?.seasonNumber ?? 0);
        if (season != 0) return season;
        final episode = (firstIdentity?.episodeNumber ?? 0)
            .compareTo(secondIdentity?.episodeNumber ?? 0);
        return episode != 0 ? episode : _compareEntriesByName(first, second);
      });
      final group = builder.build();
      if (_matches(group, keyword)) groups.add(group);
    }
    groups.sort((first, second) {
      final firstTitle = first.record?.effectiveTitle ?? first.seriesName;
      final secondTitle = second.record?.effectiveTitle ?? second.seriesName;
      return firstTitle.toLowerCase().compareTo(secondTitle.toLowerCase());
    });
    return CloudResourceCollection(folders: folders, groups: groups);
  }

  static bool _matches(CloudResourceMediaGroup group, String keyword) {
    if (keyword.isEmpty) return true;
    final title = group.record?.effectiveTitle ?? group.seriesName;
    return title.toLowerCase().contains(keyword) ||
        group.seriesName.toLowerCase().contains(keyword) ||
        group.stableKey.toLowerCase().contains(keyword) ||
        group.videos.any(
          (video) => video.name.toLowerCase().contains(keyword),
        );
  }

  static int _compareEntriesByName(
    CloudFileEntry first,
    CloudFileEntry second,
  ) =>
      first.name.toLowerCase().compareTo(second.name.toLowerCase());
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
  CloudResourceTmdbRecord? record;
  int _recordPriority = -1;

  void considerRecord(CloudResourceTmdbRecord? candidate) {
    final priority = _priority(candidate);
    if (priority <= _recordPriority) return;
    record = candidate;
    _recordPriority = priority;
  }

  CloudResourceMediaGroup build() => CloudResourceMediaGroup(
        stableKey: stableKey,
        seriesName: seriesName,
        isSeries: isSeries,
        videos: videos,
        record: record,
      );

  static int _priority(CloudResourceTmdbRecord? candidate) {
    if (candidate == null) return -1;
    final customTitle = candidate.customTitle?.trim();
    if (customTitle != null && customTitle.isNotEmpty) return 2;
    if (candidate.status == CloudResourceTmdbStatus.matched) return 1;
    return -1;
  }
}
