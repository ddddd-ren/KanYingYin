import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/services/local_media_scanner.dart';
import 'package:kanyingyin/services/local_thumbnail_cache.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';

void main() {
  test('LocalMediaScanner filters non-videos and matches video poster',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video = File('${tempDir.path}${Platform.pathSeparator}movie.mkv');
    final poster = File('${tempDir.path}${Platform.pathSeparator}movie.jpg');
    final text = File('${tempDir.path}${Platform.pathSeparator}note.txt');
    await video.writeAsString('video');
    await poster.writeAsString('poster');
    await text.writeAsString('text');

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(result.items.length, 1);
    expect(result.items.single.name, 'movie.mkv');
    expect(result.items.single.cover, poster.path);
    expect(result.skippedCount, 2);
  });

  test('LocalMediaScanner matches same-name subtitle', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video = File('${tempDir.path}${Platform.pathSeparator}movie.mkv');
    final subtitle = File('${tempDir.path}${Platform.pathSeparator}movie.ass');
    await video.writeAsString('video');
    await subtitle.writeAsString('[Script Info]');

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(result.items.single.subtitlePath, subtitle.path);
    expect(result.items.single.hasSubtitle, isTrue);
  });

  test('LocalMediaScanner matches episode subtitle in Subs directory',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video = File(
      '${tempDir.path}${Platform.pathSeparator}Show S01E03.mkv',
    );
    final subsDir = Directory('${tempDir.path}${Platform.pathSeparator}Subs');
    await subsDir.create();
    final subtitle = File(
      '${subsDir.path}${Platform.pathSeparator}Show - 03.zh.ass',
    );
    await video.writeAsString('video');
    await subtitle.writeAsString('[Script Info]');

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    final videoItem = result.items.singleWhere((item) => item.isVideo);
    expect(videoItem.subtitlePath, subtitle.path);
  });

  test('LocalMediaScanner uses cached local thumbnails for videos', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video = File('${tempDir.path}${Platform.pathSeparator}movie.mkv');
    await video.writeAsString('video');
    final thumbnail = File(LocalThumbnailCache.pathForVideo(video.path));
    await thumbnail.parent.create(recursive: true);
    await thumbnail.writeAsBytes([1, 2, 3]);

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(result.items.length, 1);
    expect(result.items.single.cover, thumbnail.path);
  });

  test('LocalMediaScanner attaches parsed episode info to videos', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await File('${tempDir.path}${Platform.pathSeparator}Show S02E07 Title.mkv')
        .writeAsString('video');

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    final info = result.items.single.episodeInfo;
    expect(info, isNotNull);
    expect(info!.seriesName, 'Show');
    expect(info.seasonNumber, 2);
    expect(info.episodeNumber, 7);
    expect(info.episodeTitle, 'Title');
  });

  test('LocalFileItem formats modified date', () {
    final item = LocalFileItem(
      path: 'video.mkv',
      name: 'video.mkv',
      size: 1024,
      modified: DateTime(2026, 6, 4, 12),
      isDirectory: false,
      isVideo: true,
    );

    expect(item.formattedModified, '2026-06-04');
  });

  test('LocalMediaScanner recursively shows recognized video files', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final childDir = Directory('${tempDir.path}${Platform.pathSeparator}Show');
    final smallVideo =
        File('${tempDir.path}${Platform.pathSeparator}Small.mp4');
    await childDir.create();
    final video = File('${childDir.path}${Platform.pathSeparator}Movie.mp4');
    await smallVideo.writeAsBytes(List<int>.filled(16, 0));
    await video.writeAsBytes(List<int>.filled(32, 0));

    final result =
        await LocalMediaScanner(minRecognizedVideoSizeBytes: 16).scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(result.items.map((item) => item.name), ['Movie.mp4']);
    expect(result.items.single.isVideo, isTrue);
    expect(result.items.any((item) => item.isDirectory), isFalse);
    expect(result.skippedCount, 1);
  });

  test('LocalMediaScanner 每次扫描动态读取一次视频大小限制', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_dynamic_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final video = File('${tempDir.path}${Platform.pathSeparator}Movie.mkv');
    await video.writeAsBytes(List<int>.filled(32, 0));
    var minSizeBytes = 64;
    var providerCalls = 0;
    final scanner = LocalMediaScanner(
      minRecognizedVideoSizeBytesProvider: () {
        providerCalls++;
        return minSizeBytes;
      },
    );

    final first = await scanner.scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );
    minSizeBytes = 16;
    final second = await scanner.scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(first.items, isEmpty);
    expect(second.items.map((item) => item.path), <String>[video.path]);
    expect(providerCalls, 2);
  });

  test('LocalVideoFileTypes 忽略零大小和等于阈值的视频', () {
    expect(
      LocalVideoFileTypes.isRecognizedVideoSize(0, minSizeBytes: -1),
      isFalse,
    );
    expect(
      LocalVideoFileTypes.isRecognizedVideoSize(16, minSizeBytes: 16),
      isFalse,
    );
    expect(
      LocalVideoFileTypes.isRecognizedVideoSize(1, minSizeBytes: 0),
      isTrue,
    );
  });

  test('LocalMediaScanner sorts names naturally', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await File('${tempDir.path}${Platform.pathSeparator}Episode 10.mkv')
        .writeAsString('video');
    await File('${tempDir.path}${Platform.pathSeparator}Episode 2.mkv')
        .writeAsString('video');
    await File('${tempDir.path}${Platform.pathSeparator}Episode 1.mkv')
        .writeAsString('video');

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(result.items.map((item) => item.name), [
      'Episode 1.mkv',
      'Episode 2.mkv',
      'Episode 10.mkv',
    ]);
  });

  test('LocalMediaScanner sorts names naturally in descending order', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await File('${tempDir.path}${Platform.pathSeparator}Episode 10.mkv')
        .writeAsString('video');
    await File('${tempDir.path}${Platform.pathSeparator}Episode 2.mkv')
        .writeAsString('video');

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: false,
    );

    expect(result.items.map((item) => item.name), [
      'Episode 10.mkv',
      'Episode 2.mkv',
    ]);
  });

  test('LocalMediaScanner uses common poster names for videos', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video = File('${tempDir.path}${Platform.pathSeparator}episode.mp4');
    final poster = File('${tempDir.path}${Platform.pathSeparator}cover.png');
    await video.writeAsString('video');
    await poster.writeAsString('poster');

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(result.items.single.cover, poster.path);
  });

  test('LocalMediaScanner moves legacy parent directory cover into folder',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final showDir = Directory('${tempDir.path}${Platform.pathSeparator}Show');
    await showDir.create();
    final video = File('${showDir.path}${Platform.pathSeparator}episode.mp4');
    final legacyPoster =
        File('${tempDir.path}${Platform.pathSeparator}Show.jpg');
    await video.writeAsString('video');
    await legacyPoster.writeAsString('poster');

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    final cover = File('${showDir.path}${Platform.pathSeparator}cover.jpg');
    expect(result.items.single.cover, cover.path);
    expect(cover.existsSync(), isTrue);
    expect(legacyPoster.existsSync(), isFalse);
  });

  test('LocalMediaScanner matches poster names case-insensitively', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_local_scan_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video = File('${tempDir.path}${Platform.pathSeparator}episode.mkv');
    final poster = File('${tempDir.path}${Platform.pathSeparator}Episode.JPG');
    await video.writeAsString('video');
    await poster.writeAsString('poster');

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(result.items.single.cover, poster.path);
  });

  test('LocalMediaScanner prefers downloaded TMDB poster', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_tmdb_cover_');
    addTearDown(() => tempDir.delete(recursive: true));
    final video = File('${tempDir.path}${Platform.pathSeparator}episode.mkv');
    final cover = File('${tempDir.path}${Platform.pathSeparator}cover.jpg');
    final tmdbPoster =
        File('${tempDir.path}${Platform.pathSeparator}tmdb-poster.jpg');
    await video.writeAsString('video');
    await cover.writeAsString('user cover');
    await tmdbPoster.writeAsString('tmdb cover');

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(result.items.single.cover, tmdbPoster.path);
  });

  test('LocalMediaScanner 主动跳过 Windows 系统目录', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_scan_system_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final valid = File('${tempDir.path}${Platform.pathSeparator}Show.mkv');
    await valid.writeAsString('video');
    for (final name in const <String>[
      'System Volume Information',
      r'$RECYCLE.BIN'
    ]) {
      final directory =
          Directory('${tempDir.path}${Platform.pathSeparator}$name');
      await directory.create();
      await File('${directory.path}${Platform.pathSeparator}Hidden.mkv')
          .writeAsString('video');
    }

    final result = await _testScanner().scan(
      tempDir.path,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(result.items.map((item) => item.path), <String>[valid.path]);
    expect(result.skippedCount, 2);
  });
}

LocalMediaScanner _testScanner() {
  return LocalMediaScanner(minRecognizedVideoSizeBytes: 0);
}
