import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/storage/storage_path_resolver.dart';

void main() {
  test('Windows 首次存储默认不依赖固定 D 盘路径', () {
    final source = File(
      'lib/services/storage/storage_path_resolver.dart',
    ).readAsStringSync();
    expect(source, contains('legacyData.parent'));
    expect(source, contains('legacyCache.path'));
    expect(source, isNot(contains("Directory(r'D:\\看影音')")));
  });

  test('启动配置读写保留数据和缓存目录', () {
    const config = StorageStartupConfig(
      dataRoot: r'D:\看影音\数据',
      cacheRoot: r'D:\看影音\缓存',
      migrationState: 'ready',
    );
    final restored = StorageStartupConfig.fromJson(
      jsonDecode(jsonEncode(config.toJson())),
    );
    expect(restored.dataRoot, config.dataRoot);
    expect(restored.cacheRoot, config.cacheRoot);
    expect(restored.migrationState, 'ready');
  });

  test('旧配置缺少目录时拒绝读取', () {
    expect(
      () => StorageStartupConfig.fromJson(const <String, Object?>{
        'dataRoot': r'D:\看影音\数据',
      }),
      throwsFormatException,
    );
  });

  test('解析器暴露稳定的 Hive 和图片缓存子目录', () async {
    final root = await Directory.systemTemp.createTemp('kanyingyin-path-');
    addTearDown(() => root.delete(recursive: true));
    final resolver = StoragePathResolver(
      dataRoot: Directory('${root.path}\\data'),
      cacheRoot: Directory('${root.path}\\cache'),
      configFile: File('${root.path}\\startup.json'),
      legacyDataRoot: Directory('${root.path}\\legacy-data'),
      legacyCacheRoot: Directory('${root.path}\\legacy-cache'),
    );
    expect(resolver.hiveRoot.path, endsWith(r'\data\hive'));
    expect(resolver.imageCacheRoot.path, endsWith(r'\cache\images'));
  });

  test('数据目录迁移请求保留上一个成功目录作为重启迁移源', () async {
    final root = await Directory.systemTemp.createTemp('kanyingyin-pending-');
    addTearDown(() => root.delete(recursive: true));
    final previous = StoragePathResolver(
      dataRoot: Directory('${root.path}\\old-data'),
      cacheRoot: Directory('${root.path}\\old-cache'),
      configFile: File('${root.path}\\startup.json'),
      legacyDataRoot: Directory('${root.path}\\legacy-data'),
      legacyCacheRoot: Directory('${root.path}\\legacy-cache'),
      isConfigured: true,
    );
    final requested = previous.copyWith(
      dataRoot: Directory('${root.path}\\new-data'),
    );

    await requested.saveMigrationRequest(previous: previous);

    final config = StorageStartupConfig.fromJson(
      jsonDecode(await requested.configFile.readAsString()),
    );
    expect(config.migrationState, 'pending');
    expect(config.dataRoot, requested.dataRoot.path);
    expect(config.lastSuccessfulDataRoot, previous.dataRoot.path);
    expect(config.lastSuccessfulCacheRoot, previous.cacheRoot.path);

    final restored = StoragePathResolver.fromStartupConfig(
      config: config,
      configFile: requested.configFile,
      fallbackDataRoot: previous.legacyDataRoot,
      fallbackCacheRoot: previous.legacyCacheRoot,
    );
    expect(restored.hasPendingMigration, isTrue);
    expect(restored.legacyDataRoot.path, previous.dataRoot.path);
    expect(restored.legacyCacheRoot.path, previous.cacheRoot.path);
  });
}
