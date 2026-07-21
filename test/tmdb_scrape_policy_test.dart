import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  const policy = TmdbScrapePolicy();

  test('统一清理季集和发布规格并去重标题候选', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'same-work',
      titleCandidates: <String>[
        '三体 S01 2160p WEB-DL',
        '三体 第一季',
        '三体【内嵌中字】',
      ],
      year: 2023,
      seasonNumbers: <int>{1},
      episodeNumbers: <int>{1, 2},
      mediaEvidence: TmdbMediaEvidence.tv,
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(plan.queries, <String>['三体']);
    expect(plan.year, 2023);
    expect(plan.mediaTypes, <TmdbMediaType>[TmdbMediaType.tv]);
  });

  test('未显式提供年份时从标题中提取且不保留在搜索词', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'movie',
      titleCandidates: <String>['流浪地球 (2019) BluRay 1080p'],
      mediaEvidence: TmdbMediaEvidence.movie,
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(plan.queries, <String>['流浪地球']);
    expect(plan.year, 2019);
    expect(plan.mediaTypes, <TmdbMediaType>[TmdbMediaType.movie]);
  });

  test('显式媒体类型设置覆盖自动识别证据', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'forced',
      titleCandidates: <String>['三体 S01E01'],
      seasonNumbers: <int>{1},
      episodeNumbers: <int>{1},
      mediaEvidence: TmdbMediaEvidence.tv,
    );
    const movieOptions = TmdbScrapeOptions(
      language: 'zh-CN',
      mediaTypeMode: TmdbMediaTypeMode.movie,
      confidenceMode: TmdbConfidenceMode.standard,
      overwriteTitle: false,
      overwriteOverview: true,
      overwritePoster: true,
      fetchPoster: true,
      fetchBackdrop: true,
    );

    final plan = policy.build(subject, movieOptions);

    expect(plan.mediaTypes, <TmdbMediaType>[TmdbMediaType.movie]);
  });

  test('自动模式有季集证据时统一只搜索电视剧', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'episode',
      titleCandidates: <String>['Show'],
      episodeNumbers: <int>{1},
      mediaEvidence: TmdbMediaEvidence.unknown,
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(plan.mediaTypes, <TmdbMediaType>[TmdbMediaType.tv]);
  });

  test('自动模式无法判断时按稳定顺序同时搜索电影和电视剧', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'unknown',
      titleCandidates: <String>['同名作品'],
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(
      plan.mediaTypes,
      <TmdbMediaType>[TmdbMediaType.movie, TmdbMediaType.tv],
    );
  });
}
