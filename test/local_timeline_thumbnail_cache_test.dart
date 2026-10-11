import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kanyingyin/services/local_timeline_thumbnail_cache.dart';
import 'package:kanyingyin/services/local_thumbnail_cache.dart';

void main() {
  late Directory root;
  late File video;

  Future<String> cachePath(String path, int bucket) =>
      LocalThumbnailCache.pathForTimelineThumbnail(path, bucket,
          cacheRootProvider: () async =>
              Directory('${root.path}${Platform.pathSeparator}cache'));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kanyingyin-timeline-');
    video = File('${root.path}${Platform.pathSeparator}episode.mkv');
    await video.writeAsBytes(<int>[1]);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String?> writeThumbnail(
    String videoPath,
    String outputPath,
    Duration position,
  ) async {
    await File(outputPath).parent.create(recursive: true);
    await File(outputPath)
        .writeAsBytes(img.encodeJpg(img.Image(width: 2, height: 2)));
    return outputPath;
  }

  test('按时间桶命中缓存且不重复生成', () async {
    var generated = 0;
    final cache = LocalTimelineThumbnailCache(
      pathProvider: cachePath,
      generator: (videoPath, outputPath, position) async {
        generated++;
        return writeThumbnail(videoPath, outputPath, position);
      },
    );

    final first = await cache.thumbnailAt(
      videoPath: video.path,
      position: const Duration(seconds: 5),
      duration: const Duration(minutes: 10),
    );
    final second = await cache.thumbnailAt(
      videoPath: video.path,
      position: const Duration(seconds: 8),
      duration: const Duration(minutes: 10),
    );

    expect(first, isNotNull);
    expect(second, first);
    expect(generated, 1);
  });

  test('取消生成不会提交临时缩略图', () async {
    final gate = Completer<void>();
    final cache = LocalTimelineThumbnailCache(
      pathProvider: cachePath,
      generator: (videoPath, outputPath, position) async {
        await writeThumbnail(videoPath, outputPath, position);
        await gate.future;
        return outputPath;
      },
    );

    final pending = cache.thumbnailAt(
      videoPath: video.path,
      position: const Duration(seconds: 5),
      duration: const Duration(minutes: 10),
    );
    await Future<void>.delayed(Duration.zero);
    cache.cancelPending();
    gate.complete();

    expect(await pending, isNull);
    final jpgs = await root
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.jpg'))
        .toList();
    expect(jpgs, isEmpty);
  });

  test('缓存损坏时重新生成，且目录保留不超过上限', () async {
    final cache = LocalTimelineThumbnailCache(
      pathProvider: cachePath,
      maxEntries: 2,
      generator: writeThumbnail,
    );
    final firstPath = await cache.thumbnailAt(
      videoPath: video.path,
      position: const Duration(seconds: 5),
      duration: const Duration(minutes: 10),
    );
    expect(firstPath, isNotNull);
    await File(firstPath!).writeAsBytes(const <int>[1, 2, 3]);
    expect(
        await cache.thumbnailAt(
            videoPath: video.path,
            position: const Duration(seconds: 5),
            duration: const Duration(minutes: 10)),
        firstPath);
    expect(img.decodeImage(await File(firstPath).readAsBytes()), isNotNull);

    final extra = File(
        '${File(firstPath).parent.path}${Platform.pathSeparator}extra.jpg');
    await extra.writeAsBytes(<int>[1]);
    final secondPath = await cache.thumbnailAt(
      videoPath: video.path,
      position: const Duration(minutes: 6),
      duration: const Duration(minutes: 10),
    );

    expect(secondPath, isNotNull);
    final jpgs = await File(firstPath)
        .parent
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.jpg'))
        .toList();
    expect(jpgs.length, lessThanOrEqualTo(2));
  });

  test('快速切换时间桶时截图任务串行执行', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    var running = 0;
    var peak = 0;
    final cache = LocalTimelineThumbnailCache(
      pathProvider: cachePath,
      generator: (videoPath, outputPath, position) async {
        running++;
        if (running > peak) peak = running;
        if (!started.isCompleted) {
          started.complete();
          await gate.future;
        }
        try {
          return await writeThumbnail(videoPath, outputPath, position);
        } finally {
          running--;
        }
      },
    );
    final first = cache.thumbnailAt(
      videoPath: video.path,
      position: const Duration(seconds: 5),
      duration: const Duration(minutes: 10),
    );
    await started.future;
    cache.cancelPending();
    final second = cache.thumbnailAt(
      videoPath: video.path,
      position: const Duration(minutes: 6),
      duration: const Duration(minutes: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    gate.complete();
    expect(await first, isNull);
    expect(await second, isNotNull);
    expect(peak, 1);
  });

  test('缓存检查尚未完成时取消不会启动截图', () async {
    var generated = 0;
    final cache = LocalTimelineThumbnailCache(
      pathProvider: cachePath,
      generator: (videoPath, outputPath, position) async {
        generated++;
        return writeThumbnail(videoPath, outputPath, position);
      },
    );
    final pending = cache.thumbnailAt(
      videoPath: video.path,
      position: const Duration(seconds: 5),
      duration: const Duration(minutes: 10),
    );
    cache.cancelPending();
    expect(await pending, isNull);
    expect(generated, 0);
  });

  test('生成失败时返回空值并回退普通进度条', () async {
    final cache = LocalTimelineThumbnailCache(
      pathProvider: cachePath,
      generator: (_, __, ___) async => null,
    );

    final result = await cache.thumbnailAt(
      videoPath: video.path,
      position: const Duration(seconds: 5),
      duration: const Duration(minutes: 10),
    );

    expect(result, isNull);
  });

  test('长视频按十秒采样，文件变化失效且不写视频旁目录', () async {
    final cache = LocalTimelineThumbnailCache(
        pathProvider: cachePath, generator: writeThumbnail);
    expect(
        cache.bucketFor(
            position: const Duration(seconds: 41),
            duration: const Duration(hours: 2)),
        4);
    final first = await cache.thumbnailAt(
        videoPath: video.path,
        position: const Duration(seconds: 5),
        duration: const Duration(hours: 2));
    expect(first, startsWith('${root.path}${Platform.pathSeparator}cache'));
    await video.writeAsBytes([1, 2]);
    final changed = await cache.thumbnailAt(
        videoPath: video.path,
        position: const Duration(seconds: 5),
        duration: const Duration(hours: 2));
    expect(changed, isNot(first));
    expect(
        await Directory('${root.path}/.kanyingyin_thumbs').exists(), isFalse);
  });

  test('截图器异常返回原视频路径不得移动或删除原视频', () async {
    final cache = LocalTimelineThumbnailCache(
        pathProvider: cachePath, generator: (path, _, __) async => path);
    expect(
        await cache.thumbnailAt(
            videoPath: video.path,
            position: const Duration(seconds: 1),
            duration: const Duration(minutes: 1)),
        isNull);
    expect(await video.readAsBytes(), [1]);
  });
  test('生成的大图收缩为预览尺寸而非全尺寸缓存', () async {
    final cache = LocalTimelineThumbnailCache(pathProvider: cachePath,
      generator: (_, output, __) async {
        await File(output).parent.create(recursive: true);
        await File(output).writeAsBytes(img.encodeJpg(img.Image(width: 1280, height: 720)));
        return output;
      });
    final path = await cache.thumbnailAt(videoPath: video.path, position: Duration.zero, duration: const Duration(minutes: 1));
    final decoded = img.decodeJpg(await File(path!).readAsBytes())!;
    expect(decoded.width, lessThanOrEqualTo(320));
    expect(decoded.height, lessThanOrEqualTo(320));
  });
}
