import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

/// 集中处理本地媒体库的 TMDB 设置和自动刮削决策。
class LocalLibraryTmdbCoordinator {
  const LocalLibraryTmdbCoordinator({
    required String Function() apiKeyProvider,
    required TmdbScrapeOptions Function() optionsProvider,
    required bool Function() autoScrapeProvider,
  })  : _apiKeyProvider = apiKeyProvider,
        _optionsProvider = optionsProvider,
        _autoScrapeProvider = autoScrapeProvider;

  final String Function() _apiKeyProvider;
  final TmdbScrapeOptions Function() _optionsProvider;
  final bool Function() _autoScrapeProvider;

  TmdbScrapeOptions get options {
    try {
      return _optionsProvider();
    } on Object {
      return const TmdbScrapeOptions.defaults();
    }
  }

  Set<String> unmatchedSeriesNames(Iterable<LocalMediaIndexItem> items) => items
      .where(
        (item) =>
            item.tmdb == null || item.scrapeStatus != TmdbScrapeStatus.matched,
      )
      .map((item) => item.seriesName.trim())
      .where((name) => name.isNotEmpty)
      .toSet();

  bool shouldAutoScrape(Iterable<LocalMediaIndexItem> items) {
    try {
      return _autoScrapeProvider() &&
          _apiKeyProvider().trim().isNotEmpty &&
          unmatchedSeriesNames(items).isNotEmpty;
    } on Object {
      return false;
    }
  }
}
