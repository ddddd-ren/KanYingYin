import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_api_client.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_drive_client.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_models.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  const source = CloudSource(
    id: 'baidu-fixture',
    type: CloudSourceType.baidu,
    name: '百度网盘',
    baseUrl: 'https://pan.baidu.com',
    rootPaths: <String>['/影视'],
    rootRefs: <CloudRemoteRef>[
      CloudRemoteRef(id: '1000', path: '/影视'),
    ],
  );

  test('授权凭据验证成功后完整写入安全存储', () async {
    final store = MemoryCloudCredentialStore();
    final api = _FakeBaiduApi();
    final client = BaiduDriveClient(
      source: source,
      credentialStore: store,
      apiFactory: (_) => api,
    );
    final expiresAt = DateTime.utc(2026, 8, 1);
    final credential = CloudCredential(
      clientId: 'client-fixture',
      clientSecret: 'secret-fixture',
      accessToken: 'access-fixture',
      refreshToken: 'refresh-fixture',
      accessTokenExpiresAt: expiresAt,
    );

    await client.authenticate(source, credential);

    expect(api.accountCalls, 1);
    final saved = await store.read(source.id);
    expect(saved?.clientId, 'client-fixture');
    expect(saved?.accessToken, 'access-fixture');
    expect(saved?.refreshToken, 'refresh-fixture');
    expect(saved?.accessTokenExpiresAt, expiresAt);
  });

  test('Access Token 到期前五分钟刷新并原子保存新令牌', () async {
    final now = DateTime.utc(2026, 7, 21, 10);
    final store = MemoryCloudCredentialStore();
    await store.write(
      source.id,
      CloudCredential(
        clientId: 'client-fixture',
        clientSecret: 'secret-fixture',
        accessToken: 'access-old',
        refreshToken: 'refresh-old',
        accessTokenExpiresAt: now.add(const Duration(minutes: 4)),
      ),
    );
    var refreshCalls = 0;
    final apiTokens = <String>[];
    final client = BaiduDriveClient(
      source: source,
      credentialStore: store,
      now: () => now,
      tokenRefresher: ({
        required clientId,
        required clientSecret,
        required refreshToken,
      }) async {
        refreshCalls++;
        expect(clientId, 'client-fixture');
        expect(clientSecret, 'secret-fixture');
        expect(refreshToken, 'refresh-old');
        return BaiduOAuthTokens(
          accessToken: 'access-new',
          refreshToken: 'refresh-new',
          expiresAt: now.add(const Duration(days: 30)),
          scopes: <String>{'basic', 'netdisk'},
        );
      },
      apiFactory: (accessToken) {
        apiTokens.add(accessToken);
        return _FakeBaiduApi();
      },
    );

    await client.listDirectory(source.remoteRoots.single);

    expect(refreshCalls, 1);
    expect(apiTokens, <String>['access-new']);
    final refreshed = await store.read(source.id);
    expect(refreshed?.accessToken, 'access-new');
    expect(refreshed?.refreshToken, 'refresh-new');
    expect(refreshed?.clientSecret, 'secret-fixture');
  });

  test('刷新失败时保留原凭据且不创建 API 客户端', () async {
    final now = DateTime.utc(2026, 7, 21, 10);
    final original = CloudCredential(
      clientId: 'client-fixture',
      clientSecret: 'secret-fixture',
      accessToken: 'access-old',
      refreshToken: 'refresh-old',
      accessTokenExpiresAt: now,
    );
    final store = MemoryCloudCredentialStore();
    await store.write(source.id, original);
    var apiCreations = 0;
    final client = BaiduDriveClient(
      source: source,
      credentialStore: store,
      now: () => now,
      tokenRefresher: ({
        required clientId,
        required clientSecret,
        required refreshToken,
      }) async =>
          throw const CloudDriveException(
        CloudDriveErrorType.authentication,
      ),
      apiFactory: (_) {
        apiCreations++;
        return _FakeBaiduApi();
      },
    );

    await expectLater(
      client.listDirectory(source.remoteRoots.single),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        'type',
        CloudDriveErrorType.authentication,
      )),
    );

    expect(apiCreations, 0);
    final preserved = await store.read(source.id);
    expect(preserved?.accessToken, 'access-old');
    expect(preserved?.refreshToken, 'refresh-old');
  });

  test('并发请求共享同一个令牌刷新任务', () async {
    final now = DateTime.utc(2026, 7, 21, 10);
    final store = MemoryCloudCredentialStore();
    await store.write(
      source.id,
      CloudCredential(
        clientId: 'client-fixture',
        clientSecret: 'secret-fixture',
        accessToken: 'access-old',
        refreshToken: 'refresh-old',
        accessTokenExpiresAt: now,
      ),
    );
    var refreshCalls = 0;
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    final client = BaiduDriveClient(
      source: source,
      credentialStore: store,
      now: () => now,
      tokenRefresher: ({
        required clientId,
        required clientSecret,
        required refreshToken,
      }) async {
        refreshCalls++;
        if (!refreshStarted.isCompleted) refreshStarted.complete();
        await releaseRefresh.future;
        return BaiduOAuthTokens(
          accessToken: 'access-new',
          refreshToken: 'refresh-new',
          expiresAt: now.add(const Duration(days: 30)),
          scopes: <String>{'basic', 'netdisk'},
        );
      },
      apiFactory: (_) => _FakeBaiduApi(),
    );

    final first = client.listDirectory(source.remoteRoots.single);
    await refreshStarted.future;
    final second = client.listDirectory(source.remoteRoots.single);
    await Future<void>.delayed(Duration.zero);
    releaseRefresh.complete();
    await Future.wait(<Future<Object?>>[first, second]);

    expect(refreshCalls, 1);
  });

  test('目录项使用 fs_id 作为稳定 ID 并保留官方路径', () async {
    final store = await _authorizedStore();
    final client = BaiduDriveClient(
      source: source,
      credentialStore: store,
      apiFactory: (_) => _FakeBaiduApi(entries: <BaiduFileEntry>[
        BaiduFileEntry(
          fsId: '1001',
          path: '/影视/示例.mkv',
          name: '示例.mkv',
          size: 4096,
          modifiedAt: DateTime.utc(2026, 7, 21),
          isDirectory: false,
        ),
      ]),
    );

    final entries = await client.listDirectory(source.remoteRoots.single);

    expect(entries.single.id, '1001');
    expect(entries.single.remotePath, '/影视/示例.mkv');
    expect(entries.single.size, 4096);
  });

  test('百度原文件声明使用公共 Range 中转且不传播放器请求头', () async {
    final store = await _authorizedStore();
    final client = BaiduDriveClient(
      source: source,
      credentialStore: store,
      apiFactory: (_) => _FakeBaiduApi(
        details: BaiduFileDetails(
          fsId: '1002',
          path: '/影视/示例电影.mkv',
          name: '示例电影.mkv',
          size: 4294967296,
          modifiedAt: DateTime.utc(2026, 7, 21),
          isDirectory: false,
          downloadUri: Uri.parse(
            'https://download.baidu-fixture.invalid/original?sign=fixture',
          ),
        ),
      ),
    );

    final resource = await client.resolvePlayback(
      const CloudRemoteRef(id: '1002', path: '/影视/示例电影.mkv'),
    );

    expect(resource.uri.scheme, 'https');
    expect(resource.headers, isEmpty);
    expect(resource.networkRoute, PlaybackNetworkRoute.direct);
    expect(resource.transport, CloudPlaybackTransport.rangeRelay);
  });

  test('文件详情鉴权失效时强制刷新令牌后重新获取 dlink', () async {
    final store = await _authorizedStore();
    var refreshCalls = 0;
    final apiTokens = <String>[];
    final client = BaiduDriveClient(
      source: source,
      credentialStore: store,
      tokenRefresher: ({
        required clientId,
        required clientSecret,
        required refreshToken,
      }) async {
        refreshCalls++;
        return BaiduOAuthTokens(
          accessToken: 'access-refreshed',
          refreshToken: 'refresh-refreshed',
          expiresAt: DateTime.utc(2099, 2),
          scopes: <String>{'basic', 'netdisk'},
        );
      },
      apiFactory: (accessToken) {
        apiTokens.add(accessToken);
        return _FakeBaiduApi(
          fileDetailsError: accessToken == 'access-fixture'
              ? const CloudDriveException(
                  CloudDriveErrorType.authentication,
                )
              : null,
          details: BaiduFileDetails(
            fsId: '1002',
            path: '/影视/示例电影.mkv',
            name: '示例电影.mkv',
            size: 4096,
            modifiedAt: DateTime.utc(2026, 7, 21),
            isDirectory: false,
            downloadUri: Uri.parse(
              'https://d.pcs.baidu.com/file/refreshed',
            ),
          ),
        );
      },
    );

    final resource = await client.resolvePlayback(
      const CloudRemoteRef(id: '1002', path: '/影视/示例电影.mkv'),
    );

    expect(resource.uri.host, 'd.pcs.baidu.com');
    expect(refreshCalls, 1);
    expect(apiTokens, <String>['access-fixture', 'access-refreshed']);
    expect((await store.read(source.id))?.refreshToken, 'refresh-refreshed');
  });
}

