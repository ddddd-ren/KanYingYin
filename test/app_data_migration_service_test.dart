import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/storage/app_data_migration_service.dart';
import 'package:kanyingyin/services/storage/storage_path_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  for (final suffix in ['migrating', 'backup']) {
    test('迁移保留名称碰撞不得删除原数据库：$suffix', () async {
      final root =
          await Directory.systemTemp.createTemp('kyy-migrate-collision-');
      addTearDown(() => root.delete(recursive: true));
      final target = await Directory(p.join(root.path, 'data')).create();
      final source = await Directory('${target.path}.$suffix').create();
      final database = File(p.join(source.path, 'database.hive'));
      await database.writeAsString('原数据库');

      await expectLater(
        const AppDataMigrationService()
            .migrateDirectory(source: source, target: target),
        throwsA(isA<StorageMigrationException>()),
      );

      expect(await database.readAsString(), '原数据库');
      expect(await target.exists(), isTrue);
    });
  }

  for (final protectedFile in ['video.MKV', 'database.hive', 'startup.json']) {
    test('独立缓存混有受保护文件时拒绝清理：$protectedFile', () async {
      final root =
          await Directory.systemTemp.createTemp('kyy-cache-ownership-');
      addTearDown(() => root.delete(recursive: true));
      final cache = await Directory(p.join(root.path, 'cache')).create();
      final protected = File(p.join(cache.path, protectedFile));
      await protected.writeAsString('受保护的临时文件');
      final poster = File(p.join(cache.path, 'poster.jpg'));
      await poster.writeAsString('临时缓存');
      final data = Directory(p.join(root.path, 'data'));
      final resolver = StoragePathResolver(
        dataRoot: data,
        cacheRoot: cache,
        configFile: protectedFile == 'startup.json'
            ? protected
            : File(p.join(root.path, 'startup.json')),
        legacyDataRoot: data,
        legacyCacheRoot: cache,
      );

      await expectLater(
        const AppDataMigrationService().clearCache(resolver),
        throwsA(isA<Exception>()),
      );

      expect(await protected.readAsString(), '受保护的临时文件');
      expect(await poster.exists(), isTrue);
    });
  }

  test('危险配置迁移在任何复制或配置写入前拒绝', () async {
    final root = await Directory.systemTemp.createTemp('kyy-migration-safety-');
    addTearDown(() => root.delete(recursive: true));
    final source = await Directory(p.join(root.path, 'source')).create();
    final database = File(p.join(source.path, 'database.hive'));
    await database.writeAsString('临时数据库');
    final target = Directory(p.join(root.path, 'target'));
    final config = File(p.join(root.path, 'startup.json'));
    await config.writeAsString('原配置');
    final resolver = StoragePathResolver(
      dataRoot: target,
      cacheRoot: target,
      configFile: config,
      legacyDataRoot: source,
      legacyCacheRoot: Directory(p.join(root.path, 'old-cache')),
    );

    await expectLater(
      const AppDataMigrationService().migrateResolver(resolver),
      throwsA(isA<Exception>()),
    );
    expect(await target.exists(), isFalse);
    expect(await database.readAsString(), '临时数据库');
    expect(await config.readAsString(), '原配置');
  });

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
    final data = await Directory(p.join(root.path, 'cache-data')).create();
    final database = File(p.join(data.path, 'database.hive'));
    await database.writeAsString('临时数据库');
    await cache.create(recursive: true);
    await File('${cache.path}\\poster.jpg').writeAsBytes(<int>[1, 2, 3]);
    await media.writeAsBytes(<int>[4, 5, 6]);
    await Link(p.join(cache.path, 'data-link')).create(data.path);
    await Link(p.join(cache.path, 'media-link')).create(media.path);

    await const AppDataMigrationService().clearCache(StoragePathResolver(
      dataRoot: data,
      cacheRoot: cache,
      configFile: File(p.join(root.path, 'startup.json')),
      legacyDataRoot: Directory(p.join(root.path, 'old-data')),
      legacyCacheRoot: cache,
    ));

    expect(await cache.exists(), isFalse);
    expect(await media.exists(), isTrue);
    expect(await database.readAsString(), '临时数据库');
  });
}
