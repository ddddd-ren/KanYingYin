import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/local_custom_cover_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('保存自定义封面会替换已有 cover 文件并保留图片扩展名', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_custom_cover_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video = File(p.join(tempDir.path, 'episode.mkv'));
    final image = File(p.join(tempDir.path, 'selected.png'));
    final previousCover = File(p.join(tempDir.path, 'cover.jpg'));
    await video.writeAsString('video');
    await image.writeAsBytes([1, 2, 3]);
    await previousCover.writeAsString('old cover');

    final result = await LocalCustomCoverService().saveForVideo(
      videoPath: video.path,
      imagePath: image.path,
    );

    expect(result, p.join(tempDir.path, 'cover.png'));
    expect(await File(result!).readAsBytes(), [1, 2, 3]);
    expect(await previousCover.exists(), isFalse);
  });

  test('选择当前封面时仍能保留封面文件', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_custom_cover_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video = File(p.join(tempDir.path, 'episode.mkv'));
    final cover = File(p.join(tempDir.path, 'cover.jpg'));
    await video.writeAsString('video');
    await cover.writeAsBytes([4, 5, 6]);

    final result = await LocalCustomCoverService().saveForVideo(
      videoPath: video.path,
      imagePath: cover.path,
    );

    expect(result, cover.path);
    expect(await cover.readAsBytes(), [4, 5, 6]);
  });
}
