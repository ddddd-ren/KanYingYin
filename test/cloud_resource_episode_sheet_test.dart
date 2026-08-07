import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv/presentation/tv_episode_tile_surface.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_episode_sheet.dart';
import 'package:kanyingyin/platform/app_platform.dart';

CloudResourceMediaGroup _episodeGroup() {
  const videos = <CloudFileEntry>[
    CloudFileEntry(
      id: 'episode-1',
      remotePath: '/影视/示例/S01E01.mkv',
      name: '示例 S01E01.mkv',
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
      CloudResourceSeasonGroup(seasonNumber: 1, videos: videos),
    ],
    record: null,
    seasonNumber: 1,
  );
}

void main() {
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
