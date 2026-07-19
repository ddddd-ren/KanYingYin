import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

class CloudResourceTmdbSearchRequest {
  const CloudResourceTmdbSearchRequest({
    required this.queryTitle,
    required this.mediaTypeMode,
    required this.options,
    this.queryYear,
  });

  final String queryTitle;
  final TmdbMediaTypeMode mediaTypeMode;
  final TmdbScrapeOptions options;
  final int? queryYear;
}

class CloudResourceTmdbSearchOutcome {
  const CloudResourceTmdbSearchOutcome({required this.ranked});

  final TmdbRankedResult ranked;
}

class CloudSeriesPropagationSummary {
  const CloudSeriesPropagationSummary({
    required this.eligible,
    required this.ruleSaved,
    required this.propagatedCount,
    required this.indexSyncFailures,
  });

  const CloudSeriesPropagationSummary.none()
      : eligible = false,
        ruleSaved = true,
        propagatedCount = 0,
        indexSyncFailures = 0;

  final bool eligible;
  final bool ruleSaved;
  final int propagatedCount;
  final int indexSyncFailures;
}

class CloudResourceTmdbSelectionOutcome {
  const CloudResourceTmdbSelectionOutcome({
    required this.record,
    required this.posterCached,
    required this.indexSynced,
    this.seriesPropagation = const CloudSeriesPropagationSummary.none(),
  });

  final CloudResourceTmdbRecord record;
  final bool posterCached;
  final bool indexSynced;
  final CloudSeriesPropagationSummary seriesPropagation;
}
