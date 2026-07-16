import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_episode_info.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';

void main() {
  test('LocalSeriesGrouper uses the manual series title override', () {
    final groups = const LocalSeriesGrouper().group([
      LocalFileItem(
        path: r'D:\Anime\Show\Show S01E01.mkv',
        name: 'Show S01E01.mkv',
        size: 1,
        modified: DateTime(2026),
        isDirectory: false,
        isVideo: true,
        seriesTitleOverride: '我喜欢的剧名',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show',
          episodeNumber: 1,
        ),
      ),
    ]);

    expect(groups.single.title, '我喜欢的剧名');
  });

  test('LocalSeriesGrouper 保留同系列剧场版的完整剧名覆盖', () {
    const fullTitle = '剧场版 假面骑士OOO：精彩绝伦 将军与21枚核心硬币';
    final groups = const LocalSeriesGrouper().group([
      _video(
        path: r'D:\a TV\假面骑士OOO\假面骑士OOO 第01集.mkv',
        name: '假面骑士OOO 第01集.mkv',
        seriesName: '假面骑士OOO',
        episodeNumber: 1,
      ),
      _video(
        path:
            r'D:\a TV\剧场版 假面骑士OOO：精彩绝伦 将军与21枚核心硬币\剧场版 假面骑士OOO：精彩绝伦 将军与21枚核心硬币.mkv',
        name: '剧场版 假面骑士OOO：精彩绝伦 将军与21枚核心硬币.mkv',
        seriesTitleOverride: fullTitle,
      ),
    ]);

    expect(groups, hasLength(2));
    expect(groups.last.title, fullTitle);
  });

  test('LocalSeriesGrouper separates seasons and movies', () {
    final groups = const LocalSeriesGrouper().group([
      _video(
        path: r'D:\Anime\Root\ShowA\ShowA S01E02.mkv',
        name: 'ShowA S01E02.mkv',
        seriesName: 'ShowA',
        seasonNumber: 1,
        episodeNumber: 2,
      ),
      _video(
        path: r'D:\Anime\Root\ShowA\ShowA S01E01.mkv',
        name: 'ShowA S01E01.mkv',
        seriesName: 'ShowA',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\Anime\Root\ShowA S02\ShowA S02E01.mkv',
        name: 'ShowA S02E01.mkv',
        seriesName: 'ShowA S02',
        seasonNumber: 2,
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\Anime\Root\ShowA Movie\ShowA Movie.mkv',
        name: 'ShowA Movie.mkv',
        seriesName: 'ShowA Movie',
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\Anime\Root\ShowB\ShowB S01E01.mkv',
        name: 'ShowB S01E01.mkv',
        seriesName: 'ShowB',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    ]);

    expect(groups.length, 4);
    expect(groups.first.title, 'ShowA S01');
    expect(groups.first.episodeCount, 2);
    expect(groups.first.episodes.map((item) => item.name), [
      'ShowA S01E01.mkv',
      'ShowA S01E02.mkv',
    ]);
    expect(groups[1].title, 'ShowA S02');
    expect(groups[2].title, 'ShowA 剧场版');
    expect(groups[3].title, 'ShowB S01');
  });

  test('LocalSeriesGrouper separates sequels and movie titles', () {
    final groups = const LocalSeriesGrouper().group([
      _video(
        path: r'D:\Anime\Root\危笑\危笑.mkv',
        name: '危笑.mkv',
        seriesName: '危笑',
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\Anime\Root\危笑2\危笑2.mkv',
        name: '危笑2.mkv',
        seriesName: '危笑2',
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\Anime\Root\命运石之门\命运石之门.mkv',
        name: '命运石之门.mkv',
        seriesName: '命运石之门',
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\Anime\Root\命运石之门 剧场版\movie.mkv',
        name: 'movie.mkv',
        seriesName: '剧场版 命运石之门 负荷领域的既视感',
        episodeNumber: 1,
      ),
    ]);

    expect(groups.length, 4);
    expect(groups.map((group) => group.title), [
      '危笑',
      '危笑 2',
      '命运石之门',
      '命运石之门 剧场版',
    ]);
    expect(groups.map((group) => group.episodeCount), [1, 1, 1, 1]);
  });

  test('LocalSeriesGrouper separates release variants by season and type', () {
    final groups = const LocalSeriesGrouper().group([
      _video(
        path: r'D:\Anime\Root\中二病也要谈恋爱\NW 中二病也要谈恋爱！ 第一季 第01集.mkv',
        name: 'NW 中二病也要谈恋爱！ 第一季 第01集.mkv',
        seriesName: 'NW 中二病也要谈恋爱',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\Anime\Root\中二病也要谈恋爱 恋\NW 中二病也要谈恋爱！恋 第01集.mkv',
        name: 'NW 中二病也要谈恋爱！恋 第01集.mkv',
        seriesName: 'NW 中二病也要谈恋爱 恋',
        seasonNumber: 2,
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\Anime\Root\小鸟游六花・改\movie.mkv',
        name: 'movie.mkv',
        seriesName: '剧场版 中二病也要谈恋爱 小鸟游六花・改',
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\Anime\Root\中二病也要谈恋爱\第1季\[4K_NW] 中二病也要谈恋爱 第1季 OVA.mkv',
        name: '[4K_NW] 中二病也要谈恋爱 第1季 OVA.mkv',
      ),
    ]);

    expect(groups.length, 4);
    expect(groups.map((group) => group.title), [
      '中二病也要谈恋爱 S01',
      '中二病也要谈恋爱 S02',
      '中二病也要谈恋爱 剧场版',
      '中二病也要谈恋爱 S01 OVA',
    ]);
  });

  test('LocalSeriesGrouper separates real nested seasons and specials', () {
    final groups = const LocalSeriesGrouper().group([
      _video(
        path: r'D:\a TV\中二病也要谈恋爱\剧场版\[4K_NW] 中二病也要谈恋爱 剧场版 01.mkv',
        name: '[4K_NW] 中二病也要谈恋爱 剧场版 01.mkv',
      ),
      _video(
        path: r'D:\a TV\中二病也要谈恋爱\剧场版\[4K_NW] 中二病也要谈恋爱 剧场版 02 Take On Me.mkv',
        name: '[4K_NW] 中二病也要谈恋爱 剧场版 02 Take On Me.mkv',
      ),
      _video(
        path: r'D:\a TV\中二病也要谈恋爱\第1季\[4K_NW] 中二病也要谈恋爱 第1季 01.mkv',
        name: '[4K_NW] 中二病也要谈恋爱 第1季 01.mkv',
      ),
      _video(
        path: r'D:\a TV\中二病也要谈恋爱\第1季\[4K_NW] 中二病也要谈恋爱 第1季 OVA.mkv',
        name: '[4K_NW] 中二病也要谈恋爱 第1季 OVA.mkv',
      ),
      _video(
        path: r'D:\a TV\中二病也要谈恋爱\第2季\[4K_NW] 中二病也要谈恋爱 第2季 01.mkv',
        name: '[4K_NW] 中二病也要谈恋爱 第2季 01.mkv',
      ),
      _video(
        path: r'D:\a TV\中二病也要谈恋爱\第2季\[4K_NW] 中二病也要谈恋爱 第2季 OVA.mkv',
        name: '[4K_NW] 中二病也要谈恋爱 第2季 OVA.mkv',
      ),
    ]);

    expect(groups.length, 5);
    expect(groups.map((group) => group.title), [
      '中二病也要谈恋爱 剧场版',
      '中二病也要谈恋爱 S01',
      '中二病也要谈恋爱 S01 OVA',
      '中二病也要谈恋爱 S02',
      '中二病也要谈恋爱 S02 OVA',
    ]);
    expect(groups.map((group) => group.episodeCount), [2, 1, 1, 1, 1]);
  });

  test('LocalSeriesGrouper keeps unrelated similar titles separated', () {
    final groups = const LocalSeriesGrouper().group([
      _video(
        path: r'D:\Anime\Root\黑天鹅\Black Swan.mkv',
        name: 'Black Swan.mkv',
        seriesName: '黑天鹅',
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\Anime\Root\黑镜\Black Mirror.mkv',
        name: 'Black Mirror.mkv',
        seriesName: '黑镜',
        episodeNumber: 1,
      ),
    ]);

    expect(groups.length, 2);
    expect(groups.map((group) => group.title), ['黑天鹅', '黑镜']);
  });

  test('LocalSeriesGrouper 不合并名称前缀相同的独立 TMDB 影片', () {
    final groups = const LocalSeriesGrouper().group([
      _video(
        path: r'D:\电影\假面骑士OOO\假面骑士OOO.mkv',
        name: '假面骑士OOO.mkv',
        seriesName: '假面骑士OOO',
        episodeNumber: 1,
      ),
      _video(
        path: r'D:\电影\假面骑士OOO 10周年 复活的核心硬币\假面骑士OOO 10周年 复活的核心硬币.mkv',
        name: '假面骑士OOO 10周年 复活的核心硬币.mkv',
        seriesName: '假面骑士OOO 10周年 复活的核心硬币',
        episodeNumber: 10,
      ),
    ]);

    expect(groups, hasLength(2));
    expect(groups.map((group) => group.episodeCount), [1, 1]);
  });

  test('LocalSeriesGrouper 将同一文件夹内的最终章归入主剧集', () {
    final groups = const LocalSeriesGrouper().group([
      _video(
        path: r'D:\a TV\假面骑士OOO\假面骑士OOO 第46集.mkv',
        name: '假面骑士OOO 第46集.mkv',
        seriesName: '假面骑士OOO',
        episodeNumber: 46,
      ),
      _video(
        path: r'D:\a TV\假面骑士OOO\假面骑士OOO 最终章 47-48（导演剪辑版）.mkv',
        name: '假面骑士OOO 最终章 47-48（导演剪辑版）.mkv',
        seriesName: '假面骑士OOO 最终章',
        episodeNumber: 47,
      ),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.title, '假面骑士OOO');
    expect(groups.single.episodeCount, 2);
  });

  test('LocalSeriesGrouper groups unrecognized files by parent directory', () {
    final groups = const LocalSeriesGrouper().group([
      _video(path: r'D:\Anime\Root\ShowA\02.mkv', name: '02.mkv'),
      _video(path: r'D:\Anime\Root\ShowA\01.mkv', name: '01.mkv'),
      _video(path: r'D:\Anime\Root\ShowB\01.mkv', name: '01.mkv'),
    ]);

    expect(groups.length, 2);
    expect(groups.first.title, 'ShowA');
    expect(groups.first.episodeCount, 2);
    expect(groups.first.episodes.map((item) => item.name), [
      '01.mkv',
      '02.mkv',
    ]);
    expect(groups.last.title, 'ShowB');
  });

  test('LocalSeriesGrouper keeps raw file names for playback titles', () {
    final groups = const LocalSeriesGrouper().group([
      _video(
        path: r'D:\Anime\Root\ShowA\ShowA S01E01.mkv',
        name: 'ShowA S01E01.mkv',
        seriesName: 'ShowA',
        seasonNumber: 1,
        episodeNumber: 1,
        episodeTitle: '起点',
      ),
      _video(
        path: r'D:\Anime\Root\ShowA\ShowA S01E02.mkv',
        name: 'ShowA S01E02.mkv',
        seriesName: 'ShowA',
        seasonNumber: 1,
        episodeNumber: 2,
        episodeTitle: '继续',
      ),
    ]);

    expect(groups.first.playlistFilesForPlayback, [
      {
        'path': r'D:\Anime\Root\ShowA\ShowA S01E01.mkv',
        'name': 'ShowA S01E01.mkv',
        'title': 'ShowA S01E01',
      },
      {
        'path': r'D:\Anime\Root\ShowA\ShowA S01E02.mkv',
        'name': 'ShowA S01E02.mkv',
        'title': 'ShowA S01E02',
      },
    ]);
  });

  test('LocalSeriesGrouper keeps raw movie playback titles compact', () {
    final groups = const LocalSeriesGrouper().group([
      _video(
        path:
            r'D:\Movie\因果报应 Maharaja 2024 HQ WEB DL DT\因果报应 Maharaja 2024 HQ WEB DL DT 01.mkv',
        name: '因果报应 Maharaja 2024 HQ WEB DL DT 01.mkv',
      ),
    ]);

    expect(groups.single.title, '因果报应 Maharaja');
    expect(groups.single.playlistFilesForPlayback.single['title'],
        '因果报应 Maharaja 2024 HQ WEB DL DT 01');
  });
}

LocalFileItem _video({
  required String path,
  required String name,
  String? seriesName,
  int? seasonNumber,
  int? episodeNumber,
  String? episodeTitle,
  String? seriesTitleOverride,
}) {
  return LocalFileItem(
    path: path,
    name: name,
    size: 1024,
    modified: DateTime(2026),
    isDirectory: false,
    isVideo: true,
    seriesTitleOverride: seriesTitleOverride,
    episodeInfo: episodeNumber == null || seriesName == null
        ? null
        : LocalEpisodeInfo(
            seriesName: seriesName,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle,
          ),
  );
}
