import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

class CloudTmdbSubjectBuilder {
  const CloudTmdbSubjectBuilder();

  TmdbScrapeSubject forWork(
    CloudWorkIdentity work, {
    CloudWorkTmdbRecord? record,
  }) {
    final candidates = <String>[];
    _addCandidate(candidates, record?.scrapeTitleOverride);
    for (final candidate in work.titleCandidates) {
      _addCandidate(candidates, candidate);
    }
    _addCandidate(candidates, work.displayTitle);
    _addCandidate(candidates, work.remoteName);

    final seasons = work.seasons
        .map((season) => season.seasonNumber)
        .where((number) => number > 0)
        .toSet();
    final episodes = work.seasons
        .expand((season) => season.episodes)
        .map((episode) => episode.episodeNumber)
        .where((number) => number > 0)
        .toSet();

    return TmdbScrapeSubject(
      stableKey: work.workKey,
      titleCandidates: candidates,
      year: work.seasons.map((season) => season.year).nonNulls.firstOrNull,
      seasonNumbers: seasons,
      episodeNumbers: episodes,
      mediaEvidence: seasons.isNotEmpty || episodes.isNotEmpty
          ? TmdbMediaEvidence.tv
          : work.standaloneVideos.length == 1
              ? TmdbMediaEvidence.movie
              : TmdbMediaEvidence.unknown,
      existingMetadata: record?.metadata,
      fieldLocks: TmdbFieldLocks(title: record?.scrapeTitleOverride != null),
      matchOrigin: record?.tmdbMatchOrigin ?? TmdbMatchOrigin.legacyUnknown,
      ruleVersion: record?.tmdbRuleVersion ?? 0,
    );
  }

  TmdbScrapeSubject forResource(
    CloudResourceTmdbTarget target, {
    CloudResourceTmdbRecord? record,
  }) {
    final candidates = <String>[];
    _addCandidate(candidates, target.customTitle);
    _addCandidate(candidates, target.matchingTitle);
    _addCandidate(candidates, target.displayName);
    final season = target.matchingSeasonNumber;
    final episode = target.matchingEpisodeNumber;
    final hasEpisodeEvidence =
        (season != null && season > 0) || (episode != null && episode > 0);

    return TmdbScrapeSubject(
      stableKey: target.stableKey,
      titleCandidates: candidates,
      seasonNumbers:
          season != null && season > 0 ? <int>{season} : const <int>{},
      episodeNumbers:
          episode != null && episode > 0 ? <int>{episode} : const <int>{},
      mediaEvidence: hasEpisodeEvidence
          ? TmdbMediaEvidence.tv
          : target.resourceKind == CloudResourceKind.standaloneVideo
              ? TmdbMediaEvidence.movie
              : TmdbMediaEvidence.unknown,
      existingMetadata: record == null ? null : _metadataFromResource(record),
      fieldLocks: TmdbFieldLocks(title: target.customTitle != null),
      matchOrigin: record?.tmdbMatchOrigin ?? TmdbMatchOrigin.legacyUnknown,
      ruleVersion: record?.tmdbRuleVersion ?? 0,
    );
  }
}

void _addCandidate(List<String> candidates, String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return;
  if (candidates.any(
    (candidate) => candidate.toLowerCase() == normalized.toLowerCase(),
  )) {
    return;
  }
  candidates.add(normalized);
}

TmdbMetadata? _metadataFromResource(CloudResourceTmdbRecord record) {
  final id = record.tmdbId;
  final mediaType = record.mediaType;
  final title = record.title;
  if (id == null ||
      mediaType == null ||
      title == null ||
      title.trim().isEmpty) {
    return null;
  }
  return TmdbMetadata(
    id: id,
    mediaType: mediaType,
    title: title,
    originalTitle: record.originalTitle,
    overview: record.overview,
    releaseDate: record.releaseDate,
    rating: record.rating,
    posterUrl: record.posterUrl,
    backdropUrl: record.backdropUrl,
    language: 'zh-CN',
    matchedAt: record.checkedAt,
    matchConfidence: 1,
    seasons: record.seasons,
  );
}
