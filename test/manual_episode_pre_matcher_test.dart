import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_pre_matcher.dart';

void main() {
  const matcher = ManualEpisodePreMatcher();

  test('明确 SxxExx 和中文季集格式可以可靠预匹配', () {
    expect(
      matcher.match(
        originalName: 'Isekai.Nonbiri.Nouka.S01E03.mkv',
        parentName: '异世界悠闲农家',
        expectedSeriesName: '异世界悠闲农家',
      ),
      const ManualEpisodePreMatch(seasonNumber: 1, episodeNumber: 3),
    );
    expect(
      matcher.match(
        originalName: '异世界悠闲农家 第1季第4集.mkv',
        parentName: '异世界悠闲农家',
        expectedSeriesName: '异世界悠闲农家',
      ),
      const ManualEpisodePreMatch(seasonNumber: 1, episodeNumber: 4),
    );
  });

  test('季度目录可以为明确 EP 集号补充季号', () {
    expect(
      matcher.match(
        originalName: '异世界悠闲农家 EP05.mkv',
        parentName: 'Season 2',
        grandParentName: '异世界悠闲农家',
        expectedSeriesName: '异世界悠闲农家',
      ),
      const ManualEpisodePreMatch(seasonNumber: 2, episodeNumber: 5),
    );
  });

  test('泛目录中的纯数字文件名保持未匹配', () {
    expect(
      matcher.match(
        originalName: '01.mkv',
        parentName: '电视剧',
        expectedSeriesName: '异世界悠闲农家',
      ),
      isNull,
    );
  });

  test('年份画质码率和数字电影标题不能当作集号', () {
    for (final name in <String>[
      '异世界悠闲农家 2024 4K.mkv',
      '异世界悠闲农家 1080p 8000kbps.mkv',
      'The 100.mkv',
    ]) {
      expect(
        matcher.match(
          originalName: name,
          parentName: '电视剧',
          expectedSeriesName: '异世界悠闲农家',
        ),
        isNull,
        reason: name,
      );
    }
  });

  test('文件名季号与目录季号冲突时保持未匹配', () {
    expect(
      matcher.match(
        originalName: '异世界悠闲农家.S01E03.mkv',
        parentName: 'Season 2',
        grandParentName: '异世界悠闲农家',
        expectedSeriesName: '异世界悠闲农家',
      ),
      isNull,
    );
  });
}
