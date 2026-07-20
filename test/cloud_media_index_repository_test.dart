import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  test('索引往返保留作品边界原名虚拟名和规则版本', () async {
    final repository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    final item = CloudMediaIndexItem(
      sourceId: 'quark-a',
      remoteId: 'episode-1',
      remotePath: '/影视/作品/第三季/01.mkv',
      name: '01.mkv',
      remoteName: '01.mkv',
      displayName: '规范剧名 S03E01.mkv',
      workKey: 'quark-a|work|work-id',
      workRootId: 'work-id',
      workRootPath: '/影视/作品',
      size: 200,
      modifiedAt: null,
      seriesName: '规范剧名',
      seasonNumber: 3,
      episodeNumber: 1,
      mediaType: CloudMediaType.episode,
      recognitionVersion: CloudMediaIndexItem.currentRecognitionVersion,
      releaseTags: const MediaReleaseTags(
        resolution: '2160p',
        source: 'Web-DL',
        codec: 'H265',
        dynamicRange: <String>['DV', 'HDR'],
        audio: <String>['DDP 5.1', 'Atmos'],
      ),
    );

    await repository.replaceSource(
      'quark-a',
      <CloudMediaIndexItem>[item],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/影视'],
    );
    final restored = (await repository.getBySource('quark-a')).single;

    expect(restored.remoteName, '01.mkv');
    expect(restored.displayName, '规范剧名 S03E01.mkv');
    expect(restored.workKey, 'quark-a|work|work-id');
    expect(restored.workRootId, 'work-id');
    expect(restored.workRootPath, '/影视/作品');
    expect(restored.releaseTags.resolution, '2160p');
    expect(restored.releaseTags.dynamicRange, <String>['DV', 'HDR']);
    expect(restored.needsRecognitionRefresh, isFalse);
  });

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
    expect(items.single.remoteName, '示例.mkv');
    expect(items.single.displayName, '示例.mkv');
    expect(items.single.recognitionVersion, 0);
    expect(items.single.needsRecognitionRefresh, isTrue);
  });

  test('更新虚拟标题和 TMDB 时不丢失作品身份字段', () {
    final item = CloudMediaIndexItem(
      sourceId: 'quark-a',
      remoteId: 'episode-1',
      remotePath: '/影视/作品/第三季/01.mkv',
      name: '01.mkv',
      remoteName: '01.mkv',
      displayName: '旧标题 S03E01.mkv',
      workKey: 'quark-a|work|work-id',
      workRootId: 'work-id',
      workRootPath: '/影视/作品',
      size: 200,
      modifiedAt: null,
      seriesName: '旧标题',
      seasonNumber: 3,
      episodeNumber: 1,
      mediaType: CloudMediaType.episode,
      releaseTags: const MediaReleaseTags(resolution: '2160p'),
    );

    final updated = item
        .withEffectiveWorkTitle('新标题')
        .replaceTmdb(tmdbId: 42, tmdbTitle: '新标题');

    expect(updated.displayName, '新标题 S03E01.mkv');
    expect(updated.seriesName, '新标题');
    expect(updated.remoteName, '01.mkv');
    expect(updated.workKey, item.workKey);
    expect(updated.workRootId, item.workRootId);
    expect(updated.workRootPath, item.workRootPath);
    expect(updated.recognitionVersion, item.recognitionVersion);
    expect(updated.releaseTags.resolution, '2160p');
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
