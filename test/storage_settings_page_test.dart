import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/settings/storage_settings_page.dart';
import 'package:kanyingyin/pages/error/storage_error_page.dart';
import 'package:kanyingyin/services/storage/app_data_migration_service.dart';
import 'package:kanyingyin/services/storage/storage_path_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('启动目录冲突显示具体原因而不是建议删除应用数据', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(
        home: StorageErrorPage(
      message: '应用数据目录和缓存目录不能相同或互相包含，请选择独立目录',
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('不能相同或互相包含'), findsOneWidget);
    expect(find.textContaining('尝试删除'), findsNothing);
  });

  for (final relation in ['相同', '缓存包含数据', '数据包含缓存', '符号链接', '目录联接', '独立']) {
    testWidgets('真实清理按钮保护数据库：$relation', (tester) async {
      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('kyy-clear-safety-');
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        final data = await Directory(p.join(root.path, 'data')).create();
        final database = File(p.join(data.path, 'database.hive'));
        await database.writeAsString('临时数据库');
        final media = File(p.join(root.path, 'video.mkv'));
        await media.writeAsString('临时媒体');
        var cache = data;
        if (relation == '缓存包含数据') cache = root;
        if (relation == '数据包含缓存') cache = Directory(p.join(data.path, 'cache'));
        if (relation == '独立') cache = Directory(p.join(root.path, 'cache'));
        if (relation == '符号链接') {
          final link = await Link(p.join(root.path, 'alias')).create(data.path);
          cache = Directory(link.path);
        }
        if (relation == '目录联接') {
          final linkPath = p.join(root.path, 'junction');
          final result = await Process.run(
            'cmd.exe',
            ['/c', 'mklink', '/J', linkPath, data.path],
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
          cache = Directory(linkPath);
        }
        await cache.create(recursive: true);
        final poster = File(p.join(cache.path, 'poster.jpg'));
        await poster.writeAsString('临时缓存');
        final service = _ObservedMigrationService();
        await tester.pumpWidget(MaterialApp(
          home: StorageSettingsPage(
            resolver: StoragePathResolver(
              dataRoot: data,
              cacheRoot: cache,
              configFile: File(p.join(root.path, 'startup.json')),
              legacyDataRoot: data,
              legacyCacheRoot: cache,
              isConfigured: true,
            ),
            migrationService: service,
          ),
        ));
        await tester.tap(find.text('清理缓存'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '清理'));
        await service.completed.future;
        await tester.pumpAndSettle();

        expect(await database.exists(), isTrue);
        expect(await media.exists(), isTrue);
        expect(await poster.exists(), relation != '独立');
        expect(
          find.textContaining(relation == '独立' ? '缓存已清理' : '清理失败'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    });
  }

  test('存储设置提供目录选择、迁移和安全清理入口', () {
    final source = File('lib/pages/settings/storage_settings_page.dart')
        .readAsStringSync();
    expect(source, contains("title: '存储'"));
    expect(source, contains("title: '应用数据目录'"));
    expect(source, contains("title: '缓存目录'"));
    expect(source, contains('FilePicker.getDirectoryPath('));
    expect(source, contains('saveMigrationRequest(previous: _resolver)'));
    expect(source, contains('重启后、打开数据库前安全迁移'));
    expect(source, contains('if (isCache)'));
    expect(source, contains('migrateDirectory('));
    expect(source, contains('原目录会保留为备份'));
    expect(source, contains('不会删除视频、索引、历史或刮削资料'));
  });
}

class _ObservedMigrationService extends AppDataMigrationService {
  final completed = Completer<void>();

  @override
  Future<void> clearCache(StoragePathResolver resolver) async {
    try {
      await super.clearCache(resolver);
    } finally {
      completed.complete();
    }
  }
}
