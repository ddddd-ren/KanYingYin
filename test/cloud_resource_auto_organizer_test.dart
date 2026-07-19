import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_auto_organizer.dart';

void main() {
  test('递归发现独立影片电影文件夹和剧集并跳过分类与季目录', () async {
    final client = _TreeClient(<String, List<CloudFileEntry>>{
      'root': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'standalone',
          remotePath: '/影视/根目录电影.mkv',
          name: '根目录电影.mkv',
          size: 100,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'movie',
          remotePath: '/影视/电影文件夹',
          name: '电影文件夹',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'category',
          remotePath: '/影视/科幻分类',
          name: '科幻分类',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'series',
          remotePath: '/影视/剧集名称',
          name: '剧集名称',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'subtitle',
          remotePath: '/影视/根目录电影.ass',
          name: '根目录电影.ass',
          size: 10,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
      'movie': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'movie-file',
          remotePath: '/影视/电影文件夹/电影文件.mkv',
          name: '电影文件.mkv',
          size: 100,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
      'category': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'nested',
          remotePath: '/影视/科幻分类/分类中的电影',
          name: '分类中的电影',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
      'nested': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'nested-file',
          remotePath: '/影视/科幻分类/分类中的电影/正片.mp4',
          name: '正片.mp4',
          size: 100,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
      'series': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'season',
          remotePath: '/影视/剧集名称/第一季',
          name: '第一季',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
      'season': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'episode',
          remotePath: '/影视/剧集名称/第一季/S01E01.mkv',
          name: 'S01E01.mkv',
          size: 100,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
    });

    final result = await const CloudResourceAutoOrganizer().discover(
      source: _source,
      client: client,
    );

    expect(
      result.candidates.map((item) => item.displayName),
      containsAll(<String>[
        '根目录电影.mkv',
        '电影文件夹',
        '分类中的电影',
        '剧集名称',
      ]),
    );
    expect(result.candidates, hasLength(4));
    expect(client.listedIds, isNot(contains('season')));
    expect(result.scannedDirectories, 5);
    expect(result.failedDirectories, 0);
  });

  test('多根目录去重并在单个分支失败后继续扫描', () async {
    final client = _TreeClient(
      <String, List<CloudFileEntry>>{
        'root-a': const <CloudFileEntry>[
          CloudFileEntry(
            id: 'same-video',
            remotePath: '/共享/同一部电影.mkv',
            name: '同一部电影.mkv',
            size: 100,
            modifiedAt: null,
            isDirectory: false,
          ),
          CloudFileEntry(
            id: 'shared',
            remotePath: '/共享/电影文件夹',
            name: '电影文件夹',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
          CloudFileEntry(
            id: 'broken',
            remotePath: '/共享/损坏分支',
            name: '损坏分支',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        ],
        'root-b': const <CloudFileEntry>[
          CloudFileEntry(
            id: 'same-video',
            remotePath: '/共享/同一部电影.mkv',
            name: '同一部电影.mkv',
            size: 100,
            modifiedAt: null,
            isDirectory: false,
          ),
          CloudFileEntry(
            id: 'shared',
            remotePath: '/共享/电影文件夹',
            name: '电影文件夹',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
          CloudFileEntry(
            id: 'movie-b',
            remotePath: '/另一个根/另一部电影',
            name: '另一部电影',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        ],
        'shared': const <CloudFileEntry>[
          CloudFileEntry(
            id: 'shared-file',
            remotePath: '/共享/电影文件夹/正片.mkv',
            name: '正片.mkv',
            size: 100,
            modifiedAt: null,
            isDirectory: false,
          ),
        ],
        'movie-b': const <CloudFileEntry>[
          CloudFileEntry(
            id: 'movie-b-file',
            remotePath: '/另一个根/另一部电影/正片.mp4',
            name: '正片.mp4',
            size: 100,
            modifiedAt: null,
            isDirectory: false,
          ),
        ],
      },
      failedIds: const <String>{'broken'},
    );
    const source = CloudSource(
      id: 'source',
      type: CloudSourceType.quark,
      name: '双根媒体库',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/共享', '/另一个根'],
      rootRefs: <CloudRemoteRef>[
        CloudRemoteRef(id: 'root-a', path: '/共享'),
        CloudRemoteRef(id: 'root-b', path: '/另一个根'),
      ],
    );

    final result = await const CloudResourceAutoOrganizer().discover(
      source: source,
      client: client,
    );

    expect(
      result.candidates.map((item) => item.displayName),
      <String>['同一部电影.mkv', '电影文件夹', '另一部电影'],
    );
    expect(result.scannedDirectories, 5);
    expect(result.failedDirectories, 1);
    expect(client.listedIds.where((id) => id == 'shared'), hasLength(1));
  });

  test('所有配置根目录读取失败时明确失败', () async {
    final client = _TreeClient(
      const <String, List<CloudFileEntry>>{},
      failedIds: const <String>{'root-a', 'root-b'},
    );
    const source = CloudSource(
      id: 'source',
      type: CloudSourceType.openList,
      name: '不可用媒体库',
      baseUrl: 'https://example.com',
      rootPaths: <String>['/一', '/二'],
      rootRefs: <CloudRemoteRef>[
        CloudRemoteRef(id: 'root-a', path: '/一'),
        CloudRemoteRef(id: 'root-b', path: '/二'),
      ],
    );

    await expectLater(
      const CloudResourceAutoOrganizer().discover(
        source: source,
        client: client,
      ),
      throwsA(
        isA<CloudDriveException>().having(
          (error) => error.type,
          'type',
          CloudDriveErrorType.network,
        ),
      ),
    );
    expect(client.listedIds, <String>['root-a', 'root-b']);
  });

  test('目录数量和深度超过安全上限时停止', () async {
    final countClient = _TreeClient(<String, List<CloudFileEntry>>{
      'root': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'child',
          remotePath: '/影视/分类',
          name: '分类',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
    });
    await expectLater(
      const CloudResourceAutoOrganizer(maximumDirectories: 1).discover(
        source: _source,
        client: countClient,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('目录数量超过 1 个'),
        ),
      ),
    );

    final depthClient = _TreeClient(<String, List<CloudFileEntry>>{
      'root': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'level-1',
          remotePath: '/影视/一级',
          name: '一级',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
      'level-1': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'level-2',
          remotePath: '/影视/一级/二级',
          name: '二级',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
    });
    await expectLater(
      const CloudResourceAutoOrganizer(maximumDepth: 1).discover(
        source: _source,
        client: depthClient,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('目录深度超过 1 层'),
        ),
      ),
    );
  });

  test('中文和英文季目录都归并为父级剧集', () async {
    final client = _TreeClient(<String, List<CloudFileEntry>>{
      'root': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'series-cn',
          remotePath: '/影视/中文剧集',
          name: '中文剧集',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'series-en',
          remotePath: '/影视/英文剧集',
          name: '英文剧集',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'series-short',
          remotePath: '/影视/短季名剧集',
          name: '短季名剧集',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
      'series-cn': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'season-cn',
          remotePath: '/影视/中文剧集/第一季',
          name: '第一季',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
      'series-en': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'season-en',
          remotePath: '/影视/英文剧集/Season 1',
          name: 'Season 1',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
      'series-short': const <CloudFileEntry>[
        CloudFileEntry(
          id: 'season-short',
          remotePath: '/影视/短季名剧集/S01',
          name: 'S01',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
    });

    final result = await const CloudResourceAutoOrganizer().discover(
      source: _source,
      client: client,
    );

    expect(
      result.candidates.map((item) => item.displayName),
      <String>['中文剧集', '英文剧集', '短季名剧集'],
    );
    expect(client.listedIds, isNot(contains('season-cn')));
    expect(client.listedIds, isNot(contains('season-en')));
    expect(client.listedIds, isNot(contains('season-short')));
  });
}

const _source = CloudSource(
  id: 'source',
  type: CloudSourceType.quark,
  name: '夸克媒体库',
  baseUrl: 'https://pan.quark.cn',
  rootPaths: <String>['/影视'],
  rootRefs: <CloudRemoteRef>[CloudRemoteRef(id: 'root', path: '/影视')],
);

class _TreeClient implements CloudDriveClient {
  _TreeClient(
    this.entriesById, {
    this.failedIds = const <String>{},
  });

  final Map<String, List<CloudFileEntry>> entriesById;
  final Set<String> failedIds;
  final List<String> listedIds = <String>[];

  @override
  Future<void> authenticate(CloudSource source, CloudCredential credential) =>
      throw UnimplementedError();

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) async {
    listedIds.add(directory.id);
    if (failedIds.contains(directory.id)) {
      throw const CloudDriveException(CloudDriveErrorType.network);
    }
    return entriesById[directory.id] ?? const <CloudFileEntry>[];
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
