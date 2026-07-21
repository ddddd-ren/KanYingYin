import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/about/about_page.dart';
import 'package:kanyingyin/services/local_image_cache_service.dart';

void main() {
  test('递归统计缓存并完整清理', () async {
    final root = await Directory.systemTemp.createTemp('image_cache_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final nested = Directory('${root.path}${Platform.pathSeparator}nested');
    await nested.create();
    await File('${root.path}${Platform.pathSeparator}a.bin')
        .writeAsBytes(List<int>.filled(3, 1));
    await File('${nested.path}${Platform.pathSeparator}b.bin')
        .writeAsBytes(List<int>.filled(5, 2));
    final service = LocalImageCacheService(
      directoryProvider: () async => root,
    );

    expect(await service.sizeBytes(), 8);
    await service.clear();
    expect(await service.sizeBytes(), 0);
    expect(await root.exists(), isFalse);
  });

  test('缓存目录不存在时清理成功', () async {
    final parent = await Directory.systemTemp.createTemp('image_cache_none_');
    addTearDown(() => parent.delete(recursive: true));
    final missing = Directory(
      '${parent.path}${Platform.pathSeparator}missing',
    );
    final service = LocalImageCacheService(
      directoryProvider: () async => missing,
    );

    await service.clear();
    expect(await service.sizeBytes(), 0);
  });

  test('清理失败转换为页面可处理的安全结果', () async {
    final service = LocalImageCacheService(
      directoryProvider: () async => throw const FileSystemException('拒绝访问'),
    );

    expect(await service.tryClear(), isFalse);
  });

  test('关于页面使用统一缓存服务', () {
    final service = LocalImageCacheService(
      directoryProvider: () async => Directory.systemTemp,
    );

    final page = AboutPage(cacheService: service);

    expect(page.cacheService, same(service));
  });
}
