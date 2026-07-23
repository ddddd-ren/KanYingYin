import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';

void main() {
  test('LocalPlaybackRequestBuilder builds playlist request', () {
    final request = LocalPlaybackRequestBuilder().build(
      filePath: r'D:\Anime\Show\02.mkv',
      fileName: '02.mkv',
      directoryFiles: [
        {'path': r'D:\Anime\Show\01.mkv', 'name': '01.mkv'},
        {'path': r'D:\Anime\Show\02.mkv', 'name': '02.mkv'},
      ],
    );

    expect(request.title, '02.mkv');
    expect(request.videoPath, r'D:\Anime\Show\02.mkv');
    expect(request.sourceLabel, '本地文件');
    expect(request.mediaItem.effectiveTitle, '02.mkv');
    expect(request.currentRoad, 0);
    expect(request.currentEpisode, 2);
    expect(request.road.name, '当前剧集');
    expect(request.road.data, [
      r'D:\Anime\Show\01.mkv',
      r'D:\Anime\Show\02.mkv',
    ]);
    expect(request.road.identifier, ['01.mkv', '02.mkv']);
  });

  test('LocalPlaybackRequestBuilder falls back to single file playlist', () {
    final request = LocalPlaybackRequestBuilder().build(
      filePath: r'D:\Anime\Show\01.mkv',
      fileName: '01.mkv',
      sourceLabel: '本地测试',
    );

    expect(request.sourceLabel, '本地测试');
    expect(request.currentEpisode, 1);
    expect(request.road.name, '播放列表1');
    expect(request.road.data, [r'D:\Anime\Show\01.mkv']);
    expect(request.road.identifier, ['01.mkv']);
  });

  test('LocalPlaybackRequestBuilder ignores invalid playlist entries', () {
    final request = LocalPlaybackRequestBuilder().build(
      filePath: r'D:\Anime\Show\02.mkv',
      fileName: '02.mkv',
      directoryFiles: [
        {'path': '', 'name': 'broken.mkv'},
        {'path': r'D:\Anime\Show\01.mkv', 'name': ''},
        {'path': r'D:\Anime\Show\02.mkv', 'name': '02.mkv'},
      ],
    );

    expect(request.currentEpisode, 1);
    expect(request.road.data, [r'D:\Anime\Show\02.mkv']);
    expect(request.road.identifier, ['02.mkv']);
  });

  test(
      'LocalPlaybackRequestBuilder inserts selected file when playlist misses it',
      () {
    final request = LocalPlaybackRequestBuilder().build(
      filePath: r'D:\Anime\Show\02.mkv',
      fileName: '02.mkv',
      directoryFiles: [
        {'path': r'D:\Anime\Show\01.mkv', 'name': '01.mkv'},
      ],
    );

    expect(request.currentEpisode, 1);
    expect(request.road.data, [
      r'D:\Anime\Show\02.mkv',
      r'D:\Anime\Show\01.mkv',
    ]);
    expect(request.road.identifier, ['02.mkv', '01.mkv']);
  });

  test('LocalPlaybackRequestBuilder removes duplicate playlist paths', () {
    final request = LocalPlaybackRequestBuilder().build(
      filePath: r'D:\Anime\Show\02.mkv',
      fileName: '02.mkv',
      directoryFiles: [
        {'path': r'D:\Anime\Show\01.mkv', 'name': '01.mkv'},
        {'path': r'D:\Anime\Show\02.mkv', 'name': '02.mkv'},
        {'path': r'D:\Anime\Show\02.mkv', 'name': '02 duplicate.mkv'},
        {'path': r'D:\Anime\Show\01.mkv', 'name': '01 duplicate.mkv'},
      ],
    );

    expect(request.currentEpisode, 2);
    expect(request.road.data, [
      r'D:\Anime\Show\01.mkv',
      r'D:\Anime\Show\02.mkv',
    ]);
    expect(request.road.identifier, ['01.mkv', '02.mkv']);
  });

  test('LocalPlaybackRequestBuilder uses full playlist titles when provided',
      () {
    final request = LocalPlaybackRequestBuilder().build(
      filePath: r'D:\Anime\Show\02.mkv',
      fileName: '02.mkv',
      directoryFiles: [
        {
          'path': r'D:\Anime\Show\01.mkv',
          'name': '01.mkv',
          'title': 'Show  第 01 集  开始',
        },
        {
          'path': r'D:\Anime\Show\02.mkv',
          'name': '02.mkv',
          'title': 'Show  第 02 集  继续',
        },
      ],
    );

    expect(request.currentEpisode, 2);
    expect(request.road.identifier, [
      'Show  第 01 集  开始',
      'Show  第 02 集  继续',
    ]);
  });

  test('LocalPlaybackRequestBuilder isolates playlist by recognized series',
      () {
    final request = LocalPlaybackRequestBuilder().build(
      filePath: r'D:\Anime\Root\ShowA\ShowA S01E02.mkv',
      fileName: 'ShowA S01E02.mkv',
      directoryFiles: [
        {
          'path': r'D:\Anime\Root\ShowA\ShowA S01E01.mkv',
          'name': 'ShowA S01E01.mkv'
        },
        {
          'path': r'D:\Anime\Root\ShowA\ShowA S01E02.mkv',
          'name': 'ShowA S01E02.mkv'
        },
        {
          'path': r'D:\Anime\Root\ShowB\ShowB S01E01.mkv',
          'name': 'ShowB S01E01.mkv'
        },
      ],
    );

    expect(request.currentEpisode, 2);
    expect(request.road.name, '当前剧集');
    expect(request.road.data, [
      r'D:\Anime\Root\ShowA\ShowA S01E01.mkv',
      r'D:\Anime\Root\ShowA\ShowA S01E02.mkv',
    ]);
  });

  test(
      'LocalPlaybackRequestBuilder preserves isolated sequel and movie playlist',
      () {
    final request = LocalPlaybackRequestBuilder().build(
      filePath: r'D:\Anime\中二病也要谈恋爱\第2季\中二病也要谈恋爱 S02E01.mkv',
      fileName: '中二病也要谈恋爱',
      directoryFiles: [
        {
          'path': r'D:\Anime\中二病也要谈恋爱\第1季\中二病也要谈恋爱 S01E01.mkv',
          'name': '第1季 第01集'
        },
        {
          'path': r'D:\Anime\中二病也要谈恋爱\第2季\中二病也要谈恋爱 S02E01.mkv',
          'name': '第2季 第01集'
        },
        {'path': r'D:\Anime\中二病也要谈恋爱\剧场版\中二病也要谈恋爱 剧场版.mkv', 'name': '剧场版'},
      ],
      playlistAlreadyIsolated: true,
    );

    expect(request.currentEpisode, 2);
    expect(request.road.data, [
      r'D:\Anime\中二病也要谈恋爱\第1季\中二病也要谈恋爱 S01E01.mkv',
      r'D:\Anime\中二病也要谈恋爱\第2季\中二病也要谈恋爱 S02E01.mkv',
      r'D:\Anime\中二病也要谈恋爱\剧场版\中二病也要谈恋爱 剧场版.mkv',
    ]);
    expect(request.road.identifier, ['第1季 第01集', '第2季 第01集', '剧场版']);
  });

  test('LocalPlaybackRequestBuilder falls back to parent directory grouping',
      () {
    final request = LocalPlaybackRequestBuilder().build(
      filePath: r'D:\Anime\Root\ShowA\02.mkv',
      fileName: '02.mkv',
      directoryFiles: [
        {'path': r'D:\Anime\Root\ShowA\01.mkv', 'name': '01.mkv'},
        {'path': r'D:\Anime\Root\ShowA\02.mkv', 'name': '02.mkv'},
        {'path': r'D:\Anime\Root\ShowB\01.mkv', 'name': '01.mkv'},
      ],
    );

    expect(request.currentEpisode, 2);
    expect(request.road.data, [
      r'D:\Anime\Root\ShowA\01.mkv',
      r'D:\Anime\Root\ShowA\02.mkv',
    ]);
  });

  test('LocalPlaybackRequestBuilder matches same-name subtitle', () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_subtitle_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Episode 01.mkv');
    final subtitle = File('${dir.path}${Platform.pathSeparator}Episode 01.ass');
    await video.writeAsBytes([0]);
    await subtitle.writeAsString('[Script Info]');

    final request = LocalPlaybackRequestBuilder().build(
      filePath: video.path,
      fileName: 'Episode 01.mkv',
    );

    expect(request.subtitlePath, subtitle.path);
  });

  test('LocalPlaybackRequestBuilder matches subtitle by episode number',
      () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_subtitle_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Show S01E05.mkv');
    final subsDir = Directory('${dir.path}${Platform.pathSeparator}字幕');
    await subsDir.create();
    final subtitle = File(
      '${subsDir.path}${Platform.pathSeparator}Show - 05.chs.srt',
    );
    await video.writeAsBytes([0]);
    await subtitle.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHi');

    final request = LocalPlaybackRequestBuilder().build(
      filePath: video.path,
      fileName: 'Show S01E05.mkv',
    );

    expect(request.subtitlePath, subtitle.path);
  });

  test('LocalPlaybackRequestBuilder prefers same-name subtitle', () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_subtitle_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Show S01E06.mkv');
    final sameName =
        File('${dir.path}${Platform.pathSeparator}Show S01E06.ass');
    final subsDir = Directory('${dir.path}${Platform.pathSeparator}Subs');
    await subsDir.create();
    final episodeMatch = File(
      '${subsDir.path}${Platform.pathSeparator}Show - 06.zh.srt',
    );
    await video.writeAsBytes([0]);
    await sameName.writeAsString('[Script Info]');
    await episodeMatch.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHi');

    final request = LocalPlaybackRequestBuilder().build(
      filePath: video.path,
      fileName: 'Show S01E06.mkv',
    );

    expect(request.subtitlePath, sameName.path);
  });

  test('LocalPlaybackRequestBuilder respects disabled auto subtitle', () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_subtitle_disabled_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Episode 02.mkv');
    final subtitle = File('${dir.path}${Platform.pathSeparator}Episode 02.srt');
    await video.writeAsBytes([0]);
    await subtitle.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHi');

    final request = LocalPlaybackRequestBuilder().build(
      filePath: video.path,
      fileName: 'Episode 02.mkv',
      autoLoadSubtitle: false,
    );

    expect(request.subtitlePath, isNull);
  });
}
