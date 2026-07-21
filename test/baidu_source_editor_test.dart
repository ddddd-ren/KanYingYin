import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/baidu/baidu_directory_picker.dart';
import 'package:kanyingyin/pages/cloud/baidu/baidu_source_editor.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_authorization_controller.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_models.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_oauth_client.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  testWidgets('百度来源先授权再选择多个媒体目录', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BaiduSourceEditorPage()),
    );

    expect(find.text('打开百度授权'), findsOneWidget);
    expect(find.text('选择目录'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择目录'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('编辑百度来源不回显任何已保存凭据且已授权时允许选目录', (tester) async {
    const source = CloudSource(
      id: 'baidu-fixture',
      type: CloudSourceType.baidu,
      name: '百度媒体库',
      baseUrl: 'https://pan.baidu.com',
      rootPaths: <String>['/影视'],
      rootRefs: <CloudRemoteRef>[
        CloudRemoteRef(id: '1001', path: '/影视'),
      ],
    );
    final credentials = MemoryCloudCredentialStore();
    await credentials.write(source.id, _authorizedCredential);
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: credentials,
      ),
      credentialStore: credentials,
    );

    await tester.pumpWidget(MaterialApp(
      home: BaiduSourceEditorPage(
        source: source,
        controller: controller,
        credentialStore: credentials,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('client-existing'), findsNothing);
    expect(find.textContaining('secret-existing'), findsNothing);
    expect(find.textContaining('access-existing'), findsNothing);
    expect(find.text('API Key 已配置'), findsOneWidget);
    expect(find.text('Secret Key 已配置'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择目录'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'API Key'),
      'client-replacement',
    );
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择目录'),
          )
          .onPressed,
      isNull,
    );
    controller.dispose();
  });

  testWidgets('完成授权后清空密钥输入并启用目录选择', (tester) async {
    final gateway = _EditorOAuthGateway();
    final authorizationController = BaiduAuthorizationController(
      oauthFactory: ({required clientId, required clientSecret}) => gateway,
      accountLoader: (_) async => const BaiduAccount(
        displayName: '测试账号',
        userId: '10001',
        vipType: 0,
      ),
      stateGenerator: () => 'state-fixture',
    );
    Uri? openedUri;

    await tester.pumpWidget(MaterialApp(
      home: BaiduSourceEditorPage(
        authorizationController: authorizationController,
        launchAuthorizationUrl: (uri) async {
          openedUri = uri;
          return true;
        },
      ),
    ));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'API Key'),
      'client-new',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Secret Key'),
      'secret-new',
    );
    await tester.tap(find.text('打开百度授权'));
    await tester.pump();
    expect(openedUri?.queryParameters['state'], 'state-fixture');

    await tester.enterText(
      find.widgetWithText(TextFormField, '授权码'),
      'code-fixture',
    );
    await tester.tap(find.text('完成授权'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'API Key'),
          )
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Secret Key'),
          )
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.text('API Key 已配置'), findsOneWidget);
    expect(find.text('Secret Key 已配置'), findsOneWidget);
    expect(find.text('已授权：测试账号'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择目录'),
          )
          .onPressed,
      isNotNull,
    );
    authorizationController.dispose();
  });

  testWidgets('百度目录选择器按 fs_id 导航并返回多个目录引用', (tester) async {
    const source = CloudSource(
      id: 'baidu-picker',
      type: CloudSourceType.baidu,
      name: '百度网盘',
      baseUrl: 'https://pan.baidu.com',
      rootPaths: <String>[],
    );
    final credentials = MemoryCloudCredentialStore();
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: credentials,
      ),
      credentialStore: credentials,
      clientFactory: (_, __, ___) => _DirectoryClient(),
    );
    List<CloudRemoteRef>? selected;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            selected = await Navigator.of(context).push<List<CloudRemoteRef>>(
              MaterialPageRoute(
                builder: (_) => BaiduDirectoryPickerPage(
                  source: source,
                  controller: controller,
                  credential: _authorizedCredential,
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

    expect(find.text('动漫'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('Show.mkv'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('select-2002')));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(
      selected,
      <CloudRemoteRef>[
        const CloudRemoteRef(id: '2002', path: '/电影'),
      ],
    );
    controller.dispose();
  });
}

final CloudCredential _authorizedCredential = CloudCredential(
  clientId: 'client-existing',
  clientSecret: 'secret-existing',
  accessToken: 'access-existing',
  refreshToken: 'refresh-existing',
  accessTokenExpiresAt: DateTime.utc(2026, 8, 21),
);

class _DirectoryClient implements CloudDriveClient {
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
          id: '2001',
          remotePath: '/动漫',
          name: '动漫',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: '2002',
          remotePath: '/电影',
          name: '电影',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: '2003',
          remotePath: '/Show.mkv',
          name: 'Show.mkv',
          size: 1024,
          modifiedAt: null,
          isDirectory: false,
        ),
      ];

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}

class _EditorOAuthGateway implements BaiduOAuthGateway {
  @override
  Uri buildAuthorizationUri({required String state}) => Uri.https(
        'openapi.baidu.com',
        '/oauth/2.0/authorize',
        <String, String>{'state': state},
      );

  @override
  Future<BaiduOAuthTokens> exchangeCode(String code) async => BaiduOAuthTokens(
        accessToken: 'access-new',
        refreshToken: 'refresh-new',
        expiresAt: DateTime.utc(2026, 8, 21),
        scopes: <String>{'basic', 'netdisk'},
      );

  @override
  Future<BaiduOAuthTokens> refresh(String refreshToken) =>
      throw UnimplementedError();
}
