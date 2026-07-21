import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:path/path.dart' as p;

class LocalTmdbSubjectBuilder {
  const LocalTmdbSubjectBuilder();

  TmdbScrapeSubject build({
    required String seriesName,
    required List<LocalMediaIndexItem> items,
  }) {
    final candidates = <String>[];
    void addCandidate(String? value) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) return;
      if (candidates.any(
        (current) => current.toLowerCase() == normalized.toLowerCase(),
      )) {
        return;
      }
      candidates.add(normalized);
    }

    addCandidate(seriesName);
    for (final item in items) {
      addCandidate(item.seriesName);
      if (p.normalize(item.parentPath) != p.normalize(item.sourcePath)) {
        addCandidate(p.basename(item.parentPath));
      }
      addCandidate(p.basenameWithoutExtension(item.name));
    }

    final seasons = items
        .map((item) => item.seasonNumber)
        .whereType<int>()
        .where((value) => value > 0)
        .toSet();
    final episodes = items
        .map((item) => item.episodeNumber)
        .whereType<int>()
        .where((value) => value > 0)
        .toSet();
    final origins = items.map((item) => item.tmdbMatchOrigin).toSet();
    final versions = items.map((item) => item.tmdbRuleVersion).toList();

    return TmdbScrapeSubject(
      stableKey: seriesName.trim().toLowerCase(),
      titleCandidates: candidates,
      seasonNumbers: seasons,
      episodeNumbers: episodes,
      mediaEvidence: seasons.isNotEmpty || episodes.isNotEmpty
          ? TmdbMediaEvidence.tv
          : items.length == 1
              ? TmdbMediaEvidence.movie
              : TmdbMediaEvidence.unknown,
      existingMetadata: items.map((item) => item.tmdb).nonNulls.firstOrNull,
      fieldLocks: TmdbFieldLocks(
        title: items.any((item) => item.titleLocked),
        overview: items.any((item) => item.overviewLocked),
        poster: items.any((item) => item.posterLocked),
      ),
      matchOrigin: origins.contains(TmdbMatchOrigin.manual)
          ? TmdbMatchOrigin.manual
          : origins.length == 1 && origins.first == TmdbMatchOrigin.automatic
              ? TmdbMatchOrigin.automatic
              : TmdbMatchOrigin.legacyUnknown,
      ruleVersion: versions.isEmpty
          ? 0
          : versions.reduce((left, right) => left < right ? left : right),
    );
  }
}
