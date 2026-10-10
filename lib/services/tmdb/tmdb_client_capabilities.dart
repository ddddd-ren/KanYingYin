import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/local/tmdb_image_metadata.dart';

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

/// TMDB 图片接口的可选能力，独立于基础客户端接口，避免破坏现有测试客户端。
abstract interface class ITmdbImageCapabilities {
  Future<TmdbImageSet> images(
    int id,
    TmdbMediaType mediaType, {
    int? seasonNumber,
    int? episodeNumber,
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
