import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';

void main() {
  test('字幕目录枚举接口异步执行', () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_subtitle_async_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final video = File('${dir.path}${Platform.pathSeparator}Show S01E01.mkv');
    await video.writeAsBytes([0]);

    final result = LocalSubtitleMatcher().findAllForVideo(video.path);

    expect(result, isA<Future<List<String>>>());
  });

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

    expect(await LocalSubtitleMatcher().findAllForVideo(video.path), isEmpty);
    expect(await LocalSubtitleMatcher().findForVideo(video.path), isNull);
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

    final result = await LocalSubtitleMatcher().findAllForVideo(video.path);

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

    expect(await LocalSubtitleMatcher().findAllForVideo(video.path),
        [unrelated.path]);
    expect(await LocalSubtitleMatcher().findForVideo(video.path), isNull);
  });

  test('LocalSubtitleMatcher 按显示名称匹配 Android 文档字幕', () {
    final treeUri = 'content://provider/tree/root';
    final video = _documentEntry(
      treeUri: treeUri,
      uri: 'content://provider/document/video',
      name: 'Show S01E03.mkv',
      mimeType: 'video/x-matroska',
    );
    final subtitle = _documentEntry(
      treeUri: treeUri,
      uri: 'content://provider/document/subtitle',
      name: 'Show S01E03.ass',
      mimeType: 'text/x-ssa',
    );
    final unrelated = _documentEntry(
      treeUri: treeUri,
      uri: 'content://provider/document/unrelated',
      name: 'Other S01E01.srt',
      mimeType: 'application/x-subrip',
    );

    final matched = LocalSubtitleMatcher().findForEntry(
      video: video,
      siblings: <LocalMediaEntry>[video, unrelated, subtitle],
    );

    expect(matched?.location, subtitle.location);
  });
}

LocalMediaEntry _documentEntry({
  required String treeUri,
  required String uri,
  required String name,
  required String mimeType,
}) {
  return LocalMediaEntry(
    location: MediaLocation.document(uri: uri, treeUri: treeUri),
    name: name,
    isDirectory: false,
    size: 1024,
    modified: DateTime(2026, 7, 29),
    mimeType: mimeType,
  );
}
