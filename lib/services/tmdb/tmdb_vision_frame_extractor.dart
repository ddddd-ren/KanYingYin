import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/local_media_probe.dart';

typedef TmdbVisionFrameCapture = Future<String?> Function(
  String videoPath,
  String outputPath,
  Duration position,
);

class TmdbVisionFrameExtractor {
  TmdbVisionFrameExtractor({
    MediaKitLocalMediaProbe? probe,
    TmdbVisionFrameCapture? captureFrame,
  })  : _probe = probe ?? MediaKitLocalMediaProbe(),
        _captureFrame = captureFrame;

  final MediaKitLocalMediaProbe _probe;
  final TmdbVisionFrameCapture? _captureFrame;

  Future<List<Uint8List>> extract(LocalMediaIndexItem item) async {
    if (!item.location.isFile || (item.durationMillis ?? 0) <= 0) {
      return const <Uint8List>[];
    }
    final source = File(item.path);
    if (!await source.exists()) return const <Uint8List>[];
    final duration = Duration(milliseconds: item.durationMillis!);
    final temp = await Directory.systemTemp.createTemp('kanyingyin-ai-');
    try {
      final frames = <Uint8List>[];
      for (final ratio in const <double>[0.1, 0.5, 0.9]) {
        final output = '${temp.path}${Platform.pathSeparator}$ratio.jpg';
        final position = Duration(
          milliseconds: (duration.inMilliseconds * ratio).round(),
        );
        final capture = _captureFrame;
        final captured = capture == null
            ? await _probe.captureThumbnailAt(
                item.path,
                output,
                position: position,
              )
            : await capture(item.path, output, position);
        if (captured == null) continue;
        final file = File(captured);
        if (!await file.exists() || await file.length() > 32 * 1024 * 1024) {
          continue;
        }
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);
        if (image == null) continue;
        final longest = image.width > image.height ? image.width : image.height;
        final resized = longest <= 512
            ? image
            : img.copyResize(
                image,
                width: (image.width * 512 / longest).round().clamp(1, 512),
                height: (image.height * 512 / longest).round().clamp(1, 512),
              );
        frames.add(Uint8List.fromList(img.encodeJpg(resized, quality: 75)));
      }
      return frames;
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
