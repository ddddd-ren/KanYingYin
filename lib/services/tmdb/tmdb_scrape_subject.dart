import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

const int currentTmdbRuleVersion = 1;

enum TmdbMediaEvidence { movie, tv, unknown }

enum TmdbMatchOrigin { automatic, manual, legacyUnknown }

class TmdbFieldLocks {
  const TmdbFieldLocks({
    this.title = false,
    this.overview = false,
    this.poster = false,
  });

  final bool title;
  final bool overview;
  final bool poster;
}

class TmdbScrapeSubject {
  const TmdbScrapeSubject({
    required this.stableKey,
    required this.titleCandidates,
    this.year,
    this.seasonNumbers = const <int>{},
    this.episodeNumbers = const <int>{},
    this.mediaEvidence = TmdbMediaEvidence.unknown,
    this.existingMetadata,
    this.fieldLocks = const TmdbFieldLocks(),
    this.matchOrigin = TmdbMatchOrigin.legacyUnknown,
    this.ruleVersion = 0,
  });

  final String stableKey;
  final List<String> titleCandidates;
  final int? year;
  final Set<int> seasonNumbers;
  final Set<int> episodeNumbers;
  final TmdbMediaEvidence mediaEvidence;
  final TmdbMetadata? existingMetadata;
  final TmdbFieldLocks fieldLocks;
  final TmdbMatchOrigin matchOrigin;
  final int ruleVersion;
}
