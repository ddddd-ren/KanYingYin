import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_card_info.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  test('本地和网盘系列卡使用统一的季度集数详情和徽标顺序', () {
    final local = _series(
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      title: '神探夏洛克',
      sizes: const [40 * 1024 * 1024 * 1024, 73 * 1024 * 1024 * 1024],
      episodes: const [1, 2],
      hasSubtitle: true,
    );
    final cloud = _series(
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '夸克网盘',
      title: '神探夏洛克 S01',
      sizes: const [40 * 1024 * 1024 * 1024, 73 * 1024 * 1024 * 1024],
      episodes: const [1, 2],
      hasSubtitle: true,
    );

    final localInfo = UnifiedMediaCardInfoBuilder.forSeries(
      local,
      categoryLabel: '电视剧',
    );
    final cloudInfo = UnifiedMediaCardInfoBuilder.forSeries(
      cloud,
      categoryLabel: '电视剧',
    );

    expect(localInfo.subtitle, '2 集 · 第 1-2 集');
    expect(cloudInfo.subtitle, localInfo.subtitle);
    expect(localInfo.details, contains('113.0 GB'));
    expect(cloudInfo.details, localInfo.details.replaceFirst('本地', ''));
    expect(
      localInfo.badges.map((badge) => badge.label).toList(),
      ['本地', '电视剧', '有字幕', '已刮削'],
    );
    expect(
      cloudInfo.badges.map((badge) => badge.label).toList(),
      ['夸克网盘', '电视剧', '有字幕', '已刮削'],
    );
    expect(
      localInfo.technicalBadges.map((badge) => badge.label),
      ['4K', '杜比视界', 'HDR', '杜比全景声'],
    );
    expect(
      cloudInfo.technicalBadges.map((badge) => badge.label),
      ['4K', '杜比视界', 'HDR', '杜比全景声'],
    );
  });
}

MediaLibrarySeries _series({
  required MediaSourceKind sourceKind,
  required String sourceId,
  required String sourceName,
  required String title,
  required List<int> sizes,
  required List<int> episodes,
  required bool hasSubtitle,
}) {
  final media = <MediaLibraryEpisode>[];
  for (var index = 0; index < episodes.length; index++) {
    final episode = episodes[index];
    final fileName =
        episode == 1 ? 'S01E01.1080p.HDR.mkv' : 'S01E02.2160p.DV.Atmos.mkv';
    if (sourceKind == MediaSourceKind.local) {
      final item = LocalMediaIndexItem(
        path: 'D:/Media/$fileName',
        name: fileName,
        parentPath: 'D:/Media',
        sourcePath: 'D:/Media',
        size: sizes[index],
        modified: DateTime.utc(2026, 5, 28),
        seriesName: title,
        seasonNumber: 1,
        episodeNumber: episode,
        subtitlePath: hasSubtitle ? 'D:/Media/S01E0$episode.srt' : null,
        indexedAt: DateTime.utc(2026, 5, 28),
        tmdb: TmdbMetadata(
          id: 1,
          mediaType: TmdbMediaType.tv,
          title: title,
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 5, 28),
          matchConfidence: 1,
        ),
      );
      media.add(
        MediaLibraryEpisode.local(
          stableId: item.id,
          name: item.name,
          localItem: item,
        ),
      );
    } else {
      media.add(
        MediaLibraryEpisode.cloud(
          stableId: 'remote-$episode',
          name: fileName,
          sourceId: sourceId,
          sourceName: sourceName,
          isAvailable: true,
          remoteId: 'remote-$episode',
          remotePath: '/$fileName',
          size: sizes[index],
          modifiedAt: DateTime.utc(2026, 5, 28),
          seasonNumber: 1,
          episodeNumber: episode,
          subtitleRemotePaths:
              hasSubtitle ? ['/S01E0$episode.srt'] : const <String>[],
        ),
      );
    }
  }
  return MediaLibrarySeries(
    key: '$sourceId|$title',
    seriesKey: title,
    title: title,
    sourceKind: sourceKind,
    sourceId: sourceId,
    sourceName: sourceName,
    isAvailable: true,
    episodes: media,
    tmdbTitle: title,
    tmdbRating: 8.7,
    mediaType: TmdbMediaType.tv,
  );
}
