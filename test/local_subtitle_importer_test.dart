import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/local_subtitle_importer.dart';

void main() {
  test('LocalSubtitleImporter imports subtitle with video file name', () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_sub_import_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Episode 01.mkv');
    final externalDir =
        await Directory.systemTemp.createTemp('kanyingyin_sub_src_');
    addTearDown(() async {
      if (await externalDir.exists()) {
        await externalDir.delete(recursive: true);
      }
    });
    final subtitle =
        File('${externalDir.path}${Platform.pathSeparator}custom.zh.ass');
    await video.writeAsBytes([0]);
    await subtitle.writeAsString('[Script Info]');

    final result = await LocalSubtitleImporter().importForVideo(
      videoPath: video.path,
      subtitlePath: subtitle.path,
      target: LocalSubtitleImportTarget.subtitleDirectory,
    );

    final expected = File(
      '${dir.path}${Platform.pathSeparator}字幕${Platform.pathSeparator}Episode 01.ass',
    );
    expect(result.targetPath, expected.path);
    expect(result.renamed, isFalse);
    expect(await expected.readAsString(), '[Script Info]');
  });

  test('LocalSubtitleImporter rejects unsupported extension', () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_sub_import_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Episode 01.mkv');
    final subtitle = File('${dir.path}${Platform.pathSeparator}Episode 01.txt');
    await video.writeAsBytes([0]);
    await subtitle.writeAsString('text');

    expect(
      () => LocalSubtitleImporter().importForVideo(
        videoPath: video.path,
        subtitlePath: subtitle.path,
      ),
      throwsA(isA<LocalSubtitleImportException>()),
    );
  });

  test('LocalSubtitleImporter avoids overwriting existing subtitle', () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_sub_import_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Episode 01.mkv');
    final existing = File('${dir.path}${Platform.pathSeparator}Episode 01.srt');
    final externalDir =
        await Directory.systemTemp.createTemp('kanyingyin_sub_src_');
    addTearDown(() async {
      if (await externalDir.exists()) {
        await externalDir.delete(recursive: true);
      }
    });
    final subtitle =
        File('${externalDir.path}${Platform.pathSeparator}download.srt');
    await video.writeAsBytes([0]);
    await existing.writeAsString('old');
    await subtitle.writeAsString('new');

    final result = await LocalSubtitleImporter().importForVideo(
      videoPath: video.path,
      subtitlePath: subtitle.path,
      target: LocalSubtitleImportTarget.videoDirectory,
    );

    final expected =
        File('${dir.path}${Platform.pathSeparator}Episode 01 (1).srt');
    expect(result.targetPath, expected.path);
    expect(result.renamed, isTrue);
    expect(await existing.readAsString(), 'old');
    expect(await expected.readAsString(), 'new');
  });

  test('LocalSubtitleImporter 将 content URI 的外部字幕复制到应用目录', () async {
    final appRoot = await Directory.systemTemp.createTemp(
      'kanyingyin-document-subtitle-import-',
    );
    final sourceRoot = await Directory.systemTemp.createTemp(
      'kanyingyin-document-subtitle-source-',
    );
    addTearDown(() async {
      await appRoot.delete(recursive: true);
      await sourceRoot.delete(recursive: true);
    });
    final subtitle = File(
      '${sourceRoot.path}${Platform.pathSeparator}Show.zh.srt',
    );
    await subtitle.writeAsString('subtitle');
    final importer = LocalSubtitleImporter(
      applicationRootProvider: () async => appRoot,
    );

    final result = await importer.importForVideo(
      videoPath: 'content://provider/document/video%3A42',
      subtitlePath: subtitle.path,
    );

    expect(result.targetPath, startsWith(appRoot.path));
    expect(result.targetPath, contains('local_document_imported_subtitles'));
    expect(await File(result.targetPath).readAsString(), 'subtitle');
    expect(await subtitle.exists(), isTrue);
    expect(
        importer.supportsVideoDirectory(videoPath: 'content://x/y'), isFalse);
  });
}
