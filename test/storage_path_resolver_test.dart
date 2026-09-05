import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/storage/storage_path_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('启动读取危险迁移配置时拒绝且不静默回写或迁移', () async {
    final root = await Directory.systemTemp.createTemp('kyy-startup-safety-');
    addTearDown(() => root.delete(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
      'getApplicationSupportDirectory' => root.path,
      'getApplicationCacheDirectory' => p.join(root.path, 'system-cache'),
      _ => null,
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final config = File(p.join(root.path, 'storage-startup.json'));
    final original = jsonEncode(StorageStartupConfig(
      dataRoot: p.join(root.path, 'data'),
      cacheRoot: p.join(root.path, 'data'),
      migrationState: 'pending',
      lastSuccessfulDataRoot: p.join(root.path, 'old-data'),
      lastSuccessfulCacheRoot: p.join(root.path, 'old-cache'),
    ).toJson());
    await config.writeAsString(original);

    await expectLater(StoragePathResolver.load(), throwsA(isA<FileSystemException>()));

    expect(await config.readAsString(), original);
    expect(await Directory(p.join(root.path, 'data')).exists(), isFalse);
  });

  for (final relation in ['相同', '缓存包含数据', '数据包含缓存', '大小写与规范化', '符号链接', '目录联接']) {
    test('拒绝保存危险目录：$relation，保留已有配置和文件', () async {
      final root = await Directory.systemTemp.createTemp('kyy-path-safety-');
      addTearDown(() => root.delete(recursive: true));
      final data = await Directory(p.join(root.path, 'data')).create();
      final database = File(p.join(data.path, 'database.hive'));
      await database.writeAsString('临时数据库');
      var cache = data;
      if (relation == '缓存包含数据') cache = root;
      if (relation == '数据包含缓存') cache = Directory(p.join(data.path, 'cache'));
      if (relation == '大小写与规范化') {
        cache = Directory(p.join(data.path.toUpperCase(), '.', 'child', '..'));
      }
      if (relation == '符号链接') {
        final link = await Link(p.join(root.path, 'alias')).create(data.path);
        cache = Directory(p.join(link.path, 'not-created'));
      }
      if (relation == '目录联接') {
        final linkPath = p.join(root.path, 'junction');
        final result = await Process.run('cmd.exe', ['/c', 'mklink', '/J', linkPath, data.path]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        cache = Directory(p.join(linkPath, 'not-created'));
      }
      final config = File(p.join(root.path, 'startup.json'));
      await config.writeAsString('原配置');
      final resolver = StoragePathResolver(
        dataRoot: data,
        cacheRoot: cache,
        configFile: config,
        legacyDataRoot: data,
        legacyCacheRoot: cache,
      );

      await expectLater(resolver.save(), throwsA(isA<Exception>()));
      await expectLater(
        resolver.saveMigrationRequest(previous: resolver),
        throwsA(isA<Exception>()),
      );
      expect(await config.readAsString(), '原配置');
      expect(await database.readAsString(), '临时数据库');
    });
  }

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
