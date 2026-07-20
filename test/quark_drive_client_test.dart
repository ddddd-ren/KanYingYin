import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/quark/quark_api_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_models.dart';

void main() {
  const source = CloudSource(
    id: 'quark-fixture',
    type: CloudSourceType.quark,
    name: '夸克网盘',
    baseUrl: 'https://pan.quark.cn',
    rootPaths: <String>['/影视'],
    rootRefs: <CloudRemoteRef>[
      CloudRemoteRef(id: 'fid_fixture_root', path: '/影视'),
    ],
  );

  test('Cookie 验证成功后写入注入的凭据存储', () async {
    final store = MemoryCloudCredentialStore();
    final api = _FakeQuarkApi(account: const QuarkAccount(nickname: 'fixture'));
    final client = QuarkDriveClient(
      source: source,
      credentialStore: store,
      apiFactory: (_) => api,
    );

    await client.authenticate(
      source,
      const CloudCredential(cookie: 'session=cookie-fixture'),
    );

    expect(api.accountCalls, 1);
    expect((await store.read(source.id))?.cookie, 'session=cookie-fixture');
  });

  test('目录按 fid 分页、去重并保留展示路径', () async {
    final store = MemoryCloudCredentialStore();
    await store.write(
      source.id,
      const CloudCredential(cookie: 'session=cookie-fixture'),
    );
    final api = _FakeQuarkApi(pages: <int, QuarkDirectoryPage>{
      1: _page(<QuarkFile>[
        _file('fid-a', 'A.mkv'),
        _file('fid-b', 'B.mkv'),
      ], page: 1, total: 3),
      2: _page(<QuarkFile>[
        _file('fid-b', 'B.mkv'),
        _file('fid-c', 'C.srt'),
      ], page: 2, total: 3),
    });
    final client = QuarkDriveClient(
      source: source,
      credentialStore: store,
      apiFactory: (_) => api,
    );

    final entries = await client.listDirectory(source.remoteRoots.single);

    expect(api.requestedDirectoryIds,
        <String>['fid_fixture_root', 'fid_fixture_root']);
    expect(
        entries.map((entry) => entry.id), <String>['fid-a', 'fid-b', 'fid-c']);
    expect(entries.first.remotePath, '/影视/A.mkv');
  });

  test('空目录正常返回，重复页明确报接口不兼容', () async {
    final store = MemoryCloudCredentialStore();
    await store.write(
      source.id,
      const CloudCredential(cookie: 'session=cookie-fixture'),
    );
    final emptyClient = QuarkDriveClient(
      source: source,
      credentialStore: store,
      apiFactory: (_) => _FakeQuarkApi(
        pages: <int, QuarkDirectoryPage>{
          1: _page(const <QuarkFile>[], page: 1, total: 0),
        },
      ),
    );
    expect(await emptyClient.listDirectory(source.remoteRoots.single), isEmpty);

    final repeated =
        _page(<QuarkFile>[_file('fid-a', 'A.mkv')], page: 1, total: 10);
    final repeatedClient = QuarkDriveClient(
      source: source,
      credentialStore: store,
      apiFactory: (_) => _FakeQuarkApi(
        fallbackPage: repeated,
      ),
    );
    await expectLater(
      repeatedClient.listDirectory(source.remoteRoots.single),
      throwsA(isA<CloudDriveException>().having(
          (error) => error.type, 'type', CloudDriveErrorType.incompatible)),
    );
  });

  test('播放使用持久化文件 ID 且不向转码 CDN 透传 API 请求头', () async {
    final store = MemoryCloudCredentialStore();
    await store.write(
      source.id,
      const CloudCredential(cookie: 'session=cookie-fixture'),
    );
    final api = _FakeQuarkApi(
      playback: QuarkPlaybackLink(
        fileId: 'fid_fixture_video',
        uri: Uri.parse('https://media.quark-fixture.invalid/video'),
      ),
    );
    final client = QuarkDriveClient(
      source: source,
      credentialStore: store,
      apiFactory: (_) => api,
    );

    final resource = await client.resolvePlayback(const CloudRemoteRef(
      id: 'fid_fixture_video',
      path: '/影视/示例.mkv',
    ));

    expect(api.requestedPlaybackIds, <String>['fid_fixture_video']);
    expect(resource.headers, isEmpty);
    expect(resource.networkRoute, PlaybackNetworkRoute.direct);
  });
}

QuarkDirectoryPage _page(
  List<QuarkFile> items, {
  required int page,
  required int total,
}) =>
    QuarkDirectoryPage(items: items, page: page, size: 2, total: total);

QuarkFile _file(String id, String name) => QuarkFile(
      id: id,
      name: name,
      isDirectory: false,
      size: 1024,
      modifiedAt: DateTime.utc(2026, 7, 19),
      category: 1,
    );

class _FakeQuarkApi implements QuarkApi {
  _FakeQuarkApi({
    this.account = const QuarkAccount(nickname: 'fixture'),
    this.pages = const <int, QuarkDirectoryPage>{},
    this.fallbackPage,
    this.playback,
  });

  final QuarkAccount account;
  final Map<int, QuarkDirectoryPage> pages;
  final QuarkDirectoryPage? fallbackPage;
  final QuarkPlaybackLink? playback;
  int accountCalls = 0;
  final List<String> requestedDirectoryIds = <String>[];
  final List<String> requestedPlaybackIds = <String>[];

  @override
  Future<void> close() async {}

  @override
  Future<QuarkAccount> getAccount() async {
    accountCalls++;
    return account;
  }

  @override
  Future<QuarkDirectoryPage> listDirectoryPage({
    required String directoryId,
    required int page,
    int size = 50,
  }) async {
    requestedDirectoryIds.add(directoryId);
    return pages[page] ?? fallbackPage!;
  }

  @override
  Future<QuarkPlaybackLink> resolvePlayback(String fileId) async {
    requestedPlaybackIds.add(fileId);
    return playback!;
  }
}
