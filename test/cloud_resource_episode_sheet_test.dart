import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv/presentation/tv_episode_tile_surface.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_episode_sheet.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';

CloudResourceMediaGroup _episodeGroup({
  TmdbSeasonMetadata? seasonMetadata,
  CloudResourceTmdbRecord? record,
}) {
  const videos = <CloudFileEntry>[
    CloudFileEntry(
      id: 'episode-1',
      remotePath: '/影视/示例/S01E01.2160p.DV.Atmos.mkv',
      name: '示例 S01E01.2160p.DV.Atmos.mkv',
      size: 1024,
      modifiedAt: null,
      isDirectory: false,
    ),
    CloudFileEntry(
      id: 'episode-2',
      remotePath: '/影视/示例/S01E02.mkv',
      name: '示例 S01E02.mkv',
      size: 1024,
      modifiedAt: null,
      isDirectory: false,
    ),
  ];
  return CloudResourceMediaGroup(
    stableKey: 'source|example',
    seriesName: '示例',
    displayName: '示例 第 1 季',
    isSeries: true,
    videos: videos,
    seasons: <CloudResourceSeasonGroup>[
      CloudResourceSeasonGroup(
        seasonNumber: 1,
        videos: videos,
        metadata: seasonMetadata,
      ),
    ],
    record: record,
    seasonNumber: 1,
  );
}

void main() {
  testWidgets('网盘选集优先使用季度缓存并回退到作品缓存', (tester) async {
    Future<CloudPosterImage> open(CloudResourceMediaGroup group) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showCloudResourceEpisodeSheet(
                  context: context,
                  sourceId: 'source',
                  group: group,
                ),
                child: const Text('打开选集'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开选集'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudPosterImage), findsOneWidget);
      expect(find.text('4K'), findsOneWidget);
      expect(find.text('杜比视界'), findsOneWidget);
      expect(find.text('杜比全景声'), findsOneWidget);
      final title = tester.getRect(
        find.text('示例 S01E01.2160p.DV.Atmos.mkv'),
      );
      final badges = tester.getRect(find.text('4K'));
      expect(badges.top, greaterThan(title.bottom));
      return tester.widget<CloudPosterImage>(find.byType(CloudPosterImage));
    }

    final seasonPoster = await open(
      _episodeGroup(
        seasonMetadata: const TmdbSeasonMetadata(
          id: 1,
          seasonNumber: 1,
          name: '第 1 季',
          episodeCount: 2,
          posterUrl: '/season.jpg',
          posterCachePath: r'C:\cache\season.jpg',
        ),
      ),
    );
    expect(seasonPoster.cachePath, r'C:\cache\season.jpg');
    expect(seasonPoster.url, contains('/w500/season.jpg'));

    await tester.tap(find.byTooltip('关闭选集'));
    await tester.pumpAndSettle();
    final seriesPoster = await open(
      _episodeGroup(
        record: CloudResourceTmdbRecord(
          sourceId: 'source',
          remoteId: 'series',
          remotePath: '/影视/示例',
          displayName: '示例',
          resourceKind: CloudResourceKind.directory,
          status: CloudResourceTmdbStatus.matched,
          checkedAt: DateTime.utc(2026, 8, 23),
          posterUrl: '/series.jpg',
          posterCachePath: r'C:\cache\series.jpg',
        ),
      ),
    );
    expect(seriesPoster.cachePath, r'C:\cache\series.jpg');
    expect(seriesPoster.url, contains('/w500/series.jpg'));
  });

  testWidgets('Android TV 选集下键移动并确认只返回一次', (tester) async {
    CloudFileEntry? selected;
    final group = _episodeGroup();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await showCloudResourceEpisodeSheet(
                  context: context,
                  sourceId: 'source',
                  group: group,
                  capabilities: AppPlatformCapabilities.android.copyWith(
                    television: true,
                    androidSdkInt: 28,
                  ),
                );
              },
              child: const Text('打开选集'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开选集'));
    await tester.pumpAndSettle();

    expect(find.byType(TvEpisodeTileSurface), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected?.id, 'episode-2');
    expect(find.byType(TvEpisodeTileSurface), findsNothing);
  });
}
