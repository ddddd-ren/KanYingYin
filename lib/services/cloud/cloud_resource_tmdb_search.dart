import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';

typedef CloudResourceTmdbSearchRequest = TmdbPreparedSearchRequest;
typedef CloudResourceTmdbSearchOutcome = TmdbPreparedSearchOutcome;

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
