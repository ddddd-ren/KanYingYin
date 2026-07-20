import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/pages/cloud/openlist_directory_picker.dart';
import 'package:kanyingyin/pages/cloud/openlist_source_editor.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/settings/cloud_sources_settings.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_share_import_action.dart';

void main() {
  testWidgets('网盘来源设置页显示入口和空状态', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CloudSourcesSettingsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('网盘数据源'), findsOneWidget);
    expect(find.text('添加网盘来源'), findsOneWidget);
    expect(find.text('还没有添加网盘数据源'), findsOneWidget);
  });

  testWidgets('添加菜单包含 OpenList 和夸克网盘', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CloudSourcesSettingsPage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加网盘来源'));
    await tester.pumpAndSettle();

    expect(find.text('添加 OpenList'), findsOneWidget);
    expect(find.text('添加夸克网盘'), findsOneWidget);
  });

  testWidgets('只有存在可用夸克来源时显示分享导入操作', (tester) async {
    final storage = MemoryCloudSourceStorage();
    final credentials = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: storage,
      credentialStore: credentials,
    );
    const source = CloudSource(
      id: 'quark-fixture',
      type: CloudSourceType.quark,
      name: '夸克媒体库',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/影视'],
    );
    await repository.save(source);
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: credentials,
    );
    await tester.pumpWidget(MaterialApp(
      home: CloudSourcesSettingsPage(controller: controller),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('导入夸克分享'), findsNothing);

    await credentials.write(
      source.id,
      const CloudCredential(cookie: 'cookie-fixture'),
    );
    await controller.load();
    await tester.pumpAndSettle();
    expect(find.byTooltip('导入夸克分享'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('媒体库导入操作只在存在可用夸克来源时显示', (tester) async {
    final storage = MemoryCloudSourceStorage();
    final credentials = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: storage,
      credentialStore: credentials,
    );
    const source = CloudSource(
      id: 'quark-library-fixture',
      type: CloudSourceType.quark,
      name: '夸克媒体库',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/影视'],
    );
    await repository.save(source);
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: credentials,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuarkShareImportAction(controller: controller),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('导入夸克分享'), findsNothing);

    await credentials.write(
      source.id,
      const CloudCredential(cookie: 'cookie-fixture'),
    );
    await controller.load();
    await tester.pumpAndSettle();
    expect(find.byTooltip('导入夸克分享'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('网盘来源列表不会展示地址中内嵌的凭据', (tester) async {
    final storage = MemoryCloudSourceStorage();
    final credentials = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: storage,
      credentialStore: credentials,
    );
    await repository.save(const CloudSource(
      id: 'legacy-source',
      type: CloudSourceType.openList,
      name: '旧数据源',
      baseUrl: 'https://secret-user:secret-pass@drive.example.com',
      rootPaths: ['/'],
    ));
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: credentials,
    );

    await tester.pumpWidget(MaterialApp(
      home: CloudSourcesSettingsPage(controller: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('secret-user'), findsNothing);
    expect(find.textContaining('secret-pass'), findsNothing);
    expect(find.text('https://drive.example.com'), findsOneWidget);
  });

  test('生产设置路由为列表页和编辑页注入同一个控制器单例', () {
    final source =
        File('lib/pages/settings/settings_module.dart').readAsStringSync();

    expect(
      source,
      contains(
        'CloudSourcesSettingsPage(\n'
        '        controller: Modular.get<CloudLibraryController>(),',
      ),
    );
    expect(source, contains('"/cloud-sources/add"'));
    expect(source, contains('"/cloud-sources/openlist/edit"'));
    expect(source, contains('"/cloud-sources/quark/edit"'));
    expect(source, contains('"/cloud-sources/quark/import"'));
    expect(source, contains('"/cloud-sources/edit"'));
    expect(
      source,
      contains(
        'onSourceDeleted: '
        'Modular.get<LocalController>().reloadCloudLibraryIndex,',
      ),
    );
    expect(
      source,
      contains(
        'OpenListSourceEditorPage(\n'
        '        controller: Modular.get<CloudLibraryController>(),',
      ),
    );
    expect(
      RegExp(
        r'onRootSelectionChanged:\s*Modular\.get<'
        r'CloudSourceRootRefreshCoordinator>\(\)\.refreshSource',
      ).allMatches(source),
      hasLength(3),
    );
  });

  testWidgets('设置页销毁时不会销毁外部共享控制器', (tester) async {
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: MemoryCloudCredentialStore(),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: CloudSourcesSettingsPage(controller: controller),
    ));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    void listener() {}
    expect(() => controller.addListener(listener), returnsNormally);
    controller.removeListener(listener);
    controller.dispose();
  });

  testWidgets('设置页使用共享控制器删除时等待扫描退出且不回写索引', (tester) async {
    const source = CloudSource(
      id: 'shared-source',
      type: CloudSourceType.openList,
      name: '共享网盘',
      baseUrl: 'https://drive.example.com',
      rootPaths: ['/'],
    );
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await sourceRepository.save(source);
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      source.id,
      [
        CloudMediaIndexItem(
          sourceId: source.id,
          remoteId: 'episode-1',
          remotePath: '/Show/E01.mkv',
          name: 'E01.mkv',
          size: 1024,
          modifiedAt: DateTime(2026),
          seriesName: 'Show',
          seasonNumber: 1,
          episodeNumber: 1,
          mediaType: CloudMediaType.episode,
        ),
      ],
      const {},
      const {},
      const ['/'],
    );
    final localController = LocalController(
      cloudSourceRepository: sourceRepository,
      cloudMediaIndexRepository: indexRepository,
    );
    await localController.reloadCloudLibraryIndex();
    expect(localController.cloudLibraryItems, hasLength(1));
    final started = Completer<void>();
    final release = Completer<void>();
    final controller = CloudLibraryController(
      repository: sourceRepository,
      credentialStore: MemoryCloudCredentialStore(),
      mediaIndexRepository: indexRepository,
      mediaIndexer: CloudMediaIndexer(repository: indexRepository),
      posterCacheCleaner: (_) async {},
      subtitleCacheCleaner: (_) async {},
      clientFactory: (_, __, ___) => _BlockingCloudClient(started, release),
    );
    final scan = controller.scanSource(source.id);
    await started.future;
    await tester.pumpWidget(MaterialApp(
      home: CloudSourcesSettingsPage(
        controller: controller,
        onSourceDeleted: localController.reloadCloudLibraryIndex,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除数据源'));
    await tester.pump();
    expect(await sourceRepository.getById(source.id), isNotNull);
    release.complete();
    expect((await scan).cancelled, isTrue);
    await tester.pumpAndSettle();

    expect(await sourceRepository.getById(source.id), isNull);
    expect(await indexRepository.getBySource(source.id), isEmpty);
    expect(localController.cloudLibraryItems, isEmpty);
    controller.dispose();
  });

  testWidgets('网盘来源列表可扫描单个来源并刷新媒体库', (tester) async {
    const source = CloudSource(
      id: 'scan-source',
      type: CloudSourceType.openList,
      name: '家庭网盘',
      baseUrl: 'https://drive.example.com',
      rootPaths: <String>['/'],
    );
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(source);
    final client = _DirectoryCloudClient();
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: MemoryCloudCredentialStore(),
      mediaIndexer: CloudMediaIndexer(
        repository: CloudMediaIndexRepository(
          storage: MemoryCloudMediaIndexStorage(),
        ),
      ),
      clientFactory: (_, __, ___) => client,
    );
    var reloads = 0;

    await tester.pumpWidget(MaterialApp(
      home: CloudSourcesSettingsPage(
        controller: controller,
        onSourceScanned: (_) async => reloads++,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('扫描数据源'));
    await tester.pumpAndSettle();

    expect(client.listedPaths, contains('/'));
    expect(reloads, 1);
    expect(find.text('网盘媒体扫描完成'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('网盘来源列表显示上次扫描的媒体和失败统计', (tester) async {
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(CloudSource(
      id: 'summary-source',
      type: CloudSourceType.openList,
      name: '家庭网盘',
      baseUrl: 'https://drive.example.com',
      rootPaths: const <String>['/动漫'],
      scanStatus: CloudScanStatus.completed,
      lastScannedAt: DateTime(2026, 7, 15, 20, 30),
      indexedVideoCount: 12,
      matchedSubtitleCount: 8,
      lastScanFailureCount: 2,
    ));
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: MemoryCloudCredentialStore(),
    );

    await tester.pumpWidget(MaterialApp(
      home: CloudSourcesSettingsPage(controller: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('12 个视频'), findsOneWidget);
    expect(find.textContaining('8 个字幕'), findsOneWidget);
    expect(find.textContaining('2 个目录失败'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('OpenList 编辑器显示必要字段且密码默认留空', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OpenListSourceEditorPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('OpenList 数据源'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '名称'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '地址'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '用户名'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '密码'), findsOneWidget);
    expect(find.text('允许自签名证书'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    final password = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, '密码'),
    );
    expect(password.controller?.text, isEmpty);
  });

  testWidgets('OpenList 编辑器拒绝非 HTTP 地址和带凭据地址', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OpenListSourceEditorPage()),
    );

    await tester.enterText(find.widgetWithText(TextFormField, '名称'), '家庭网盘');
    final address = find.widgetWithText(TextFormField, '地址');
    await tester.enterText(address, 'ftp://drive.example.com');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('仅支持 HTTP 或 HTTPS 地址'), findsOneWidget);

    await tester.enterText(address, 'https://user:pass@drive.example.com');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('地址不能包含用户名或密码'), findsOneWidget);
  });

  testWidgets('OpenList 编辑器选择并保存多个扫描目录', (tester) async {
    const source = CloudSource(
      id: 'edit-directory-source',
      type: CloudSourceType.openList,
      name: '家庭网盘',
      baseUrl: 'https://drive.example.com',
      rootPaths: <String>['/动漫'],
      scanStatus: CloudScanStatus.completed,
      indexedVideoCount: 9,
      matchedSubtitleCount: 4,
    );
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(source);
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: MemoryCloudCredentialStore(),
      clientFactory: (_, __, ___) => _DirectoryCloudClient(),
    );
    final refreshedSourceIds = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: OpenListSourceEditorPage(
        source: source,
        controller: controller,
        onRootSelectionChanged: (sourceId) async {
          refreshedSourceIds.add(sourceId);
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('/动漫'), findsOneWidget);
    await tester.tap(find.text('选择扫描目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('select-/电影')));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await repository.getById(source.id);
    expect(saved?.rootPaths, <String>['/动漫', '/电影']);
    expect(saved?.scanStatus, CloudScanStatus.completed);
    expect(saved?.indexedVideoCount, 9);
    expect(saved?.matchedSubtitleCount, 4);
    expect(refreshedSourceIds, <String>[source.id]);
    controller.dispose();
  });

  testWidgets('OpenList 更新媒体库期间禁用保存和目录选择', (tester) async {
    const source = CloudSource(
      id: 'busy-directory-source',
      type: CloudSourceType.openList,
      name: '家庭网盘',
      baseUrl: 'https://drive.example.com',
      rootPaths: <String>['/动漫'],
    );
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(source);
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: MemoryCloudCredentialStore(),
      clientFactory: (_, __, ___) => _DirectoryCloudClient(),
    );
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();

    await tester.pumpWidget(MaterialApp(
      home: OpenListSourceEditorPage(
        source: source,
        controller: controller,
        onRootSelectionChanged: (_) async {
          refreshStarted.complete();
          await releaseRefresh.future;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择扫描目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('select-/电影')));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await refreshStarted.future;
    await tester.pump();

    expect(find.text('正在更新媒体库'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '选择扫描目录'))
          .onPressed,
      isNull,
    );

    releaseRefresh.complete();
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets('OpenList 只修改名称时不触发媒体库刷新', (tester) async {
    const source = CloudSource(
      id: 'rename-only-source',
      type: CloudSourceType.openList,
      name: '家庭网盘',
      baseUrl: 'https://drive.example.com',
      rootPaths: <String>['/动漫'],
    );
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(source);
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: MemoryCloudCredentialStore(),
    );
    var refreshCount = 0;

    await tester.pumpWidget(MaterialApp(
      home: OpenListSourceEditorPage(
        source: source,
        controller: controller,
        onRootSelectionChanged: (_) async => refreshCount++,
      ),
    ));
    await tester.enterText(
      find.widgetWithText(TextFormField, '名称'),
      '仅修改来源名称',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(refreshCount, 0);
    expect((await repository.getById(source.id))?.name, '仅修改来源名称');
    controller.dispose();
  });

  testWidgets('新建来源浏览目录前不会提前保存表单', (tester) async {
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: MemoryCloudCredentialStore(),
      clientFactory: (_, __, ___) => _DirectoryCloudClient(),
    );
    await tester.pumpWidget(MaterialApp(
      home: OpenListSourceEditorPage(controller: controller),
    ));
    await tester.enterText(find.widgetWithText(TextFormField, '名称'), '家庭网盘');
    await tester.enterText(
      find.widgetWithText(TextFormField, '地址'),
      'https://drive.example.com',
    );

    await tester.tap(find.text('选择扫描目录'));
    await tester.pumpAndSettle();

    expect(find.text('选择扫描目录'), findsOneWidget);
    expect(await repository.getAll(), isEmpty);
    controller.dispose();
  });

  testWidgets('OpenList 目录选择页只显示文件夹并返回多选路径', (tester) async {
    const source = CloudSource(
      id: 'directory-source',
      type: CloudSourceType.openList,
      name: '家庭网盘',
      baseUrl: 'https://drive.example.com',
      rootPaths: <String>['/动漫'],
    );
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(source);
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: MemoryCloudCredentialStore(),
      clientFactory: (_, __, ___) => _DirectoryCloudClient(),
    );
    List<String>? selected;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            selected = await Navigator.of(context).push<List<String>>(
              MaterialPageRoute(
                builder: (_) => OpenListDirectoryPickerPage(
                  source: source,
                  controller: controller,
                ),
              ),
            );
          },
          child: const Text('打开'),
        );
      }),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('选择扫描目录'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('Show.mkv'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('select-/电影')));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(selected, <String>['/动漫', '/电影']);
    controller.dispose();
  });
}

class _DirectoryCloudClient implements CloudDriveClient {
  final List<String> listedPaths = <String>[];

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) async {
    listedPaths.add(directory.path);
    return <CloudFileEntry>[
      const CloudFileEntry(
        id: 'anime',
        remotePath: '/动漫',
        name: '动漫',
        size: 0,
        modifiedAt: null,
        isDirectory: true,
      ),
      const CloudFileEntry(
        id: 'movies',
        remotePath: '/电影',
        name: '电影',
        size: 0,
        modifiedAt: null,
        isDirectory: true,
      ),
      const CloudFileEntry(
        id: 'video',
        remotePath: '/Show.mkv',
        name: 'Show.mkv',
        size: 1024,
        modifiedAt: null,
        isDirectory: false,
      ),
    ];
  }

  @override
  Future<void> authenticate(
      CloudSource source, CloudCredential credential) async {}

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}

class _BlockingCloudClient implements CloudDriveClient {
  _BlockingCloudClient(this.started, this.release);

  final Completer<void> started;
  final Completer<void> release;

  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {}

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return const <CloudFileEntry>[];
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
