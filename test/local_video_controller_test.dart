import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_episode.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/modules/video/local_playback_session.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/pages/video/video_page_controller_interface.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';
import 'package:mobx/mobx.dart';

void main() {
  test('播放中的来源改名只更新展示，保留身份进度与播放顺序', () async {
    final initialized = <PlaybackInitParams>[];
    var resolvedCount = 0;
    final controller = LocalVideoController(
      initializePlayer: (params) async => initialized.add(params),
      resolveCloudPlayback: (target) async {
        resolvedCount++;
        return CloudResolvedPlayback(
            target: target,
            videoUrl: 'https://example.invalid/${target.remoteId}',
            httpHeaders: const {});
      },
    );
    final targets = [
      for (final episode in [1, 2])
        CloudPlaybackTarget(
          sourceId: 'source-a',
          remoteId: 'remote-$episode',
          remotePath: '/Original/E$episode.mkv',
          stableId: 'old-view-$episode',
          title: '旧剧名 第 $episode 集',
          subtitleRemotePath: '/Original/E$episode.ass',
        ),
    ];
    MediaLibrarySeries sourceSeries(String title) => MediaLibrarySeries(
          key: 'work-1',
          seriesKey: 'work-1',
          title: title,
          sourceKind: MediaSourceKind.cloud,
          sourceId: 'source-a',
          sourceName: '来源',
          isAvailable: true,
          legacySeriesTitles: const [],
          episodes: [
            for (final episode in [2, 1])
              MediaLibraryEpisode.cloud(
                stableId: 'remote-$episode',
                name: '$title 第 $episode 集',
                sourceId: 'source-a',
                sourceName: '来源',
                isAvailable: true,
                remoteId: 'remote-$episode',
                remotePath: '/Original/E$episode.mkv',
              ),
          ],
        );
    await controller.openCloudPlayback(
      seriesTitle: '旧剧名',
      targets: targets,
      selectedStableId: targets.first.stableId,
    );
    final mediaId = controller.mediaItem.id;
    expect(controller.refreshCloudSourceTitles([sourceSeries('来源剧名')]), isTrue);
    expect(initialized, isEmpty);
    expect(resolvedCount, 1);
    expect(controller.mediaItem.id, mediaId);
    expect(controller.title, '来源剧名');
    expect(controller.mediaItem.effectiveTitle, '来源剧名');
    expect(controller.roadList.single.data,
        ['/Original/E1.mkv', '/Original/E2.mkv']);
    expect(controller.roadList.single.identifier,
        ['来源剧名 第 1 集', '来源剧名 第 2 集']);
    await controller.changeEpisode(1, offset: 29);
    final playing = initialized.single;
    expect(playing.offset, 29);
    expect(playing.mediaTitle, '来源剧名');
    expect(playing.episodeTitle, '来源剧名 第 1 集');
    expect(playing.mediaId, mediaId);
    expect(playing.stableMediaKey, 'source-a|old-view-1');
    expect(playing.trackPreferenceKey, 'cloud|source-a|旧剧名');
    expect(playing.legacyTrackPreferenceKeys, isEmpty);
    expect(
        mergeRefreshedCloudPlayback(
          previous: playing.withDisplayTitles(
            mediaTitle: '旧剧名',
            episodeTitle: '旧剧名 第 1 集',
            legacyTrackPreferenceKeys: const ['unsafe-old-key'],
          ),
          refreshed: playing,
          position: const Duration(seconds: 29),
        ).legacyTrackPreferenceKeys,
        isEmpty);
    expect(controller.refreshCloudSourceTitles([sourceSeries('最终来源剧名')]),
        isTrue);
    expect(initialized, hasLength(1));
    expect(resolvedCount, 1);
    final history = controller.buildPlaybackHistoryEntry(
        position: const Duration(seconds: 29),
        duration: const Duration(minutes: 30))!;
    expect(history.seriesTitle, '最终来源剧名');
    expect(history.episodeTitle, '最终来源剧名 第 1 集');
    expect(history.positionSeconds, 29);
    expect(history.stableKey, playing.stableMediaKey);
    expect(controller.currentCloudPlaybackTarget, targets.first);
    final refreshed = await playing.refreshCloudPlayback!();
    expect(refreshed.mediaTitle, '最终来源剧名');
    expect(refreshed.trackPreferenceKey, playing.trackPreferenceKey);
    expect(refreshed.subtitleStorageKey, playing.subtitleStorageKey);
    expect(controller.refreshCloudSourceTitles([
      sourceSeries('错误标题一'),
      sourceSeries('错误标题二'),
    ]), isFalse);
    expect(controller.title, '最终来源剧名');
    await controller.changeEpisode(2, offset: 0);
    expect(initialized.last.mediaTitle, '最终来源剧名');
    expect(initialized.last.episodeTitle, '最终来源剧名 第 2 集');
    expect(initialized.last.trackPreferenceKey, playing.trackPreferenceKey);
    expect(initialized.last.stableMediaKey, 'source-a|old-view-2');
  });

  test('调用者明确禁用旧标题兼容时不补入当前名或原始名', () async {
    final local = LocalVideoController();
    local.openSession(
        LocalPlaybackSession(
          seriesId: 'same-directory',
          seriesTitle: '同名作品',
          episodes: const [
            LocalEpisode(id: 'e1', path: 'Original.S01E01.mkv', title: '第 1 集')
          ],
          currentEpisodeId: 'e1',
        ),
        legacySeriesTitles: const []);
    expect(local.createPlaybackParams().legacyTrackPreferenceKeys, isEmpty);
    final initialized = <PlaybackInitParams>[];
    final cloud = LocalVideoController(
      initializePlayer: (params) async => initialized.add(params),
      resolveCloudPlayback: (target) async => CloudResolvedPlayback(
          target: target, videoUrl: 'https://example.invalid', httpHeaders: const {}),
    );
    await cloud.openCloudPlayback(
      seriesTitle: '同名作品',
      workKey: 'work-a',
      legacySeriesTitles: const [],
      targets: const [
        CloudPlaybackTarget(
            sourceId: 'source-a', remotePath: '/a.mkv', stableId: 'a', title: 'a')
      ],
      selectedStableId: 'a',
    );
    await cloud.changeEpisode(1);
    expect(initialized.single.legacyTrackPreferenceKeys, isEmpty);
  });

  test('本地控制器生成播放器初始化参数', () {
    final controller = LocalVideoController();
    controller.openSession(
      LocalPlaybackSession(
        seriesId: 'series-id',
        seriesTitle: '测试动画',
        episodes: const [
          LocalEpisode(
            id: 'e1',
            path: r'D:\Video\01.mkv',
            title: '第1集',
            subtitlePath: r'D:\Video\01.ass',
          ),
        ],
        currentEpisodeId: 'e1',
      ),
    );

    final params = controller.createPlaybackParams();
    expect(params.videoUrl, r'D:\Video\01.mkv');
    expect(params.offset, 0);
    expect(params.episodeTitle, '第1集');
    expect(params.subtitlePath, r'D:\Video\01.ass');
    expect(params.isLocalPlayback, isTrue);
  });

  test('本地作品选轨身份不随展示改名或新增剧集变化，同目录其他作品隔离', () {
    PlaybackInitParams params(String title, String rawSeries,
        {bool extraEpisode = false, String directoryId = 'file:d:\\video'}) {
      final controller = LocalVideoController();
      controller.openSession(
        LocalPlaybackSession(
          seriesId: directoryId,
          seriesTitle: title,
          episodes: [
            LocalEpisode(
                id: 'e1',
                path: 'D:\\Video\\$rawSeries.S01E01.mkv',
                title: '第1集'),
            LocalEpisode(
                id: 'e2',
                path: 'D:\\Video\\$rawSeries.S01E02.mkv',
                title: '第2集'),
            if (extraEpisode)
              LocalEpisode(
                  id: 'e3',
                  path: 'D:\\Video\\$rawSeries.S01E03.mkv',
                  title: '第3集'),
          ],
          currentEpisodeId: 'e2',
        ),
        legacySeriesTitles: const ['旧剧名 S01'],
      );
      return controller.createPlaybackParams();
    }

    final original = params('旧剧名 S01', 'Original');
    final renamed = params('来源剧名', 'Original', extraEpisode: true);
    expect(renamed.trackPreferenceKey, original.trackPreferenceKey);
    expect(renamed.trackPreferenceKey,
        isNot(params('来源剧名', 'Other').trackPreferenceKey));
    expect(renamed.trackPreferenceKey,
        isNot(params('来源剧名', 'Original', directoryId: 'other').trackPreferenceKey));
    expect(renamed.legacyTrackPreferenceKeys,
        contains('local-work|file:d:\\video|${Uri.encodeComponent('旧剧名 s01')}'));
  });

  test('云作品选轨身份跨集和改名保持稳定，精确继承旧剧名键', () async {
    Future<List<PlaybackInitParams>> open(String title, String sourceId) async {
      final initialized = <PlaybackInitParams>[];
      final controller = LocalVideoController(
        initializePlayer: (params) async => initialized.add(params),
        resolveCloudPlayback: (target) async => CloudResolvedPlayback(
            target: target, videoUrl: 'https://example.invalid', httpHeaders: const {}),
      );
      final targets = [
        for (final episode in [1, 2])
          CloudPlaybackTarget(
              sourceId: sourceId,
              remotePath: '/Original/E$episode.mkv',
              stableId: 'e$episode',
              title: '第 $episode 集'),
      ];
      await controller.openCloudPlayback(
        seriesTitle: title,
        workKey: 'work-id',
        legacySeriesTitles: const ['旧剧名 S01'],
        targets: targets,
        selectedStableId: 'e1',
      );
      await controller.changeEpisode(1);
      await controller.changeEpisode(2);
      return initialized;
    }

    final old = await open('旧剧名 S01', 'source-a');
    final renamed = await open('来源剧名', 'source-a');
    expect(renamed.first.trackPreferenceKey, 'cloud-work|source-a|work-id');
    expect(renamed.last.trackPreferenceKey, old.first.trackPreferenceKey);
    expect(renamed.first.legacyTrackPreferenceKeys,
        contains('cloud|source-a|旧剧名 S01'));
    expect((await open('来源剧名', 'source-b')).first.trackPreferenceKey,
        isNot(renamed.first.trackPreferenceKey));
    expect(renamed.first.withOffset(9).legacyTrackPreferenceKeys,
        renamed.first.legacyTrackPreferenceKeys);
    expect(
        mergeRefreshedCloudPlayback(
                previous: renamed.first,
                refreshed: renamed.last,
                position: const Duration(seconds: 10))
            .legacyTrackPreferenceKeys,
        renamed.last.legacyTrackPreferenceKeys);
  });

  test('Android 文档作品选轨使用原始文件名，新增前一集不会改变身份', () async {
    final parent = MediaLocation.document(
        uri: 'content://media/document/parent',
        treeUri: 'content://media/tree/root');
    final controller = LocalVideoController();
    final first = LocalPlaybackEntry(
      location: MediaLocation.document(
          uri: 'content://media/document/opaque-1', treeUri: parent.treeUri!),
      parentLocation: parent,
      name: 'Original.S01E01.mkv',
      title: '来源剧名 第 1 集',
    );
    final second = LocalPlaybackEntry(
      location: MediaLocation.document(
          uri: 'content://media/document/opaque-2', treeUri: parent.treeUri!),
      parentLocation: parent,
      name: 'Original.S01E02.mkv',
      title: '来源剧名 第 2 集',
    );
    await controller.openFilePlayback(
        filePath: second.location.value,
        seriesTitle: '旧剧名',
        playbackEntries: [second],
        playlistAlreadyIsolated: true,
        autoLoadSubtitle: false);
    final oldKey = controller.createPlaybackParams().trackPreferenceKey;
    await controller.openFilePlayback(
        filePath: second.location.value,
        seriesTitle: '来源剧名',
        playbackEntries: [first, second],
        playlistAlreadyIsolated: true,
        autoLoadSubtitle: false);
    expect(controller.createPlaybackParams().trackPreferenceKey, oldKey);
    expect(oldKey, contains(Uri.encodeComponent('original')));
  });

  test('本地观看历史保存媒体真实集数', () {
    final controller = LocalVideoController();
    controller.openSession(
      LocalPlaybackSession(
        seriesId: 'series-id',
        seriesTitle: '测试动画',
        episodes: const [
          LocalEpisode(
            id: 'e22',
            path: 'Show.S01E22.mkv',
            title: 'Show S01E22',
            episodeNumber: 22,
          ),
        ],
        currentEpisodeId: 'e22',
      ),
    );

    final entry = controller.buildPlaybackHistoryEntry(
      position: const Duration(minutes: 1),
      duration: const Duration(minutes: 40),
    );

    expect(entry?.episodeIndex, 22);
  });

  test('切换剧集后更新当前会话', () {
    final controller = LocalVideoController();
    controller.openSession(
      LocalPlaybackSession(
        seriesId: 'series-id',
        seriesTitle: '测试动画',
        episodes: const [
          LocalEpisode(id: 'e1', path: '01.mkv', title: '第1集'),
          LocalEpisode(id: 'e2', path: '02.mkv', title: '第2集'),
        ],
        currentEpisodeId: 'e1',
      ),
    );

    controller.selectEpisode('e2');
    expect(controller.session.currentEpisode.path, '02.mkv');
  });

  test('本地控制器直接从文件组创建播放会话', () async {
    final controller = LocalVideoController();

    await controller.openFilePlayback(
      filePath: r'D:\Video\02.mkv',
      seriesTitle: '测试动画',
      directoryFiles: const [
        {'path': r'D:\Video\01.mkv', 'name': '01.mkv', 'title': '第1集'},
        {'path': r'D:\Video\02.mkv', 'name': '02.mkv', 'title': '第2集'},
      ],
      playlistAlreadyIsolated: true,
      autoLoadSubtitle: false,
    );

    expect(controller.session.seriesTitle, '测试动画');
    expect(controller.session.currentIndex, 1);
    expect(controller.session.currentEpisode.title, '第2集');
  });

  test('重新打开本地视频始终从开头播放', () async {
    final controller = LocalVideoController();

    await controller.openFilePlayback(
      filePath: r'D:\Video\01.mkv',
      seriesTitle: '测试动画',
      autoLoadSubtitle: false,
    );

    expect(controller.createPlaybackParams().offset, 0);
  });

  test('本地媒体页不再依赖旧在线视频控制器', () {
    final source = File('lib/pages/local/local_page.dart').readAsStringSync();

    expect(source, isNot(contains('VideoPageController.new')));
    expect(source, isNot(contains('Modular.get<VideoPageController>()')));
    expect(source, contains('LocalVideoController'));
  });

  test('本地页面恢复分组和媒体库入口', () {
    final source = File('lib/pages/local/local_page.dart').readAsStringSync();
    final pathBar = File(
      'lib/features/library/presentation/library_path_bar.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('FeatureFlags.seriesGroupingEnabled')));
    expect(source, contains('_seriesGrouper.group(items)'));
    expect(source, contains('LibraryPathBar('));
    expect(pathBar, contains("'扫描所有媒体源'"));
    expect(pathBar, contains("'媒体库'"));
    expect(pathBar, contains("'查看全部已索引作品'"));
  });

  test('LocalPage 为路径栏提供本地直接子目录', () {
    final source = File('lib/pages/local/local_page.dart').readAsStringSync();

    expect(source, contains('onLoadChildDirectories: _loadChildDirectories'));
    expect(source, contains('onChildDirectorySelected:'));
    expect(source, contains('loadLocalDirectories(path)'));
    expect(source, contains('_enterDirectory(item.path)'));
  });

  test('本地页面优先使用 TMDB 海报并保留本地封面回退', () {
    final pageSource =
        File('lib/pages/local/local_page.dart').readAsStringSync();
    final gridSource = File(
      'lib/features/library/presentation/library_media_grid.dart',
    ).readAsStringSync();
    final librarySource =
        File('lib/pages/local/library_sheet.dart').readAsStringSync();
    final controllerSource =
        File('lib/pages/local/local_controller.dart').readAsStringSync();

    expect(controllerSource, contains('tmdbPosterUrlForPaths'));
    expect(pageSource, contains('tmdbPosterUrlForPaths'));
    expect(pageSource, contains('networkCoverUrl:'));
    expect(gridSource, contains('TmdbNetworkImage'));
    expect(gridSource, isNot(contains('Image.network')));
    expect(
      librarySource.indexOf('if (remoteUrl != null && remoteUrl.isNotEmpty)'),
      lessThan(librarySource.indexOf('if (cover != null && cover.isNotEmpty)')),
    );
  });

  test('TMDB 刮削完成后由 Observer 重建网格展示数据', () {
    final page = File('lib/pages/local/local_page.dart').readAsStringSync();
    final viewDataBuilder = File(
      'lib/features/library/application/library_media_view_data_builder.dart',
    ).readAsStringSync();
    final grid = File(
      'lib/features/library/presentation/library_media_grid.dart',
    ).readAsStringSync();
    final observerBuilder = page.indexOf('Expanded(child: Observer(');
    final mediaItems = page.indexOf(
      'items: [for (final group in groups) _mediaItemData(group)]',
    );

    expect(observerBuilder, greaterThanOrEqualTo(0));
    expect(mediaItems, greaterThan(observerBuilder));
    expect(page, contains('tmdbPosterUrlForPaths'));
    expect(page, contains('networkCoverUrl:'));
    expect(
      viewDataBuilder,
      contains('preferLocalCover: !group.needsOnlinePoster'),
    );
    expect(grid, contains('GridView.builder'));
    expect(grid, contains('final url = item.networkCoverUrl'));
    expect(grid, contains('LibraryMediaCoverFallback.build('));
  });

  test('字幕设置支持按视频调节出现时间', () {
    final controller =
        File('lib/pages/player/player_controller.dart').readAsStringSync();
    final overlay = File(
      'lib/pages/player/widgets/subtitle_settings_overlay.dart',
    ).readAsStringSync();
    final typedSettings = File(
      'lib/features/settings/application/typed_settings.dart',
    ).readAsStringSync();

    expect(
      typedSettings,
      contains("subtitleDelayByVideo = 'subtitleDelayByVideo'"),
    );
    expect(controller, contains('double subtitleDelaySeconds = 0.0'));
    expect(
        controller, contains('Future<void> setSubtitleDelay(double seconds)'));
    expect(controller, contains("'sub-delay', subtitleDelaySeconds"));
    expect(controller, contains('clamp(-30.0, 30.0)'));
    expect(overlay, contains("_SubtitleSectionTitle(title: '字幕时间')"));
    expect(overlay, contains("tooltip: '字幕提前 0.5 秒'"));
    expect(overlay, contains("tooltip: '字幕延后 0.5 秒'"));
    expect(overlay, contains('playerController.resetSubtitleDelay'));
    expect(overlay, contains('divisions: 120'));
  });

  test('外部字幕与内置字幕切换保持互斥', () {
    final controller =
        File('lib/pages/player/player_controller.dart').readAsStringSync();

    expect(
      controller,
      contains('final SubtitleTrackSelectionState _subtitleTrackSelection'),
    );
    expect(
      controller,
      contains('if (!_subtitleTrackSelection.canApplyAutomaticSelection('),
    );
    expect(
      controller,
      contains(
        "await _trySetNativeSubtitleProperty(platform, 'secondary-sid', 'no')",
      ),
    );
    final selection = controller.substring(
        controller.indexOf('Future<bool> selectEmbeddedSubtitleTrack('),
        controller.indexOf('void _resetEmbeddedTrackState()'));
    final clear = selection.indexOf('await _clearSubtitleTrackForSwitch();');
    final apply = selection.indexOf('await player.setSubtitleTrack(track);');
    expect(clear, greaterThanOrEqualTo(0));
    expect(apply, greaterThan(clear));
    expect(selection.substring(clear, apply),
        contains('if (!isCurrent()) return false;'));
    expect(selection, contains('identical(player, mediaPlayer)'));
    expect(selection, contains('revision == _subtitleTrackRequestRevision'));
    expect(selection, contains('canApplyAutomaticSelection(automaticRevision)'));
  });

  test('播放器集成轨道语言确认并保护退出后的旧结果', () {
    final source =
        File('lib/pages/player/player_controller.dart').readAsStringSync();
    final item = File('lib/pages/player/player_item.dart').readAsStringSync();
    final dialog = File(
      'lib/pages/player/widgets/track_language_confirmation_dialog.dart',
    ).readAsStringSync();

    expect(source, contains('pendingTrackLanguages'));
    expect(source, contains('trackLanguageConfirmationRevision'));
    expect(source, contains('_trackLanguageConfirmationState.canApply'));
    expect(item, contains('if (!_canUsePlayer) return;'));
    expect(source, contains('Future<String?> confirmTrackLanguage('));
    expect(source,
        isNot(contains('if (pendingTrackLanguages.isNotEmpty) return;')));
    expect(source, contains('selectTrackByPreferences('));
    expect(source, contains('_trackPreferences.load('));
    expect(source, contains('globalTrackPreference('));
    expect(
        source, isNot(contains('availableEmbeddedSubtitleTracks.firstOrNull')));
    expect(item, isNot(contains('_scheduleTrackLanguageConfirmation')));
    expect(item, contains('barrierDismissible: true'));
    expect(dialog, contains('稍后确认'));
  });

  test('播放器全屏切换等待原生完成并避免重复触发', () {
    final item = File('lib/pages/player/player_item.dart').readAsStringSync();
    final fullPanel =
        File('lib/pages/player/player_item_panel.dart').readAsStringSync();
    final compactPanel = File(
      'lib/pages/player/smallest_player_item_panel.dart',
    ).readAsStringSync();

    expect(item, contains('bool _fullscreenTransitionActive = false;'));
    expect(
        item,
        contains(
            'if (!_acceptingInput || _fullscreenTransitionActive) return;'));
    expect(item, contains('await videoPageController.enterFullScreen();'));
    expect(item, contains('await videoPageController.exitFullScreen();'));
    expect(item, contains('displayVideoController();'));
    expect(fullPanel, isNot(contains('AnimatedPositioned')));
    expect(compactPanel, isNot(contains('AnimatedPositioned')));
  });

  test('TMDB 海报部分下载失败时显示明确提示', () {
    final page = File('lib/pages/local/local_page.dart').readAsStringSync();
    final library =
        File('lib/pages/local/library_sheet.dart').readAsStringSync();

    expect(page, contains('TMDB 信息已更新，部分封面下载失败'));
    expect(library, contains('TMDB 信息已更新，部分封面下载失败'));
    expect(page, contains('posterDownloadFailures > 0'));
    expect(library, contains('posterDownloadFailures > 0'));
  });

  test('本地控制器实现播放器页面状态接口', () {
    final controller = LocalVideoController();

    expect(controller, isA<IVideoPageController>());
  });

  test('切换剧集时更新状态并初始化对应本地文件', () async {
    PlaybackInitParams? receivedParams;
    final controller = LocalVideoController(
      initializePlayer: (params) async {
        receivedParams = params;
      },
    );
    controller.openSession(
      LocalPlaybackSession(
        seriesId: 'series-id',
        seriesTitle: '测试动画',
        episodes: const [
          LocalEpisode(id: 'e1', path: '01.mkv', title: '第1集'),
          LocalEpisode(id: 'e2', path: '02.mkv', title: '第2集'),
        ],
        currentEpisodeId: 'e1',
      ),
    );

    await controller.changeEpisode(2, currentRoad: 0, offset: 18);

    expect(controller.currentEpisode, 2);
    expect(controller.session.currentEpisodeId, 'e2');
    expect(receivedParams?.videoUrl, '02.mkv');
    expect(receivedParams?.offset, 18);
  });

  test('播放器页面状态变化可以通知观察者', () async {
    final controller = LocalVideoController();
    final values = <bool>[];
    final dispose = reaction<bool>(
      (_) => controller.isFullscreen,
      values.add,
    );

    controller.isFullscreen = true;
    await Future<void>.delayed(Duration.zero);

    expect(values, [true]);
    dispose();
  });

  test('视频页面只依赖本地播放控制器', () {
    final source = File('lib/pages/video/video_page.dart').readAsStringSync();

    for (final text in [
      'VideoPageController',
      'CommentsController',
      'DownloadController',
      'EpisodeCommentsSheet',
      'DownloadEpisodeSheet',
      '_initOnlineMode',
      '_initDirectMode',
    ]) {
      expect(source, isNot(contains(text)));
    }
  });

  test('根模块使用本地控制器提供播放器页面状态', () {
    final source = File('lib/pages/index_module.dart').readAsStringSync();
    final playbackBindings =
        File('lib/app/bindings/playback_bindings.dart').readAsStringSync();

    expect(source, isNot(contains('VideoPageController.new')));
    expect(source, isNot(contains('Modular.get<VideoPageController>()')));
    expect(source, isNot(contains('CommentsController')));
    for (final text in [
      'PluginsController',
      'CollectController',
      'DownloadController',
      'MyController',
      'ICollectRepository',
      'ICollectCrudRepository',
      'IDownloadRepository',
      'IDownloadManager',
    ]) {
      expect(source, isNot(contains(text)));
    }
    expect(
      playbackBindings,
      contains('Modular.get<LocalVideoController>()'),
    );
    expect(source, contains('registerApplicationBindings('));
  });

  test('播放器面板不再提供在线收藏同步和投屏控件', () {
    for (final path in [
      'lib/pages/player/player_item_panel.dart',
      'lib/pages/player/smallest_player_item_panel.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final text in [
        'CollectController',
        'CollectButton',
        'DownloadController',
        'showSyncPlayRoomCreateDialog',
        'showSyncPlayEndPointSwitchDialog',
        'castVideo',
        '远程投屏',
      ]) {
        expect(source, isNot(contains(text)), reason: path);
      }
    }
  });

  test('播放器主体不再初始化在线同步服务', () {
    final source = File('lib/pages/player/player_item.dart').readAsStringSync();

    for (final text in [
      'WebDav',
      'CollectController',
      'MyController',
      'showSyncPlayRoomCreateDialog',
      'showSyncPlayEndPointSwitchDialog',
      'setSyncPlayCurrentPosition',
      'createSyncPlayRoom',
    ]) {
      expect(source, isNot(contains(text)));
    }
  });

  test('播放器始终记录 mpv 日志且不做无效 TrueHD 视频重建', () {
    final source =
        File('lib/pages/player/player_controller.dart').readAsStringSync();

    expect(
      source,
      contains("writePlayerLog('MPV: \$safeLog')"),
    );
    expect(source, contains('logLevel: MPVLogLevel.v'));
    expect(source, isNot(contains('logLevel: MPVLogLevel.trace')));
    expect(source, contains('_switchToCompatibleAudioTrackForTrueHd'));
    expect(source, isNot(contains('_retryWithSoftwareDecodingForTrueHd')));
    expect(
      source,
      isNot(contains('_forceSoftwareDecodingForCurrentMedia')),
    );
  });
}
