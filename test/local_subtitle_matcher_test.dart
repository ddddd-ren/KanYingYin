import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';

void main() {
  test('LocalSubtitleMatcher returns empty list when no subtitle exists',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_subtitle_empty_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Show S01E01.mkv');
    await video.writeAsBytes([0]);

    expect(LocalSubtitleMatcher().findAllForVideo(video.path), isEmpty);
    expect(LocalSubtitleMatcher().findForVideo(video.path), isNull);
  });

  test('LocalSubtitleMatcher findAllForVideo sorts nearby subtitles', () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_subtitle_all_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Show S01E03.mkv');
    final sameName =
        File('${dir.path}${Platform.pathSeparator}Show S01E03.ass');
    final sameEpisodeSibling =
        File('${dir.path}${Platform.pathSeparator}Show - 03.tc.srt');
    final subtitleDir = Directory('${dir.path}${Platform.pathSeparator}Subs');
    final subtitleDirMatch =
        File('${subtitleDir.path}${Platform.pathSeparator}Show - 03.zh.srt');
    final unrelated =
        File('${dir.path}${Platform.pathSeparator}Another Show.srt');

    await video.writeAsBytes([0]);
    await subtitleDir.create();
    await sameName.writeAsString('[Script Info]');
    await sameEpisodeSibling
        .writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHi');
    await subtitleDirMatch
        .writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHi');
    await unrelated.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHi');

    final result = LocalSubtitleMatcher().findAllForVideo(video.path);

    expect(result.first, sameName.path);
    expect(result[1], subtitleDirMatch.path);
    expect(result[2], sameEpisodeSibling.path);
    expect(result.last, unrelated.path);
  });

  test('LocalSubtitleMatcher keeps auto match limited to relevant subtitles',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_subtitle_auto_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Show S01E04.mkv');
    final unrelated =
        File('${dir.path}${Platform.pathSeparator}Another Show.srt');

    await video.writeAsBytes([0]);
    await unrelated.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHi');

    expect(
        LocalSubtitleMatcher().findAllForVideo(video.path), [unrelated.path]);
    expect(LocalSubtitleMatcher().findForVideo(video.path), isNull);
  });
}
