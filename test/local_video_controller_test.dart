import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_episode.dart';
import 'package:kanyingyin/modules/video/local_playback_session.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/pages/video/video_page_controller_interface.dart';
import 'package:mobx/mobx.dart';

void main() {
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

  test('本地控制器直接从文件组创建播放会话', () {
    final controller = LocalVideoController();

    controller.openFilePlayback(
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

  test('重新打开本地视频始终从开头播放', () {
    final controller = LocalVideoController();

    controller.openFilePlayback(
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
    expect(pathBar, contains("'扫描媒体库'"));
    expect(pathBar, contains("'媒体库'"));
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
    expect(gridSource, contains('Image.network'));
    expect(
      librarySource.indexOf('if (remoteUrl != null && remoteUrl.isNotEmpty)'),
      lessThan(librarySource.indexOf('if (cover != null && cover.isNotEmpty)')),
    );
  });

  test('TMDB 刮削完成后由 Observer 重建网格展示数据', () {
    final page = File('lib/pages/local/local_page.dart').readAsStringSync();
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
    expect(grid, contains('GridView.builder'));
    expect(grid, contains('widget.item.networkCoverUrl'));
  });

  test('字幕设置支持按视频调节出现时间', () {
    final controller =
        File('lib/pages/player/player_controller.dart').readAsStringSync();
    final overlay = File(
      'lib/pages/player/widgets/subtitle_settings_overlay.dart',
    ).readAsStringSync();
    final storage = File('lib/utils/storage.dart').readAsStringSync();

    expect(storage, contains("subtitleDelayByVideo = 'subtitleDelayByVideo'"));
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
      source,
      contains('Modular.get<LocalVideoController>()'),
    );
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
