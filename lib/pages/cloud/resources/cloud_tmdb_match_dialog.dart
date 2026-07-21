import 'package:kanyingyin/pages/tmdb_match_dialog.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';

export 'package:kanyingyin/pages/tmdb_match_dialog.dart';

typedef CloudTmdbSearchCallback = TmdbMatchSearchCallback;
typedef CloudTmdbApplyCallback
    = TmdbMatchApplyCallback<CloudResourceTmdbSelectionOutcome>;
typedef CloudTmdbMatchDialog
    = TmdbMatchDialog<CloudResourceTmdbSelectionOutcome>;
