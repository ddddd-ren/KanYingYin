import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_hidden_video.dart';
import 'package:kanyingyin/repositories/cloud_hidden_video_repository.dart';

void main() {
  group('CloudHiddenVideoRepository', () {
    test('隐藏记录按来源持久化并可跨仓库实例读取', () async {
      final storage = MemoryCloudHiddenVideoStorage();
      final first = CloudHiddenVideoRepository(storage: storage);
      const hidden = CloudHiddenVideo(
        sourceId: 'source-a',
        remoteId: 'video-b',
        remotePath: '/电影/B.mkv',
        fileName: 'B.mkv',
      );

      await first.replaceSource('source-a', const <CloudHiddenVideo>[hidden]);

      final second = CloudHiddenVideoRepository(storage: storage);
      expect(await second.getBySource('source-a'), const <CloudHiddenVideo>[
        hidden,
      ]);
      expect(await second.getBySource('source-b'), isEmpty);
    });

    test('损坏记录被忽略且清理来源不影响其他来源', () async {
      final storage = MemoryCloudHiddenVideoStorage(<Object?>[
        <String, Object?>{'sourceId': 'source-a'},
        <String, Object?>{
          'sourceId': 'source-b',
          'remoteId': 'video-b',
          'remotePath': '/电影/B.mkv',
          'fileName': 'B.mkv',
        },
      ]);
      final repository = CloudHiddenVideoRepository(storage: storage);

      expect(await repository.getBySource('source-a'), isEmpty);
      await repository.clearSource('source-a');

      expect(
        await repository.getBySource('source-b'),
        const <CloudHiddenVideo>[
          CloudHiddenVideo(
            sourceId: 'source-b',
            remoteId: 'video-b',
            remotePath: '/电影/B.mkv',
            fileName: 'B.mkv',
          ),
        ],
      );
    });

    test('远程 ID 缺失时使用规范化路径匹配', () {
      const hidden = CloudHiddenVideo(
        sourceId: 'openlist-a',
        remoteId: '',
        remotePath: r'影视\电影\B.mkv',
        fileName: 'B.mkv',
      );

      expect(
        hidden.matches(
          sourceId: 'openlist-a',
          remoteId: '',
          remotePath: '/影视/电影/B.mkv',
        ),
        isTrue,
      );
      expect(
        hidden.matches(
          sourceId: 'openlist-b',
          remoteId: '',
          remotePath: '/影视/电影/B.mkv',
        ),
        isFalse,
      );
    });
  });
}
