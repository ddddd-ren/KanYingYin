import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

void main() {
  test('默认刮削选项使用中文、自动类型和标准置信度', () {
    const options = TmdbScrapeOptions.defaults();
    expect(options.language, 'zh-CN');
    expect(options.mediaTypeMode, TmdbMediaTypeMode.auto);
    expect(options.confidenceMode, TmdbConfidenceMode.standard);
    expect(options.minimumScore, 0.8);
    expect(options.minimumLead, 0.1);
    expect(options.maximumSearchPages, 3);
    expect(options.maximumAliasCandidates, 20);
    expect(options.scrapeEpisodeNames, isTrue);
  });

  test('刮削选项序列化往返保留全部开关', () {
    const options = TmdbScrapeOptions(
      language: 'en-US',
      mediaTypeMode: TmdbMediaTypeMode.movie,
      confidenceMode: TmdbConfidenceMode.strict,
      overwriteTitle: true,
      overwriteOverview: false,
      overwritePoster: false,
      scrapeEpisodeNames: false,
      fetchPoster: false,
      fetchBackdrop: false,
      maximumSearchPages: 5,
      maximumAliasCandidates: 12,
    );
    expect(TmdbScrapeOptions.fromMap(options.toMap()).toMap(), options.toMap());
  });

  test('旧配置缺少逐集名称字段时默认开启', () {
    final options = TmdbScrapeOptions.fromMap(const <String, Object?>{});
    expect(options.scrapeEpisodeNames, isTrue);
  });
}