Future<MemoryCloudCredentialStore> _authorizedStore() async {
  final store = MemoryCloudCredentialStore();
  await store.write(
    'baidu-fixture',
    CloudCredential(
      clientId: 'client-fixture',
      clientSecret: 'secret-fixture',
      accessToken: 'access-fixture',
      refreshToken: 'refresh-fixture',
      accessTokenExpiresAt: DateTime.utc(2099),
    ),
  );
  return store;
}

class _FakeBaiduApi implements BaiduApi {
  _FakeBaiduApi({
    this.entries = const <BaiduFileEntry>[],
    this.details,
    this.fileDetailsError,
  });

  final List<BaiduFileEntry> entries;
  final BaiduFileDetails? details;
  final Object? fileDetailsError;
  int accountCalls = 0;

  @override
  Future<BaiduAccount> account() async {
    accountCalls++;
    return const BaiduAccount(
      displayName: 'account_fixture',
      userId: '123456789',
      vipType: 2,
    );
  }

  @override
  Future<void> close() async {}

  @override
  Future<BaiduFileDetails> fileDetails(
    CloudRemoteRef file, {
    required bool includeDownloadLink,
  }) async {
    final error = fileDetailsError;
    if (error != null) throw error;
    return details ??
        BaiduFileDetails(
          fsId: file.id,
          path: file.path,
          name: file.path.split('/').last,
          size: 0,
          modifiedAt: DateTime.utc(2026, 7, 21),
          isDirectory: false,
        );
  }

  @override
  Future<List<BaiduFileEntry>> listDirectory(CloudRemoteRef directory) async =>
      entries;
}
