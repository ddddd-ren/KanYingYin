import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_series_identity_resolver.dart';

void main() {
  group('CloudSeriesIdentityResolver', () {
    final resolver = CloudSeriesIdentityResolver();

    test('不同发布规格的同目录分集生成同一个系列键', () {
      final first = resolver.resolve(
        sourceId: 'quark',
        remotePath:
            '/剧集/The.Resurrected.S01E01.2160p.NF.WEB-DL.H.265.DDP5.1.Atmos.mkv',
        size: 4 * 1024 * 1024 * 1024,
        minSizeBytes: 1024 * 1024,
      );
      final second = resolver.resolve(
        sourceId: 'quark',
        remotePath: '/剧集/The.Resurrected.S01E02.1080p.WEB-DL.x265.mkv',
        size: 2 * 1024 * 1024 * 1024,
        minSizeBytes: 1024 * 1024,
      );

      expect(first, isNotNull);
      expect(first?.stableKey, second?.stableKey);
      expect(first?.seriesName, 'The Resurrected');
      expect(first?.normalizedSeriesName, 'the resurrected');
      expect(first?.parentPath, '/剧集');
      expect(first?.seasonNumber, 1);
      expect(first?.episodeNumber, 1);
      expect(second?.episodeNumber, 2);
    });

    test('不同目录来源和剧名不会生成相同系列键', () {
      CloudSeriesEpisodeIdentity resolve(
        String sourceId,
        String path,
      ) =>
          resolver.resolve(
            sourceId: sourceId,
            remotePath: path,
            size: 1024 * 1024 * 1024,
            minSizeBytes: 1024 * 1024,
          )!;

      final base = resolve('quark', '/A/Show.S01E01.mkv');
      final anotherDirectory = resolve('quark', '/B/Show.S01E02.mkv');
      final anotherSource = resolve('openlist', '/A/Show.S01E03.mkv');
      final anotherSeries = resolve('quark', '/A/Other.S01E01.mkv');

      expect(base.stableKey, isNot(anotherDirectory.stableKey));
      expect(base.stableKey, isNot(anotherSource.stableKey));
      expect(base.stableKey, isNot(anotherSeries.stableKey));
    });

    test('不超过阈值、非视频和无法识别集号的文件不生成系列身份', () {
      expect(
        resolver.resolve(
          sourceId: 'quark',
          remotePath: '/剧集/Show.S01E01.mkv',
          size: 100,
          minSizeBytes: 100,
        ),
        isNull,
      );
      expect(
        resolver.resolve(
          sourceId: 'quark',
          remotePath: '/剧集/Show.S01E01.ass',
          size: 1000,
          minSizeBytes: 100,
        ),
        isNull,
      );
      expect(
        resolver.resolve(
          sourceId: 'quark',
          remotePath: '/电影/Movie.2026.mkv',
          size: 1000,
          minSizeBytes: 100,
        ),
        isNull,
      );
    });

    test('反斜杠与重复分隔符会规范化为稳定父目录', () {
      final identity = resolver.resolve(
        sourceId: 'quark',
        remotePath: r'\剧集\\Show.S02E03.mkv',
        size: 1000,
        minSizeBytes: 100,
      );

      expect(identity?.parentPath, '/剧集');
      expect(identity?.seasonNumber, 2);
      expect(identity?.episodeNumber, 3);
    });
  });
}
