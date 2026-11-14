import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';

void main() {
  test('多个封面查找器并发迁移旧海报后均返回有效新路径', () async {
    final root = await Directory.systemTemp.createTemp('cover_migration_race_');
    addTearDown(() => root.delete(recursive: true));
    final series =
        await Directory('${root.path}${Platform.pathSeparator}Show').create();
    final legacy = File('${root.path}${Platform.pathSeparator}Show.jpg');
    await legacy.writeAsString('poster');
    final finders = List.generate(12, (_) => LocalCoverFinder());
    final results = await Future.wait(
        finders.map((finder) => finder.findDirCover(series.path)));
    final expected = LocalCoverFinder.directoryCoverPath(series.path);
    expect(results, everyElement(expected));
    expect(await File(expected).readAsString(), 'poster');
    expect(await legacy.exists(), isFalse);
    final repeated = await Future.wait(
        finders.map((finder) => finder.findDirCover(series.path)));
    expect(repeated, everyElement(expected));
  });

  test('LocalCoverFinder 优先匹配 Android 文档目录中的 TMDB 海报', () {
    const treeUri = 'content://provider/tree/root';
    final video = _entry(
      treeUri: treeUri,
      uri: 'content://provider/document/video',
      name: 'Show S01E01.mkv',
      mimeType: 'video/x-matroska',
    );
    final sameName = _entry(
      treeUri: treeUri,
      uri: 'content://provider/document/same-name-cover',
      name: 'Show S01E01.jpg',
      mimeType: 'image/jpeg',
    );
    final tmdb = _entry(
      treeUri: treeUri,
      uri: 'content://provider/document/tmdb-cover',
      name: 'tmdb-poster.webp',
      mimeType: 'image/webp',
    );

    final matched = LocalCoverFinder().findForEntry(
      video: video,
      siblings: <LocalMediaEntry>[video, sameName, tmdb],
    );

    expect(matched?.location, tmdb.location);
  });
}

LocalMediaEntry _entry({
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
