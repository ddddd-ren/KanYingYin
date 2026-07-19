import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_page.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';

void main() {
  testWidgets('无来源时显示两种添加入口', (tester) async {
    final fixture = await _PageFixture.create();

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(controller: fixture.controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有可用的网盘来源'), findsOneWidget);
    expect(find.text('添加 OpenList'), findsOneWidget);
    expect(find.text('添加夸克网盘'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('显示来源、文件夹和视频且不显示字幕', (tester) async {
    final fixture = await _PageFixture.create(
      source: const CloudSource(
        id: 'quark-source',
        type: CloudSourceType.quark,
        name: '夸克媒体库',
        baseUrl: 'https://pan.quark.cn',
        rootPaths: <String>['/影视'],
        rootRefs: <CloudRemoteRef>[
          CloudRemoteRef(id: 'root-fid', path: '/影视'),
        ],
      ),
      entries: <CloudFileEntry>[
        const CloudFileEntry(
          id: 'folder-fid',
          remotePath: '/影视/动漫',
          name: '动漫',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/第01集.mkv',
          name: '第01集.mkv',
          size: 1024 * 1024 * 700,
          modifiedAt: DateTime(2026, 7, 19),
          isDirectory: false,
        ),
        const CloudFileEntry(
          id: 'subtitle-fid',
          remotePath: '/影视/第01集.ass',
          name: '第01集.ass',
          size: 1024,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(controller: fixture.controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('网盘资源'), findsOneWidget);
    expect(find.text('夸克媒体库'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    expect(find.text('第01集.mkv'), findsOneWidget);
    expect(find.text('第01集.ass'), findsNothing);
    expect(find.text('700.0 MB'), findsOneWidget);
    expect(find.text('2026-07-19'), findsOneWidget);
    expect(find.widgetWithText(TextField, '搜索当前目录'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('点击视频使用来源 ID、远程 ID 和同名字幕播放', (tester) async {
    CloudPlaybackTarget? target;
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/第01集.mkv',
          name: '第01集.mkv',
          size: 1024 * 1024 * 700,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'subtitle-fid',
          remotePath: '/影视/第01集.ass',
          name: '第01集.ass',
          size: 1024,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(
          controller: fixture.controller,
          onPlayTarget: (value) async => target = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('第01集.mkv'));
    await tester.pump();

    expect(target?.sourceId, 'quark-source');
    expect(target?.remoteId, 'video-fid');
    expect(target?.remotePath, '/影视/第01集.mkv');
    expect(target?.subtitleRemoteId, 'subtitle-fid');
    expect(target?.subtitleRemotePath, '/影视/第01集.ass');
    fixture.controller.dispose();
  });

  testWidgets('移除来源先提示不删除远程文件', (tester) async {
    String? deletedSourceId;
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(
          controller: fixture.controller,
          onDeleteSource: (sourceId) async => deletedSourceId = sourceId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除当前来源'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('不会删除网盘中的任何文件'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();
    expect(deletedSourceId, 'quark-source');
    fixture.controller.dispose();
  });
}

const _quarkSource = CloudSource(
  id: 'quark-source',
  type: CloudSourceType.quark,
  name: '夸克媒体库',
  baseUrl: 'https://pan.quark.cn',
  rootPaths: <String>['/影视'],
  rootRefs: <CloudRemoteRef>[
    CloudRemoteRef(id: 'root-fid', path: '/影视'),
  ],
);

class _PageFixture {
  const _PageFixture(this.controller);

  final CloudResourcesController controller;

  static Future<_PageFixture> create({
    CloudSource? source,
    List<CloudFileEntry> entries = const <CloudFileEntry>[],
  }) async {
    final credentials = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    if (source != null) await repository.save(source);
    final client = _PageCloudClient(entries);
    final registry = CloudProviderRegistry(
      clientFactories: <CloudSourceType, CloudProviderClientFactory>{
        CloudSourceType.openList: (_, __, ___) => client,
        CloudSourceType.quark: (_, __, ___) => client,
      },
    );
    return _PageFixture(
      CloudResourcesController(
        repository: repository,
        credentialStore: credentials,
        providerRegistry: registry,
      ),
    );
  }
}

class _PageCloudClient implements CloudDriveClient {
  const _PageCloudClient(this.entries);

  final List<CloudFileEntry> entries;

  @override
  Future<void> authenticate(CloudSource source, CloudCredential credential) =>
      throw UnimplementedError();

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<List<CloudFileEntry>> listDirectory(
    CloudRemoteRef directory,
  ) async =>
      entries;

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
