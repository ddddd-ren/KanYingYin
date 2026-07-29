import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_api_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_drive_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';

void main() {
  const source = CloudSource(
    id: 'xunlei-a',
    type: CloudSourceType.xunlei,
    name: '迅雷网盘',
    baseUrl: 'https://pan.xunlei.com',
    rootPaths: <String>['/'],
  );
  const credential = CloudCredential(
    refreshToken: 'refresh-old',
    deviceId: '0123456789abcdef0123456789abcdef',
    captchaToken: 'captcha-old',
  );

  test('并发目录请求只刷新一次并更新安全凭据', () async {
    final api = _FakeXunleiApi();
    final store = MemoryCloudCredentialStore();
    await store.write(source.id, credential);
    final client = XunleiDriveClient(
      source: source,
      credentialStore: store,
      apiFactory: ({required deviceId, captchaToken}) => api,
    );

    await Future.wait(<Future<Object?>>[
      client.listDirectory(const CloudRemoteRef(id: '0', path: '/')),
      client.listDirectory(const CloudRemoteRef(id: '0', path: '/')),
    ]);

    expect(api.refreshCalls, 1);
    final saved = await store.read(source.id);
    expect(saved?.refreshToken, 'refresh-next');
    expect(saved?.deviceId, credential.deviceId);
    expect(saved?.captchaToken, 'captcha-next');
    expect(saved?.accessToken, isNull);
    await client.close();
  });

  test('分页按文件 ID 去重并构建稳定路径', () async {
    final api = _FakeXunleiApi(
      pages: <String?, XunleiDirectoryPage>{
        null: XunleiDirectoryPage(
          files: <XunleiFile>[
            _file('folder-a', '剧集', isDirectory: true),
            _file('video-a', '示例.S01E01.mkv'),
          ],
          nextPageToken: 'page-2',
        ),
        'page-2': XunleiDirectoryPage(
          files: <XunleiFile>[
            _file('video-a', '重复.mkv'),
            _file('video-b', '示例.S01E02.mkv'),
          ],
        ),
      },
    );
    final client = await _authenticatedClient(source, credential, api);

    final entries = await client.listDirectory(
      const CloudRemoteRef(id: '0', path: '/媒体'),
    );

    expect(entries.map((entry) => entry.id),
        <String>['folder-a', 'video-a', 'video-b']);
    expect(entries.map((entry) => entry.remotePath), <String>[
      '/媒体/剧集',
      '/媒体/示例.S01E01.mkv',
      '/媒体/示例.S01E02.mkv',
    ]);
    await client.close();
  });

  test('迅雷根目录兼容旧标识并以空 ID 请求接口', () async {
    final api = _FakeXunleiApi();
    final client = await _authenticatedClient(source, credential, api);

    await client.listDirectory(
      const CloudRemoteRef(id: '0', path: '/'),
    );

    expect(api.directoryIds, <String>['']);
    await client.close();
  });

  test('重复分页令牌被拒绝且不无限请求', () async {
    final api = _FakeXunleiApi(
      pages: <String?, XunleiDirectoryPage>{
        null: XunleiDirectoryPage(
          files: <XunleiFile>[_file('video-a', 'A.mkv')],
          nextPageToken: 'same',
        ),
        'same': XunleiDirectoryPage(
          files: <XunleiFile>[_file('video-b', 'B.mkv')],
          nextPageToken: 'same',
        ),
      },
    );
    final client = await _authenticatedClient(source, credential, api);

    await expectLater(
      client.listDirectory(const CloudRemoteRef(id: '0', path: '/')),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        '类型',
        CloudDriveErrorType.incompatible,
      )),
    );
    expect(api.listCalls, 2);
    await client.close();
  });

  test('播放只使用原始地址并忽略转码地址', () async {
    final api = _FakeXunleiApi();
    final client = await _authenticatedClient(source, credential, api);

    final resource = await client.resolvePlayback(
      const CloudRemoteRef(id: 'video-a', path: '/影视/A.mkv'),
    );

    expect(resource.uri,
        Uri.parse('https://download.xunlei.com/original?token=fixture'));
    expect(resource.transport, CloudPlaybackTransport.rangeRelay);
    expect(resource.networkRoute, PlaybackNetworkRoute.direct);
    expect(resource.headers['User-Agent'], isNotEmpty);
    expect(resource.uri.toString(), isNot(contains('transcode')));
    await client.close();
  });
}

Future<XunleiDriveClient> _authenticatedClient(
  CloudSource source,
  CloudCredential credential,
  _FakeXunleiApi api,
) async {
  final client = XunleiDriveClient(
    source: source,
    credentialStore: MemoryCloudCredentialStore(),
    apiFactory: ({required deviceId, captchaToken}) => api,
  );
  await client.authenticate(source, credential);
  return client;
}

XunleiFile _file(String id, String name, {bool isDirectory = false}) =>
    XunleiFile(
      id: id,
      parentId: '0',
      name: name,
      size: isDirectory ? 0 : 1024,
      modifiedAt: DateTime.utc(2026, 7, 28),
      isDirectory: isDirectory,
    );

class _FakeXunleiApi implements XunleiApi {
  _FakeXunleiApi({Map<String?, XunleiDirectoryPage>? pages})
      : pages = pages ??
            <String?, XunleiDirectoryPage>{
              null: const XunleiDirectoryPage(files: <XunleiFile>[]),
            };

  final Map<String?, XunleiDirectoryPage> pages;
  int refreshCalls = 0;
  int listCalls = 0;
  final List<String> directoryIds = <String>[];
  bool _usable = false;
  final Completer<void> _refreshStarted = Completer<void>();

  @override
  String? get captchaToken => 'captcha-next';

  @override
  bool get hasUsableSession => _usable;

  @override
  Future<XunleiSession> refresh({
    required String refreshToken,
    required String deviceId,
    String? captchaToken,
  }) async {
    refreshCalls++;
    if (!_refreshStarted.isCompleted) _refreshStarted.complete();
    await Future<void>.delayed(Duration.zero);
    _usable = true;
    return XunleiSession(
      tokenType: 'Bearer',
      accessToken: 'access-next',
      refreshToken: 'refresh-next',
      expiresAt: DateTime.utc(2030),
      userId: 'user-fixture',
    );
  }

  @override
  Future<XunleiAccount> account(XunleiSession session) async =>
      const XunleiAccount(
        userId: 'user-fixture',
        accountLabel: '138****0000',
      );

  @override
  Future<XunleiDirectoryPage> listDirectoryPage({
    required String directoryId,
    String? pageToken,
    int size = 100,
  }) async {
    listCalls++;
    directoryIds.add(directoryId);
    return pages[pageToken] ?? const XunleiDirectoryPage(files: <XunleiFile>[]);
  }

  @override
  Future<XunleiFileDetail> fileDetail(String fileId) async => XunleiFileDetail(
        file: _file(fileId, 'A.mkv'),
        originalUri: Uri.parse(
          'https://download.xunlei.com/original?token=fixture',
        ),
        transcodeUris: <Uri>[
          Uri.parse('https://media.xunlei.com/transcode?token=fixture'),
        ],
      );

  @override
  Future<XunleiSession> login({
    required String identifier,
    required String password,
    required String deviceId,
    String? captchaToken,
    String? creditKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> close() async {}
}
