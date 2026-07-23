import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_source_editor.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_source_root_refresh_coordinator.dart';

void main() {
  testWidgets('夸克编辑器包含必要字段且不回显已有 Cookie', (tester) async {
    const source = CloudSource(
      id: 'quark-fixture',
      type: CloudSourceType.quark,
      name: '夸克媒体库',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/影视'],
    );
    final credentials = MemoryCloudCredentialStore();
    await credentials.write(
      source.id,
      const CloudCredential(cookie: 'existing-cookie-must-not-render'),
    );
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: credentials,
      ),
      credentialStore: credentials,
    );

    await tester.pumpWidget(MaterialApp(
      home: QuarkSourceEditorPage(source: source, controller: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.text('夸克网盘数据源'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '来源名称'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Cookie'), findsOneWidget);
    expect(find.text('测试登录'), findsOneWidget);
    expect(find.text('媒体根目录'), findsOneWidget);
    expect(find.text('默认转存目录'), findsOneWidget);
    expect(find.text('启用此来源'), findsOneWidget);
    final cookieFinder = find.widgetWithText(TextFormField, 'Cookie');
    final cookieField = tester.widget<TextFormField>(cookieFinder);
    final editable = tester.widget<EditableText>(
      find.descendant(of: cookieFinder, matching: find.byType(EditableText)),
    );
    expect(editable.obscureText, isTrue);
    expect(cookieField.controller?.text, isEmpty);
    expect(
        find.textContaining('existing-cookie-must-not-render'), findsNothing);
    controller.dispose();
  });

  testWidgets('夸克根目录变化刷新失败时保留配置并提示重试', (tester) async {
    const source = CloudSource(
      id: 'quark-edit-roots',
      type: CloudSourceType.quark,
      name: '夸克媒体库',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/旧目录'],
      rootRefs: <CloudRemoteRef>[
        CloudRemoteRef(id: 'old-fid', path: '/旧目录'),
      ],
    );
    final credentials = MemoryCloudCredentialStore();
    await credentials.write(
      source.id,
      const CloudCredential(cookie: 'existing-cookie'),
    );
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    await repository.save(source);
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: credentials,
      clientFactory: (_, __, ___) => _QuarkDirectoryCloudClient(),
    );
    final refreshedSourceIds = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: QuarkSourceEditorPage(
        source: source,
        controller: controller,
        onRootSelectionChanged: (sourceId) async {
          refreshedSourceIds.add(sourceId);
          throw CloudSourceRootRefreshException(
            StateError('模拟扫描失败'),
          );
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(OutlinedButton, '选择目录').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('select-new-fid')));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(refreshedSourceIds, <String>[source.id]);
    expect(
      find.text('目录已保存，但媒体库更新失败，请稍后手动重试'),
      findsOneWidget,
    );
    final saved = await repository.getById(source.id);
    expect(
      saved?.rootRefs,
      contains(const CloudRemoteRef(id: 'new-fid', path: '/影视')),
    );
    controller.dispose();
  });

  testWidgets('保存默认转存目录时自动加入媒体根目录并刷新媒体库', (tester) async {
    const source = CloudSource(
      id: 'quark-transfer-root',
      type: CloudSourceType.quark,
      name: '夸克媒体库',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/旧目录'],
      rootRefs: <CloudRemoteRef>[
        CloudRemoteRef(id: 'old-fid', path: '/旧目录'),
      ],
    );
    final credentials = MemoryCloudCredentialStore();
    await credentials.write(
      source.id,
      const CloudCredential(cookie: 'existing-cookie'),
    );
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    await repository.save(source);
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: credentials,
      clientFactory: (_, __, ___) => _QuarkDirectoryCloudClient(),
    );
    final refreshedSourceIds = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: QuarkSourceEditorPage(
        source: source,
        controller: controller,
        onRootSelectionChanged: (sourceId) async {
          refreshedSourceIds.add(sourceId);
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(OutlinedButton, '选择目录').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('select-new-fid')));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await repository.getById(source.id);
    const transferDirectory = CloudRemoteRef(id: 'new-fid', path: '/影视');
    expect(saved?.defaultTransferDirectory, transferDirectory);
    expect(saved?.rootRefs, contains(transferDirectory));
    expect(saved?.rootPaths, contains('/影视'));
    expect(refreshedSourceIds, <String>[source.id]);
    controller.dispose();
  });
}

class _QuarkDirectoryCloudClient implements CloudDriveClient {
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
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) async =>
      const <CloudFileEntry>[
        CloudFileEntry(
          id: 'new-fid',
          remotePath: '/影视',
          name: '影视',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ];

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
