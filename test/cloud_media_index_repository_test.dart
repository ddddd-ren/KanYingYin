import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  test('旧索引字幕路径迁移为可持久化远程引用', () async {
    final storage = _SeededCloudMediaIndexStorage(<String, Object?>{
      'items': <Object?>[
        <String, Object?>{
          'sourceId': 'openlist-fixture',
          'remoteId': '/动漫/示例.mkv',
          'remotePath': '/动漫/示例.mkv',
          'name': '示例.mkv',
          'size': 10485760,
          'seriesName': '示例',
          'mediaType': 'movie',
          'subtitlePaths': <String>['/动漫/示例.zh-CN.srt'],
        },
      ],
    });

    final items = await CloudMediaIndexRepository(storage: storage)
        .getBySource('openlist-fixture');

    expect(items, hasLength(1));
    expect(
      items.single.subtitleRefs,
      const <CloudRemoteRef>[
        CloudRemoteRef(
          id: '/动漫/示例.zh-CN.srt',
          path: '/动漫/示例.zh-CN.srt',
        ),
      ],
    );
  });
}

class _SeededCloudMediaIndexStorage implements CloudMediaIndexStorage {
  _SeededCloudMediaIndexStorage(this.value);

  Map<String, Object?> value;

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<Map<String, Object?>> read() async => value;

  @override
  Future<void> write(Map<String, Object?> value) async {
    this.value = value;
  }
}
