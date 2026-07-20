import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';

@immutable
class CloudEpisodeIdentity {
  const CloudEpisodeIdentity({
    required this.entry,
    required this.remoteName,
    required this.displayName,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.releaseTags,
  });

  final CloudFileEntry entry;
  final String remoteName;
  final String displayName;
  final int seasonNumber;
  final int episodeNumber;
  final MediaReleaseTags releaseTags;
}

@immutable
class CloudSeasonIdentity {
  const CloudSeasonIdentity({
    required this.workKey,
    required this.seasonNumber,
    required this.displayName,
    required this.remoteDirectories,
    required this.episodes,
    this.year,
  });

  final String workKey;
  final int seasonNumber;
  final String displayName;
  final List<CloudFileEntry> remoteDirectories;
  final List<CloudEpisodeIdentity> episodes;
  final int? year;
}

@immutable
class CloudWorkIdentity {
  const CloudWorkIdentity({
    required this.sourceId,
    required this.workKey,
    required this.root,
    required this.remoteName,
    required this.displayTitle,
    required this.titleCandidates,
    required this.seasons,
    this.standaloneVideos = const <CloudFileEntry>[],
  });

  final String sourceId;
  final String workKey;
  final CloudFileEntry root;
  final String remoteName;
  final String displayTitle;
  final List<String> titleCandidates;
  final List<CloudSeasonIdentity> seasons;
  final List<CloudFileEntry> standaloneVideos;
}

@immutable
class CloudMediaTreeConflict {
  const CloudMediaTreeConflict({
    required this.entry,
    required this.folderSeasonNumber,
    required this.detectedSeasonNumber,
  });

  final CloudFileEntry entry;
  final int folderSeasonNumber;
  final int detectedSeasonNumber;
}

@immutable
class CloudMediaTree {
  const CloudMediaTree({
    required this.sourceId,
    required this.works,
    required this.ignored,
    required this.conflicts,
  });

  final String sourceId;
  final List<CloudWorkIdentity> works;
  final List<CloudFileEntry> ignored;
  final List<CloudMediaTreeConflict> conflicts;
}
