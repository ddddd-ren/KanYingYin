import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kanyingyin/services/local_media_probe.dart';
import 'package:kanyingyin/services/local_thumbnail_cache.dart';

typedef LocalTimelineThumbnailGenerator = Future<String?> Function(
  String videoPath,
  String outputPath,
  Duration position,
);

typedef LocalTimelineThumbnailPathProvider = FutureOr<String> Function(
  String videoPath,
  int bucket,
);

class LocalTimelineThumbnailCache {
  LocalTimelineThumbnailCache({
    LocalTimelineThumbnailGenerator? generator,
    LocalTimelineThumbnailPathProvider? pathProvider,
    this.maxEntries = 20,
  })  : _generator = generator ?? _defaultGenerator,
        _pathProvider =
            pathProvider ?? LocalThumbnailCache.pathForTimelineThumbnail,
        assert(maxEntries > 0);

  static Future<String?> _defaultGenerator(
    String videoPath,
    String outputPath,
    Duration position,
  ) {
    return MediaKitLocalMediaProbe().captureThumbnailAt(
      videoPath,
      outputPath,
      position: position,
    );
  }

  final LocalTimelineThumbnailGenerator _generator;
  final LocalTimelineThumbnailPathProvider _pathProvider;
  final int maxEntries;
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};
  Future<String?> _generationTail = Future<String?>.value();
  int _generation = 0;

  int bucketFor({required Duration position, required Duration duration}) {
    final durationMillis = duration.inMilliseconds;
    if (durationMillis <= 0) return 0;
    final raw = position.inMilliseconds.clamp(0, durationMillis - 1);
    return raw ~/ 10000;
  }

  Duration positionForBucket({
    required int bucket,
    required Duration duration,
  }) {
    final durationMillis = duration.inMilliseconds;
    if (durationMillis <= 0) return Duration.zero;
    final position =
        bucket.clamp(0, (durationMillis - 1) ~/ 10000) * 10000 + 5000;
    return Duration(
      milliseconds: position.clamp(0, durationMillis - 1),
    );
  }

  Future<String?> thumbnailAt({
    required String videoPath,
    required Duration position,
    required Duration duration,
  }) async {
    if (videoPath.trim().isEmpty || duration <= Duration.zero) return null;
    final token = _generation;
    final bucket = bucketFor(position: position, duration: duration);
    late final FileStat stat;
    late final String outputPath;
    try {
      stat = await File(videoPath).stat();
      if (stat.type != FileSystemEntityType.file) return null;
      outputPath = await _pathProvider(videoPath, bucket);
    } on Object {
      return null;
    }
    final cached = await _validPath(outputPath);
    if (token != _generation) return null;
    if (cached != null) return cached;

    final existing = _inFlight[outputPath];
    if (existing != null) return existing;

    final previous = _generationTail;
    final future = () async {
      await previous;
      if (token != _generation) return null;
      return _generate(
        videoPath: videoPath,
        outputPath: outputPath,
        position: positionForBucket(bucket: bucket, duration: duration),
        token: token,
        stat: stat,
      );
    }();
    _generationTail = future;
    _inFlight[outputPath] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[outputPath], future)) {
        _inFlight.remove(outputPath);
      }
    }
  }

  void cancelPending() {
    _generation++;
    _inFlight.clear();
  }

  Future<String?> _generate({
    required String videoPath,
    required String outputPath,
    required Duration position,
    required int token,
    required FileStat stat,
  }) async {
    final temporaryPath =
        '$outputPath.pending-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final generatedPath =
          await _generator(videoPath, temporaryPath, position);
      // 截图器只能交回本次指定临时文件，不接管任意返回路径。
      if (generatedPath != temporaryPath) {
        await _delete(temporaryPath);
        return null;
      }
      final current = await File(videoPath).stat();
      if (token != _generation ||
          current.size != stat.size ||
          current.modified != stat.modified) {
        await _delete(temporaryPath);
        return null;
      }
      final source = File(temporaryPath);
      if (!await source.exists() || await source.length() > 32 * 1024 * 1024) {
        await _delete(temporaryPath);
        return null;
      }
      final bytes = await source.readAsBytes();
      final thumbnail = await Isolate.run(() => _resizeThumbnail(bytes));
      final afterCapture = await File(videoPath).stat();
      if (thumbnail == null ||
          token != _generation ||
          afterCapture.size != stat.size ||
          afterCapture.modified != stat.modified) {
        await _delete(temporaryPath);
        return null;
      }
      await source.writeAsBytes(thumbnail, flush: true);
      await File(outputPath).parent.create(recursive: true);
      if (token != _generation) {
        await _delete(temporaryPath);
        return null;
      }
      if (temporaryPath != outputPath) {
        try {
          await source.rename(outputPath);
        } on FileSystemException {
          await source.copy(outputPath);
          await source.delete();
        }
      }
      if (token != _generation) {
        await _delete(outputPath);
        return null;
      }
      await _trim(outputPath);
      return outputPath;
    } on Object {
      await _delete(temporaryPath);
      return null;
    }
  }

  Future<String?> _validPath(String path) async {
    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final length = await file.length();
      if (length > 0 &&
          length <= 4 * 1024 * 1024 &&
          _decodeJpeg(await file.readAsBytes(), maxPixels: 320 * 320) != null) {
        await file.setLastModified(DateTime.now());
        return path;
      }
    } on Object {
      // 损坏或暂时不可读的缓存按未命中处理。
    }
    await _delete(path);
    return null;
  }

  Future<void> _trim(String newestPath) async {
    final directory = Directory(File(newestPath).parent.path);
    if (!await directory.exists()) return;
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.jpg')) {
        files.add(entity);
      }
    }
    if (files.length <= maxEntries) return;
    final records = <({File file, DateTime modified})>[];
    for (final file in files) {
      try {
        records.add((file: file, modified: await file.lastModified()));
      } on FileSystemException {
        records.add(
            (file: file, modified: DateTime.fromMillisecondsSinceEpoch(0)));
      }
    }
    records.sort((a, b) => a.modified.compareTo(b.modified));
    final removeCount = records.length - maxEntries;
    var removed = 0;
    for (final record in records) {
      if (removed >= removeCount) break;
      if (record.file.path == newestPath) continue;
      await _delete(record.file.path);
      removed++;
    }
  }

  Future<void> _delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 缓存清理失败不应影响播放。
    }
  }
}

img.Image? _decodeJpeg(Uint8List bytes, {required int maxPixels}) {
  final decoder = img.JpegDecoder();
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > maxPixels) {
    return null;
  }
  return decoder.decodeFrame(0);
}

Uint8List? _resizeThumbnail(Uint8List bytes) {
  try {
    final decoded = _decodeJpeg(bytes, maxPixels: 40 * 1000 * 1000);
    if (decoded == null) return null;
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longest <= 320
        ? decoded
        : img.copyResize(decoded,
            width: (decoded.width * 320 / longest).round().clamp(1, 320),
            height: (decoded.height * 320 / longest).round().clamp(1, 320));
    return img.encodeJpg(resized, quality: 80);
  } on Object {
    return null;
  }
}
