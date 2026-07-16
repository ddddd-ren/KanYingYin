import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';

void main() {
  final parser = LocalEpisodeParser();

  test('LocalEpisodeParser parses SxxExx names', () {
    final info = parser.parse('Frieren S01E12 The Real Hero.mkv');

    expect(info, isNotNull);
    expect(info!.seriesName, 'Frieren');
    expect(info.seasonNumber, 1);
    expect(info.episodeNumber, 12);
    expect(info.episodeTitle, 'The Real Hero');
    expect(info.episodeLabel, 'S01E12');
  });

  test('LocalEpisodeParser parses Chinese episode names', () {
    final info = parser.parse(
      '\u846c\u9001\u7684\u8299\u8389\u83b2 '
      '\u7b2c08\u96c6 '
      '\u5317\u65b9\u8bf8\u56fd.mkv',
    );

    expect(info, isNotNull);
    expect(info!.seriesName, '\u846c\u9001\u7684\u8299\u8389\u83b2');
    expect(info.episodeNumber, 8);
    expect(info.displayTitle, '\u7b2c 08 \u96c6  \u5317\u65b9\u8bf8\u56fd');
  });

  test('LocalEpisodeParser parses bracketed episode names', () {
    final info = parser.parse('[Fansub] Bang Dream [03].mp4');

    expect(info, isNotNull);
    expect(info!.seriesName, 'Bang Dream');
    expect(info.episodeNumber, 3);
    expect(info.releaseGroup, 'Fansub');
  });

  test('LocalEpisodeParser uses bracketed episode after release tags', () {
    final info = parser.parse(
      r'D:\a TV\[SumiSora][Chu-2_Koi][BDRip]\[SumiSora][Chu-2_Koi][BDRip][01][x264_3flac](62A8611D).mkv',
    );

    expect(info, isNotNull);
    expect(info!.seriesName, 'Chu 2 Koi');
    expect(info.episodeNumber, 1);
    expect(info.releaseGroup, 'SumiSora');
  });

  test('LocalEpisodeParser uses season directory for bare episode files', () {
    final info = parser.parse(r'D:\Anime\Frieren\Season 2\Frieren - 03.mkv');

    expect(info, isNotNull);
    expect(info!.seriesName, 'Frieren');
    expect(info.seasonNumber, 2);
    expect(info.episodeNumber, 3);
  });

  test('LocalEpisodeParser parses Chinese season and episode names', () {
    final info = parser.parse(
      '\u846c\u9001\u7684\u8299\u8389\u83b2 '
      '\u7b2c2\u5b63 \u7b2c04\u8bdd 旅路.mkv',
    );

    expect(info, isNotNull);
    expect(info!.seriesName, '\u846c\u9001\u7684\u8299\u8389\u83b2');
    expect(info.seasonNumber, 2);
    expect(info.episodeNumber, 4);
  });

  test('LocalEpisodeParser falls back to parent folder for fansub prefix', () {
    final info = parser.parse(r'D:\Anime\My Show\[Nekomoe] [05][1080p].mkv');

    expect(info, isNotNull);
    expect(info!.seriesName, 'My Show');
    expect(info.episodeNumber, 5);
  });

  test('LocalEpisodeParser ignores names without episode number', () {
    final info = parser.parse('Movie Special.mkv');

    expect(info, isNull);
  });

  test('LocalEpisodeParser ignores movie years in titles', () {
    final info = parser.parse('Persian Lessons 2020.mkv');

    expect(info, isNull);
  });

  test('LocalEpisodeParser does not truncate four digit years as episodes', () {
    final info = parser.parse('Movie Title - 2024.mkv');

    expect(info, isNull);
  });

  test('LocalEpisodeParser ignores movie release trailing numbers', () {
    final info = parser.parse(
      '因果报应 Maharaja 2024 HQ WEB DL DT 01.mkv',
    );

    expect(info, isNull);
  });

  test('LocalEpisodeParser 不把电影标题中的周年数字识别为集号', () {
    final info = parser.parse(
      r'D:\电影\假面骑士OOO 10周年 复活的核心硬币\假面骑士OOO 10周年 复活的核心硬币.mkv',
    );

    expect(info, isNull);
  });

  test('LocalEpisodeParser ignores 4K release markers as episodes', () {
    final info = parser.parse('interstellar 2014 imax 4K-kc.mkv');

    expect(info, isNull);
  });
}
