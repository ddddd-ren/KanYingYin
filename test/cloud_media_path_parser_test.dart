import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_media_path_parser.dart';

void main() {
  final parser = CloudMediaPathParser();

  test('从剧名加季度文件夹和纯集数文件名组合剧集身份', () {
    final result = parser.parse('/电视剧/权力的游戏 第2季/03.mkv');

    expect(result.seriesName, '权力的游戏');
    expect(result.seasonNumber, 2);
    expect(result.episodeNumber, 3);
    expect(result.hasSeasonConflict, isFalse);
  });

  test('从纯季度文件夹和紧邻上级文件夹组合剧集身份', () {
    final result = parser.parse('/电视剧/权力的游戏/Season 2/EP03.mkv');

    expect(result.seriesName, '权力的游戏');
    expect(result.seasonNumber, 2);
    expect(result.episodeNumber, 3);
  });

  test('支持中文数字英文和 S02 季度后缀', () {
    final cases = <String, String>{
      '/剧集/三体 第二季/第1集.mkv': '三体',
      '/剧集/三体 Season 2/E01.mkv': '三体',
      '/剧集/三体 S02/EP01.mkv': '三体',
      '/剧集/三体/第二季/01.mkv': '三体',
      '/剧集/三体/S02/01.mkv': '三体',
    };

    for (final entry in cases.entries) {
      final result = parser.parse(entry.key);
      expect(result.seriesName, entry.value, reason: entry.key);
      expect(result.seasonNumber, 2, reason: entry.key);
      expect(result.episodeNumber, 1, reason: entry.key);
    }
  });

  test('文件名明确季号覆盖文件夹季号', () {
    final result = parser.parse('/剧集/三体 第2季/三体.S01E03.mkv');

    expect(result.seriesName, '三体');
    expect(result.seasonNumber, 1);
    expect(result.folderSeasonNumber, 2);
    expect(result.episodeNumber, 3);
    expect(result.hasSeasonConflict, isTrue);
  });

  test('普通分类目录不会被当成纯季度目录的剧名', () {
    final result = parser.parse('/电视剧/第2季/01.mkv');

    expect(result.seriesName, isNull);
    expect(result.seasonNumber, 2);
    expect(result.episodeNumber, 1);
    expect(result.isEpisode, isFalse);
  });

  test('原有完整文件名识别保持不变', () {
    final result = parser.parse(
      '/任意目录/Alice.in.Borderland.S01E03.mkv',
    );

    expect(result.seriesName, 'Alice in Borderland');
    expect(result.seasonNumber, 1);
    expect(result.episodeNumber, 3);
    expect(result.hasSeasonConflict, isFalse);
  });
}
