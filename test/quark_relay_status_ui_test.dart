import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/history/application/playback_history_controller.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';
import 'package:kanyingyin/features/player/application/player_runtime_preferences.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/pages/player/player_item_panel.dart';
import 'package:kanyingyin/pages/player/smallest_player_item_panel.dart';
import 'package:kanyingyin/pages/video/cloud_relay_status_presenter.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/pages/video/video_page.dart';
import 'package:kanyingyin/pages/video/video_page_controller_interface.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:mobx/mobx.dart';

void main() {
  test('预缓冲状态显示实时速度', () {
    final presentation = CloudRelayStatusPresenter.present(
      const CloudRangeRelayStatus(
        providerName: '夸克',
        phase: CloudRangeRelayPhase.prefetching,
        bytesPerSecond: 12.3 * 1024 * 1024,
      ),
    );

    expect(presentation.text, '夸克预缓冲中 · 12.3 MB/s');
    expect(presentation.stable, isFalse);
  });

  test('速度低于媒体平均消耗时显示速度不足和缓存时长', () {
    final presentation = CloudRelayStatusPresenter.present(
      const CloudRangeRelayStatus(
        providerName: '夸克',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: 5 * 1024 * 1024,
        cachedBytes: 20 * 1024 * 1024,
      ),
      totalBytes: 600 * 1024 * 1024,
      mediaDuration: const Duration(seconds: 60),
    );

    expect(presentation.text, contains('当前网盘读取速度不足'));
    expect(presentation.text, contains('缓存 2 秒'));
    expect(presentation.warning, isTrue);
    expect(presentation.stable, isFalse);
    expect(presentation.dismissible, isTrue);
  });

  test('总时长未知时只显示速度且就绪状态可自动隐藏', () {
    final presentation = CloudRelayStatusPresenter.present(
      const CloudRangeRelayStatus(
        providerName: '夸克',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: 8 * 1024 * 1024,
      ),
    );

    expect(presentation.text, '夸克读取 8.0 MB/s');
    expect(presentation.warning, isFalse);
    expect(presentation.stable, isTrue);
  });

  test('重连和失败状态使用明确文案且不可按低速规则关闭', () {
    final reconnecting = CloudRelayStatusPresenter.present(
      const CloudRangeRelayStatus(
        providerName: '夸克',
        phase: CloudRangeRelayPhase.reconnecting,
      ),
    );
    final failed = CloudRelayStatusPresenter.present(
      const CloudRangeRelayStatus(
        providerName: '夸克',
        phase: CloudRangeRelayPhase.failed,
      ),
    );

    expect(reconnecting.text, '夸克正在重新连接');
    expect(reconnecting.dismissible, isFalse);
    expect(failed.text, '夸克分段读取失败');
    expect(failed.dismissible, isFalse);
  });

  group('真实播放器控件', () {
    late Directory hiveDirectory;
    late Box<Object?> settingBox;
    late TypedSettings settings;
    late PlayerController playerController;
    late _RelayVideoController videoController;

    setUpAll(() async {
      hiveDirectory = await Directory.systemTemp.createTemp(
        'quark-relay-status-ui-',
      );
      Hive.init(hiveDirectory.path);
      settingBox = await Hive.openBox<Object?>('settings');
      GStorage.setting = settingBox;
    });

    setUp(() async {
      await settingBox.clear();
      settings = TypedSettings(settingBox);
      playerController = PlayerController(
        runtimePreferences: PlayerRuntimePreferences(settings),
        shadersController: ShadersController(),
      );
      videoController = _RelayVideoController(playerController);
      Modular.init(_PlayerUiTestModule(
        settings: settings,
        playerController: playerController,
        videoController: videoController,
      ));
    });

    tearDown(() {
      cleanModular();
    });

    tearDownAll(() async {
      await Hive.close();
      await hiveDirectory.delete(recursive: true);
    });

    for (final compact in <bool>[false, true]) {
      testWidgets(
        '${compact ? '紧凑' : '完整'}控制栏在窄宽度中将网速放在进度条下方',
        (tester) async {
          installAppPlatformCapabilities(AppPlatformCapabilities.android);
          addTearDown(
            () => installAppPlatformCapabilities(
              AppPlatformCapabilities.windows,
            ),
          );
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize =
              compact ? const Size(480, 320) : const Size(760, 480);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final animationController = AnimationController(vsync: tester);
          final keyboardFocus = FocusNode();
          addTearDown(animationController.dispose);
          addTearDown(keyboardFocus.dispose);
          playerController.loading = false;
          videoController.updateStatus(const CloudRangeRelayStatus(
            providerName: '夸克',
            phase: CloudRangeRelayPhase.ready,
            bytesPerSecond: 4.3 * 1024 * 1024,
          ));

          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: compact
                  ? _compactPanel(animationController, keyboardFocus)
                  : _fullPanel(animationController, keyboardFocus),
            ),
          ));
          await tester.pump();

          expect(tester.takeException(), isNull);
          final speedText = find.text('网速 4.3 MB/s');
          final progress = find.byType(ProgressBar);
          final bottomAnimation = find
              .ancestor(
                of: speedText,
                matching: find.byType(SlideTransition),
              )
              .first;
          expect(speedText, findsOneWidget);
          expect(progress, findsOneWidget);
          expect(bottomAnimation, findsOneWidget);
          expect(
            tester.getTopLeft(speedText).dy,
            greaterThan(tester.getBottomLeft(progress).dy),
          );
          expect(
            find.descendant(of: bottomAnimation, matching: speedText),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('低速提示具备语义且关闭只影响当前视频', (tester) async {
      var semanticsDisposed = false;
      final semantics = tester.ensureSemantics();
      addTearDown(() {
        if (!semanticsDisposed) semantics.dispose();
      });
      installAppPlatformCapabilities(AppPlatformCapabilities.android);
      addTearDown(
        () => installAppPlatformCapabilities(AppPlatformCapabilities.windows),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      playerController.loading = false;
      videoController.loading = false;
      videoController.updateStatus(const CloudRangeRelayStatus(
        providerName: '夸克',
        phase: CloudRangeRelayPhase.degraded,
      ));

      await tester.pumpWidget(const MaterialApp(home: VideoPage()));
      await tester.pump();

      Finder overlayFor(String text) => find.ancestor(
            of: find.text(text),
            matching: find.byType(AnimatedOpacity),
          );
      final overlay = overlayFor('当前网盘读取速度不足');
      final dismiss = find.byTooltip('隐藏本视频低速提示');
      expect(overlay, findsOneWidget);
      expect(dismiss, findsOneWidget);
      expect(
        tester
            .getSemantics(dismiss)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      semanticsDisposed = true;
      semantics.dispose();

      await tester.tap(dismiss);
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(overlay).opacity, 0);

      videoController.updateStatus(const CloudRangeRelayStatus(
        providerName: '夸克',
        phase: CloudRangeRelayPhase.reconnecting,
      ));
      await tester.pump();
      expect(
        tester.widget<AnimatedOpacity>(overlayFor('夸克正在重新连接')).opacity,
        1,
      );
      expect(find.text('夸克正在重新连接'), findsOneWidget);
      expect(find.byTooltip('隐藏本视频低速提示'), findsNothing);

      videoController.updateStatus(const CloudRangeRelayStatus(
        providerName: '夸克',
        phase: CloudRangeRelayPhase.failed,
      ));
      await tester.pump();
      expect(
        tester.widget<AnimatedOpacity>(overlayFor('夸克分段读取失败')).opacity,
        1,
      );
      expect(find.text('夸克分段读取失败'), findsOneWidget);
      expect(find.byTooltip('隐藏本视频低速提示'), findsNothing);

      videoController.updateIdentity('cloud:episode-2');
      videoController.updateStatus(const CloudRangeRelayStatus(
        providerName: '夸克',
        phase: CloudRangeRelayPhase.degraded,
      ));
      await tester.pump();
      expect(
        tester.widget<AnimatedOpacity>(overlayFor('当前网盘读取速度不足')).opacity,
        1,
      );
      expect(find.byTooltip('隐藏本视频低速提示'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 21));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  });
}

class _PlayerUiTestModule extends Module {
  _PlayerUiTestModule({
    required this.settings,
    required this.playerController,
    required this.videoController,
  });

  final TypedSettings settings;
  final PlayerController playerController;
  final _RelayVideoController videoController;

  @override
  void binds(Injector i) {
    i.addInstance<TypedSettings>(settings);
    i.addInstance<PlayerController>(playerController);
    i.addInstance<LocalVideoController>(videoController);
    i.addInstance<IVideoPageController>(videoController);
    i.addInstance<PlaybackHistoryController>(PlaybackHistoryController());
  }
}

class _RelayVideoController extends LocalVideoController {
  _RelayVideoController(this.playerController);

  final PlayerController playerController;
  final Observable<CloudRangeRelayStatus?> _status = Observable(null);
  final Observable<String> _identity = Observable('cloud:episode-1');

  @override
  CloudRangeRelayStatus? get relayStatus => _status.value;

  @override
  String? get currentPlaybackHistoryKey => _identity.value;

  @override
  String get title => '测试视频';

  @override
  bool get hasSession => false;

  void updateStatus(CloudRangeRelayStatus status) {
    runInAction(() => _status.value = status);
  }

  void updateIdentity(String identity) {
    runInAction(() => _identity.value = identity);
  }

  @override
  void activatePlayerLifecycle() {}

  @override
  void invalidatePlaybackOperations() {}

  @override
  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
  }) async {
    currentEpisode = episode;
    this.currentRoad = currentRoad;
    loading = false;
    playerController.loading = false;
  }
}

Widget _fullPanel(
  AnimationController animationController,
  FocusNode keyboardFocus,
) =>
    PlayerItemPanel(
      onBackPressed: (_) {},
      setPlaybackSpeed: (_) async {},
      changeEpisode: (_, {currentRoad = 0, offset = 0}) async {},
      handleFullscreen: () {},
      handleScreenShot: () {},
      handlePreNextEpisode: (_) {},
      handleProgressBarDragStart: (_) {},
      handleProgressBarDragEnd: () {},
      handleSuperResolutionChange: (_) async {},
      animationController: animationController,
      openMenu: () {},
      keyboardFocus: keyboardFocus,
      startHideTimer: () {},
      cancelHideTimer: () {},
      skipOP: () {},
      showVideoInfo: () {},
      showSubtitleSettings: () {},
      onConfirmTrackLanguage: (EmbeddedTrackInfo _) {},
      pauseForTimedShutdown: () {},
    );

Widget _compactPanel(
  AnimationController animationController,
  FocusNode keyboardFocus,
) =>
    SmallestPlayerItemPanel(
      onBackPressed: (_) {},
      setPlaybackSpeed: (_) async {},
      handleFullscreen: () {},
      handleProgressBarDragStart: (_) {},
      handleProgressBarDragEnd: () {},
      handleSuperResolutionChange: (Anime4kPreference _) async {},
      animationController: animationController,
      keyboardFocus: keyboardFocus,
      handleHove: () {},
      startHideTimer: () {},
      cancelHideTimer: () {},
      skipOP: () {},
      showVideoInfo: () {},
      showSubtitleSettings: () {},
      onConfirmTrackLanguage: (EmbeddedTrackInfo _) {},
      pauseForTimedShutdown: () {},
    );
