import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/storage/app_data_migration_service.dart';

void main() {
  test('迁移复制文件并校验清单，源目录保持不变', () async {
    final root = await Directory.systemTemp.createTemp('kanyingyin-migrate-');
    addTearDown(() => root.delete(recursive: true));
    final source = Directory('${root.path}\\source');
    final target = Directory('${root.path}\\target');
    await Directory('${source.path}\\hive').create(recursive: true);
    await File('${source.path}\\hive\\setting.hive').writeAsString('设置数据');

    final result = await const AppDataMigrationService().migrateDirectory(
      source: source,
      target: target,
    );

    expect(result.fileCount, 1);
    expect(result.byteCount, greaterThan(0));
    expect(await File('${target.path}\\hive\\setting.hive').readAsString(),
        '设置数据');
    expect(await File('${source.path}\\hive\\setting.hive').exists(), isTrue);
  });

  test('清理缓存不会删除媒体目录', () async {
    final root = await Directory.systemTemp.createTemp('kanyingyin-cache-');
    addTearDown(() => root.delete(recursive: true));
    final cache = Directory('${root.path}\\cache');
    final media = File('${root.path}\\video.mkv');
    await cache.create(recursive: true);
    await File('${cache.path}\\poster.jpg').writeAsBytes(<int>[1, 2, 3]);
    await media.writeAsBytes(<int>[4, 5, 6]);

    await const AppDataMigrationService().clearCache(cache);

    expect(await cache.exists(), isFalse);
    expect(await media.exists(), isTrue);
  });
}
