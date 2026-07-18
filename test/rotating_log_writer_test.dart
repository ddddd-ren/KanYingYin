import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanyingyin_logs_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('日志达到阈值后轮转且只保留十个文件', () async {
    final writer = RotatingLogWriter(
      directoryProvider: () async => tempDir,
      maxBytes: 64,
      maxFiles: 10,
    );

    for (var i = 0; i < 30; i++) {
      await writer.write('line-$i-${'x' * 32}');
    }
    await writer.flush();

    final files = await writer.listLogFiles();
    expect(files, hasLength(10));
    expect(
      files.any((file) => file.path.endsWith('kanyingyin.log')),
      isTrue,
    );
  });

  test('并发日志通过串行队列完整写入', () async {
    final writer = RotatingLogWriter(
      directoryProvider: () async => tempDir,
      maxBytes: 1024 * 1024,
    );

    await Future.wait([
      for (var i = 0; i < 100; i++) writer.write('parallel-line-$i'),
    ]);
    await writer.flush();

    final active =
        File('${tempDir.path}${Platform.pathSeparator}kanyingyin.log');
    final lines = await active.readAsLines();
    expect(lines, hasLength(100));
    expect(lines.toSet(), hasLength(100));
  });

  test('日志目录不可用时写入不会抛到业务层', () async {
    final writer = RotatingLogWriter(
      directoryProvider: () async => throw const FileSystemException('拒绝访问'),
    );

    await expectLater(writer.write('still-running'), completes);
    await expectLater(writer.flush(), completes);
    expect(await writer.tryGetDirectory(), isNull);
  });
}
