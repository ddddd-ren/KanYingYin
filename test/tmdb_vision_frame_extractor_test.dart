import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_frame_extractor.dart';

void main() {
  test('本地抽帧最多三张并缩小到 512 像素以内', () async {
    final directory = await Directory.systemTemp.createTemp('vision-frames');
    final video = File('${directory.path}${Platform.pathSeparator}episode.mkv');
    await video.writeAsBytes(<int>[1, 2, 3]);
    final positions = <Duration>[];
    String? frameDirectory;
    final extractor = TmdbVisionFrameExtractor(
      captureFrame: (path, output, position) async {
        positions.add(position);
        frameDirectory = File(output).parent.path;
        await File(output).writeAsBytes(
          img.encodeJpg(img.Image(width: 800, height: 600)),
        );
        return output;
      },
    );

    final frames = await extractor.extract(
      LocalMediaIndexItem(
        path: video.path,
        name: 'episode.mkv',
        parentPath: directory.path,
        sourcePath: directory.path,
        size: 3,
        modified: DateTime(2026),
        seriesName: '剧名',
        durationMillis: 100000,
        indexedAt: DateTime(2026),
      ),
    );

    expect(frames, hasLength(3));
    expect(positions, <Duration>[
      const Duration(milliseconds: 10000),
      const Duration(milliseconds: 50000),
      const Duration(milliseconds: 90000),
    ]);
    for (final frame in frames) {
      final decoded = img.decodeJpg(frame)!;
      expect(decoded.width <= 512 && decoded.height <= 512, isTrue);
    }
    expect(Directory(frameDirectory!).existsSync(), isFalse);
    await directory.delete(recursive: true);
  });
}
