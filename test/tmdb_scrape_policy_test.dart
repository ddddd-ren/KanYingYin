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

  test('电视剧标题末尾的当前季度数字会从搜索词中移除', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'isekai-nonbiri-s02',
      titleCandidates: <String>['Isekai Nonbiri Nouka 2'],
      seasonNumbers: <int>{2},
      mediaEvidence: TmdbMediaEvidence.tv,
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(plan.queries, <String>['Isekai Nonbiri Nouka']);
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

  test('本地搜索计划清除与网盘相同的完整发布标签', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'movie-release-name',
      titleCandidates: <String>[
        '流浪地球2.2160p.REMUX.DV.HDR10+.H.265.TrueHD.7.1.Atmos.mkv',
      ],
      mediaEvidence: TmdbMediaEvidence.movie,
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(plan.queries, <String>['流浪地球2']);
  });

  test('本地搜索计划清理发布站尾缀并保留年份筛选', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'release-title',
      titleCandidates: <String>[
        '片名【高清剧集网发布 www.DDHDTV.com】第二季[全6集][简繁英字幕].S02.2014.1080p.BluRay.x264.FLAC.2.0-ZeroTV',
      ],
      seasonNumbers: <int>{2},
      mediaEvidence: TmdbMediaEvidence.tv,
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(plan.queries, <String>['片名']);
    expect(plan.year, 2014);
    expect(plan.mediaTypes, <TmdbMediaType>[TmdbMediaType.tv]);
  });

  test('本地搜索计划清理 REMUX 版本杜比视界和多音轨后缀', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'remux-release-title',
      titleCandidates: <String>[
        '流浪地球 V3 UHD REMUX DoVi TrueHD7 1 14Audio.mkv',
      ],
      mediaEvidence: TmdbMediaEvidence.movie,
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(plan.queries, <String>['流浪地球']);
  });

  test('纯年份数字作品名不会被清空', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'numeric-title',
      titleCandidates: <String>['1923'],
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(plan.queries, <String>['1923']);
    expect(plan.year, 1923);
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
      scrapeEpisodeNames: true,
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

  test('手动搜索词优先于清洗后的主标题和其他候选', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'manual',
      manualSearchTitle: 'The Three Body Problem',
      titleCandidates: <String>['三体 S01E01', 'The Three-Body Problem'],
      mediaEvidence: TmdbMediaEvidence.tv,
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(plan.queries, <String>['The Three Body Problem', '三体']);
  });

  test('电视剧季集证据清除独立数字集号', () {
    const subject = TmdbScrapeSubject(
      stableKey: 'numeric-episode',
      titleCandidates: <String>['权力的游戏 S03 09'],
      seasonNumbers: <int>{3},
      episodeNumbers: <int>{9},
      mediaEvidence: TmdbMediaEvidence.tv,
    );

    final plan = policy.build(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(plan.queries, <String>['权力的游戏']);
  });
}
