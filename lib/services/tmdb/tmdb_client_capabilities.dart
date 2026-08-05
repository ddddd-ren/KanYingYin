import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

abstract interface class ITmdbClientCapabilities {
  Future<TmdbSearchPage> searchPage(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
    required int page,
  });

  Future<List<String>> alternativeTitles(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  });

  Future<TmdbSeasonMetadata> seasonDetails(
    int id,
    int seasonNumber, {
    String language = 'zh-CN',
  });
}

class TmdbSearchPage {
  const TmdbSearchPage({
    required this.page,
    required this.totalPages,
    required this.results,
  });

  final int page;
  final int totalPages;
  final List<TmdbMetadata> results;
}
