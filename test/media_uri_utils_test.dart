import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/media_uri_utils.dart';

void main() {
  test('MediaUriUtils converts local paths to playable file URI', () {
    final path =
        Platform.isWindows ? r'D:\动画 文件\第 01 集.mkv' : '/tmp/动画 文件/第 01 集.mkv';

    final uri = MediaUriUtils.toPlayableUri(path, isLocalPlayback: true);

    expect(uri, startsWith('file:'));
    expect(uri, contains('%20'));
  });

  test('MediaUriUtils keeps existing URI and online URLs unchanged', () {
    const fileUri = 'file:///D:/Anime/01.mkv';
    const httpUrl = 'https://example.com/video.m3u8';

    expect(
      MediaUriUtils.toPlayableUri(fileUri, isLocalPlayback: true),
      fileUri,
    );
    expect(
      MediaUriUtils.toPlayableUri(httpUrl, isLocalPlayback: false),
      httpUrl,
    );
  });
}
