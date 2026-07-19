import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  group('CloudRemoteRef', () {
    test('同时保存文件 ID 和展示路径并支持 JSON 往返', () {
      const reference = CloudRemoteRef(
        id: 'fid_fixture_video',
        path: '/动漫/示例.S01E01.mkv',
      );

      expect(CloudRemoteRef.fromJson(reference.toJson()), reference);
      expect(reference.toString(), contains('fid_fixture_video'));
      expect(reference.toString(), contains('/动漫/示例.S01E01.mkv'));
    });

    test('旧来源只有 rootPaths 时生成按路径工作的远程引用', () {
      final source = CloudSource.fromJson(<String, Object?>{
        'id': 'openlist-fixture',
        'type': 'openList',
        'name': '旧 OpenList',
        'baseUrl': 'https://openlist.example.invalid',
        'rootPaths': <String>['/动漫'],
      });

      expect(
        source.remoteRoots,
        const <CloudRemoteRef>[
          CloudRemoteRef(id: '/动漫', path: '/动漫'),
        ],
      );
    });

    test('新来源持久化根目录 ID 且普通配置不包含 Cookie', () {
      const source = CloudSource(
        id: 'quark-fixture',
        type: CloudSourceType.quark,
        name: '夸克网盘',
        baseUrl: 'https://pan.quark.cn',
        rootPaths: <String>['/影视'],
        rootRefs: <CloudRemoteRef>[
          CloudRemoteRef(id: 'fid_fixture_root', path: '/影视'),
        ],
        defaultTransferDirectory: CloudRemoteRef(
          id: 'fid_fixture_target',
          path: '/接收',
        ),
      );

      final json = source.toJson();

      expect(json['rootRefs'], <Map<String, String>>[
        <String, String>{'id': 'fid_fixture_root', 'path': '/影视'},
      ]);
      expect(json.toString().toLowerCase(), isNot(contains('cookie')));
      expect(CloudSource.fromJson(json).remoteRoots, source.remoteRoots);
      expect(
        CloudSource.fromJson(json).defaultTransferDirectory,
        source.defaultTransferDirectory,
      );
    });

    test('云盘客户端的目录、文件和播放接口统一接收远程引用', () async {
      final client = _RemoteRefCloudClient();
      const reference = CloudRemoteRef(id: 'fid_fixture', path: '/示例');

      await client.listDirectory(reference);
      await client.getFile(reference);
      await client.resolvePlayback(reference);

      expect(client.received, <CloudRemoteRef>[
        reference,
        reference,
        reference,
      ]);
    });
  });
}

class _RemoteRefCloudClient implements CloudDriveClient {
  final List<CloudRemoteRef> received = <CloudRemoteRef>[];

  @override
  Future<void> authenticate(
      CloudSource source, CloudCredential credential) async {}

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) async {
    received.add(file);
    return CloudFileEntry(
      id: file.id,
      remotePath: file.path,
      name: '示例',
      size: 0,
      modifiedAt: null,
      isDirectory: false,
    );
  }

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) async {
    received.add(directory);
    return const <CloudFileEntry>[];
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) async {
    received.add(file);
    return CloudPlaybackResource(
        uri: Uri.parse('https://media.example.invalid'));
  }
}
