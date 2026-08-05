import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/modules/cloud/cloud_hidden_video.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/repositories/cloud_hidden_video_repository.dart';

void main() {
  test('分类聚合会按原网盘隐藏记录过滤远程 ID 和标准化路径', () async {
    final repository = CloudHiddenVideoRepository(
      storage: MemoryCloudHiddenVideoStorage(<Object?>[
        const CloudHiddenVideo(
          sourceId: 'quark',
          remoteId: 'hidden-by-id',
          remotePath: '/电影/按ID隐藏.mkv',
          fileName: '按ID隐藏.mkv',
        ).toJson(),
        const CloudHiddenVideo(
          sourceId: 'openlist',
          remoteId: '',
          remotePath: r'\动漫\按路径隐藏.mkv\',
          fileName: '按路径隐藏.mkv',
        ).toJson(),
      ]),
    );
    final state = MediaCategoryHiddenVideoState(repository: repository);
    await state.load(const <String>['quark', 'openlist']);

    final visible = state.visibleCloudItems(<CloudMediaIndexItem>[
      _cloudItem(
        sourceId: 'quark',
        remoteId: 'hidden-by-id',
        remotePath: '/电影/另一个路径.mkv',
      ),
      _cloudItem(
        sourceId: 'openlist',
        remoteId: '',
        remotePath: '/动漫/按路径隐藏.mkv',
      ),
      _cloudItem(
        sourceId: 'quark',
        remoteId: 'visible',
        remotePath: '/电影/保留.mkv',
      ),
    ]).toList(growable: false);

    expect(visible.map((item) => item.remoteId), <String>['visible']);
  });

  test('从分类菜单隐藏视频会写入原网盘仓储使用的稳定身份', () async {
    final repository = CloudHiddenVideoRepository(
      storage: MemoryCloudHiddenVideoStorage(),
    );
    final state = MediaCategoryHiddenVideoState(repository: repository);
    await state.load(const <String>['quark']);
    final episode = MediaLibraryEpisode.cloud(
      stableId: 'episode-1',
      name: '电影正片.mkv',
      sourceId: 'quark',
      sourceName: '夸克网盘',
      isAvailable: true,
      remoteId: 'remote-1',
      remotePath: r'\电影\电影正片.mkv\',
    );

    await state.hideEpisodes(<MediaLibraryEpisode>[episode]);

    final records = await repository.getBySource('quark');
    expect(records, hasLength(1));
    expect(records.single.remoteId, 'remote-1');
    expect(records.single.remotePath, '/电影/电影正片.mkv');
    expect(records.single.fileName, '电影正片.mkv');
    expect(records.single.identityKey, 'id:remote-1');
    expect(
      state.visibleCloudItems(<CloudMediaIndexItem>[
        _cloudItem(
          sourceId: 'quark',
          remoteId: 'remote-1',
          remotePath: '/电影/电影正片.mkv',
        ),
      ]),
      isEmpty,
    );
  });
}

CloudMediaIndexItem _cloudItem({
  required String sourceId,
  required String remoteId,
  required String remotePath,
}) {
  return CloudMediaIndexItem(
    sourceId: sourceId,
    remoteId: remoteId,
    remotePath: remotePath,
    name: '测试视频.mkv',
    size: 1024,
    modifiedAt: DateTime.utc(2026, 8, 5),
    seriesName: '测试视频',
  );
}
