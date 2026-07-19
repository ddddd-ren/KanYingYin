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
  _TreeClient(this.entriesById);

  final Map<String, List<CloudFileEntry>> entriesById;
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
    return entriesById[directory.id] ?? const <CloudFileEntry>[];
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
