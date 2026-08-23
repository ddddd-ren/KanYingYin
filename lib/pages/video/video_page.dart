import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/platform/android/android_system_ui_surface.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/pages/player/player_item.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:kanyingyin/features/history/application/playback_history_controller.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:kanyingyin/utils/pip_utils.dart';
import 'package:kanyingyin/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kanyingyin/bean/widget/embedded_native_control_area.dart';
import 'package:kanyingyin/services/timed_shutdown_service.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/pages/video/cloud_relay_status_presenter.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/features/player/presentation/player_exit_coordinator.dart';
import 'package:kanyingyin/features/player/application/player_back_policy.dart';
import 'package:kanyingyin/features/tv/presentation/tv_episode_tile_surface.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with TickerProviderStateMixin, WindowListener {
  final TypedSettings setting = Modular.get<TypedSettings>();
  final PlayerController playerController = Modular.get<PlayerController>();
  final LocalVideoController localVideoController =
      Modular.get<LocalVideoController>();
  final PlaybackHistoryController historyController =
      Modular.get<PlaybackHistoryController>();
  bool showDebugLog = false;
  bool _relayStatusHidden = false;
  bool _relayVisibilityResetScheduled = false;
  Timer? _relayStableTimer;
  final CloudRelayStatusDismissal _relayStatusDismissal =
      CloudRelayStatusDismissal();
  final FocusNode keyboardFocus = FocusNode();
  final GlobalKey<PlayerItemState> _playerItemKey =
      GlobalKey<PlayerItemState>();
  final PlayerExitCoordinator _exitCoordinator = PlayerExitCoordinator();
  ReactionDisposer? _historyDisposer;

  ScrollController scrollController = ScrollController();
  late ListObserverController observerController;
  late AnimationController animation;
  late Animation<Offset> _rightOffsetAnimation;
  late Animation<double> _maskOpacityAnimation;
  late TabController tabController;

  // 当前播放列表
  late int currentRoad;

  // disable animation.
  late final bool disableAnimations;

  @override
  void initState() {
    super.initState();
    if (Utils.isDesktop()) {
      windowManager.addListener(this);
      windowManager.isFullScreen().then((value) {
        localVideoController.isFullscreen = value;
      });
    }
    tabController = TabController(length: 1, vsync: this);
    observerController = ListObserverController(controller: scrollController);
    animation = AnimationController(
      duration: StyleString.fastAnimationDuration,
      vsync: this,
    );
    _rightOffsetAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: const Offset(0.0, 0.0),
    ).animate(CurvedAnimation(
      parent: animation,
      curve: StyleString.defaultCurve,
    ));
    _maskOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: StyleString.decelerateCurve,
    ));

    disableAnimations = setting.getTyped<bool>(
      SettingBoxKey.playerDisableAnimations,
      defaultValue: false,
    );
    localVideoController.activatePlayerLifecycle();
    localVideoController.showTabBody = true;
    currentRoad = localVideoController.currentRoad;
    _historyDisposer = reaction<List<Object?>>(
      (_) => <Object?>[
        playerController.currentPosition,
        playerController.duration,
        playerController.completed,
        localVideoController.currentEpisode,
        localVideoController.loading,
        localVideoController.errorMessage,
      ],
      (_) => unawaited(_recordPlaybackHistory()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await historyController.ensureLoaded();
        final key = localVideoController.currentPlaybackHistoryKey;
        final offset =
            key == null ? 0 : historyController.resumePosition(key).inSeconds;
        await changeEpisode(
          localVideoController.currentEpisode,
          currentRoad: localVideoController.currentRoad,
          offset: offset,
        );
      } on Object catch (error, stackTrace) {
        AppLogger().e(
          'VideoPage: failed to initialize playback',
          error: error,
          stackTrace: stackTrace,
        );
        if (mounted) {
          localVideoController.errorMessage = '播放器加载失败：$error';
        }
      }
    });
  }

  @override
  void dispose() {
    _relayStableTimer?.cancel();
    _historyDisposer?.call();
    unawaited(_recordPlaybackHistory(forcePersist: true));
    _exitCoordinator.beginExit();
    if (Utils.isDesktop()) {
      try {
        windowManager.removeListener(this);
      } catch (_) {}
    } else {
      unawaited(Utils.exitFullScreen());
    }
    try {
      animation.dispose();
    } catch (_) {}
    try {
      localVideoController.invalidatePlaybackOperations();
      unawaited(playerController.dispose());
    } catch (e) {
      AppLogger().e('LocalVideoController: failed to dispose playerController',
          error: e);
    }
    tabController.dispose();
    keyboardFocus.dispose();
    scrollController.dispose();
    // Cancel timed shutdown when leaving anime page
    TimedShutdownService().cancel();
    _exitCoordinator.dispose();
    super.dispose();
  }

  // Handle fullscreen change invoked by system controls
  @override
  void onWindowEnterFullScreen() {
    localVideoController.isFullscreen = true;
  }

  @override
  void onWindowLeaveFullScreen() {
    localVideoController.isFullscreen = false;
  }

  void showDebugConsole() {
    setState(() {
      showDebugLog = true;
    });
  }

  void hideDebugConsole() {
    setState(() {
      showDebugLog = false;
    });
  }

  void switchDebugConsole() {
    setState(() {
      showDebugLog = !showDebugLog;
    });
  }

  void clearPlayerLog() {
    setState(() {
      playerController.playerLog.clear();
    });
  }

  List<String> get _debugLogLines {
    final lines = <String>[
      if (playerController.playerLog.isNotEmpty) '== 播放器日志 ==',
      ...playerController.playerLog,
    ];
    return lines.isEmpty ? ['暂无调试日志'] : lines;
  }

  Future<void> changeEpisode(int episode,
      {int currentRoad = 0, int offset = 0}) async {
    final previousPlaybackIdentity = _relayPlaybackIdentity;
    await _recordPlaybackHistory(forcePersist: true);
    _resetRelayVisibility();
    clearPlayerLog();
    hideDebugConsole();
    localVideoController.loading = true;
    localVideoController.errorMessage = null;
    await playerController.stop();
    if (!mounted) return;
    await localVideoController.changeEpisode(episode,
        currentRoad: currentRoad, offset: offset);
    if (_relayPlaybackIdentity != previousPlaybackIdentity) {
      _relayStatusDismissal.clear();
    }
    if (mounted) setState(() {});
  }

  String get _relayPlaybackIdentity =>
      localVideoController.currentPlaybackHistoryKey ??
      'relay-session:${localVideoController.currentEpisode}:${localVideoController.currentRoad}';

  Future<void> _recordPlaybackHistory({bool forcePersist = false}) async {
    if (!localVideoController.hasSession ||
        localVideoController.loading ||
        localVideoController.errorMessage != null) {
      return;
    }
    final duration = playerController.duration;
    final position = playerController.completed
        ? duration
        : playerController.currentPosition;
    if (duration <= Duration.zero ||
        (position <= Duration.zero && !playerController.completed)) {
      return;
    }
    final entry = localVideoController.buildPlaybackHistoryEntry(
      position: position,
      duration: duration,
    );
    if (entry == null) return;
    try {
      await historyController.record(entry, forcePersist: forcePersist);
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        'VideoPage: failed to persist playback history',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  CloudRelayStatusPresentation? _relayPresentation({
    bool forLoading = false,
  }) {
    final status = localVideoController.relayStatus;
    if (status == null) return null;
    final displayedStatus =
        forLoading && status.phase == CloudRangeRelayPhase.ready
            ? CloudRangeRelayStatus(
                providerName: status.providerName,
                phase: CloudRangeRelayPhase.prefetching,
                bytesPerSecond: status.bytesPerSecond,
                receivedBytes: status.receivedBytes,
                cachedBytes: status.cachedBytes,
                bufferedDuration: status.bufferedDuration,
                message: status.message,
              )
            : status;
    return CloudRelayStatusPresenter.present(
      displayedStatus,
      totalBytes: localVideoController.relayTotalBytes,
      mediaDuration: playerController.duration > Duration.zero
          ? playerController.duration
          : null,
    );
  }

  void _syncRelayVisibility(CloudRelayStatusPresentation? presentation) {
    final stable = presentation?.stable == true && !playerController.loading;
    if (!stable) {
      _relayStableTimer?.cancel();
      _relayStableTimer = null;
      if (_relayStatusHidden && !_relayVisibilityResetScheduled) {
        _relayVisibilityResetScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _relayVisibilityResetScheduled = false;
          if (mounted && _relayStatusHidden) {
            setState(() => _relayStatusHidden = false);
          }
        });
      }
      return;
    }
    if (_relayStatusHidden || _relayStableTimer != null) return;
    _relayStableTimer = Timer(const Duration(seconds: 5), () {
      _relayStableTimer = null;
      if (mounted) setState(() => _relayStatusHidden = true);
    });
  }

  void _resetRelayVisibility() {
    _relayStableTimer?.cancel();
    _relayStableTimer = null;
    if (_relayStatusHidden && mounted) {
      setState(() => _relayStatusHidden = false);
    }
  }

  void menuJumpToCurrentEpisode() {
    Future.delayed(const Duration(milliseconds: 20), () async {
      await observerController.jumpTo(
          index: localVideoController.currentEpisode > 1
              ? localVideoController.currentEpisode - 1
              : 0);
    });
  }

  void openTabBodyAnimated() {
    if (localVideoController.showTabBody) {
      if (!disableAnimations) {
        animation.forward();
      }
      menuJumpToCurrentEpisode();
    }
  }

  void closeTabBodyAnimated() {
    if (!disableAnimations) {
      animation.reverse();
      Future.delayed(StyleString.fastAnimationDuration, () {
        localVideoController.showTabBody = false;
      });
    } else {
      localVideoController.showTabBody = false;
    }
    keyboardFocus.requestFocus();
  }

  void onBackPressed(BuildContext context) async {
    final capabilities = detectAppPlatform();
    final action = PlayerBackPolicy.decide(
      overlayVisible: AppDialog.observer.hasAppDialog,
      fullscreen: localVideoController.isFullscreen && Utils.isDesktop(),
      episodePanelVisible:
          capabilities.isAndroidTv && localVideoController.showTabBody,
      controlsVisible: playerController.showVideoController,
      isAndroidTv: capabilities.isAndroidTv,
    );
    if (action == PlayerBackAction.closeOverlay) {
      if (AppDialog.observer.hasAppDialog) {
        AppDialog.dismiss<void>();
      } else if (capabilities.isAndroidTv &&
          playerController.showVideoController) {
        final playerItemMounted = _playerItemKey.currentState != null;
        _playerItemKey.currentState?.hideVideoController();
        if (!playerItemMounted) {
          playerController.showVideoController = false;
          keyboardFocus.requestFocus();
        }
      }
      return;
    }
    if (action == PlayerBackAction.closeEpisodePanel) {
      closeTabBodyAnimated();
      return;
    }
    if (localVideoController.isPip && Utils.isDesktop()) {
      PipUtils.exitPIPWindow();
      localVideoController.isPip = false;
      return;
    }
    if (action == PlayerBackAction.exitFullscreen) {
      if (!Utils.isTablet()) {
        menuJumpToCurrentEpisode();
        localVideoController.showTabBody = false;
      }
      await Utils.exitFullScreen();
      localVideoController.isFullscreen = false;
      return;
    }
    if (!Utils.isDesktop() &&
        !capabilities.isAndroidTv &&
        localVideoController.isFullscreen) {
      await Utils.exitFullScreen();
      localVideoController.isFullscreen = false;
    }
    if (!context.mounted) return;
    if (!_exitCoordinator.beginExit()) return;
    AppLogger().i('VideoPage: route exit requested');
    Navigator.of(context).pop();
  }

  /// Callback for timed shutdown - pauses video when timer expires
  void pauseForTimedShutdown() {
    if (playerController.playing) {
      playerController.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool islandScape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      openTabBodyAnimated();
    });
    return AndroidPlaybackSystemUiSurface(
      capabilities: detectAppPlatform(),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) {
            return;
          }
          onBackPressed(context);
        },
        child: OrientationBuilder(builder: (context, orientation) {
          if (!Utils.isDesktop()) {
            if (orientation == Orientation.landscape &&
                !localVideoController.isFullscreen) {
              localVideoController.enterFullScreen();
            } else if (orientation == Orientation.portrait &&
                localVideoController.isFullscreen) {
              localVideoController.exitFullScreen();
              menuJumpToCurrentEpisode();
              localVideoController.showTabBody = true;
            }
          }
          return Observer(builder: (context) {
            return Scaffold(
              appBar: null,
              backgroundColor: Colors.black,
              body: SafeArea(
                  top: !localVideoController.isFullscreen,
                  // set iOS and Android navigation bar to immersive
                  bottom: false,
                  left: !localVideoController.isFullscreen,
                  right: !localVideoController.isFullscreen,
                  child: Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      Column(
                        children: [
                          Flexible(
                            // make it unflexible when not wideScreen.
                            flex: (islandScape) ? 1 : 0,
                            child: Container(
                              color: Colors.black,
                              height: (islandScape)
                                  ? MediaQuery.sizeOf(context).height
                                  : MediaQuery.sizeOf(context).width * 9 / 16,
                              width: MediaQuery.sizeOf(context).width,
                              child: playerBody,
                            ),
                          ),
                          // when not wideScreen, show tabBody on the bottom
                          if (!islandScape) Expanded(child: tabBody),
                        ],
                      ),

                      // when is wideScreen, show tabBody on the right side with SlideTransition or direct visibility
                      if (islandScape && localVideoController.showTabBody) ...[
                        if (disableAnimations) ...[
                          sideTabMask,
                          sideTabBody,
                        ] else ...[
                          FadeTransition(
                            opacity: _maskOpacityAnimation,
                            child: sideTabMask,
                          ),
                          SlideTransition(
                            position: _rightOffsetAnimation,
                            child: sideTabBody,
                          ),
                        ],
                      ],
                    ],
                  )),
            );
          });
        }),
      ),
    );
  }

  Widget get sideTabBody {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height,
      width: (!Utils.isDesktop() && !Utils.isTablet())
          ? MediaQuery.sizeOf(context).height
          : (MediaQuery.sizeOf(context).width / 3 > 420
              ? 420
              : MediaQuery.sizeOf(context).width / 3),
      child: Container(
        color: Theme.of(context).canvasColor,
        child: ListViewObserver(
          controller: observerController,
          child: (Utils.isDesktop() || Utils.isTablet())
              ? tabBody
              : Column(
                  children: [
                    menuBar,
                    menuBody,
                  ],
                ),
        ),
      ),
    );
  }

  Widget get sideTabMask {
    return GestureDetector(
      onTap: closeTabBodyAnimated,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.black.withValues(alpha: 0.5),
              Colors.transparent,
            ],
          ),
        ),
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  Widget get playerBody {
    return Stack(
      children: [
        Positioned.fill(
          child: Stack(
            children: [
              if (localVideoController.loading ||
                  playerController.loading ||
                  localVideoController.errorMessage != null)
                Container(
                  color: Colors.black,
                  child: Observer(builder: (context) {
                    final relay = _relayPresentation(forLoading: true);
                    return Center(
                      child: localVideoController.errorMessage != null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline,
                                    color: Theme.of(context).colorScheme.error,
                                    size: 48),
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 32),
                                  child: Text(
                                    localVideoController.errorMessage!,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 16),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .tertiaryContainer),
                                const SizedBox(height: 10),
                                Text(
                                  relay?.text ??
                                      (localVideoController.loading
                                          ? '视频资源解析中'
                                          : '视频资源解析成功, 播放器加载中'),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                    );
                  }),
                ),
              Visibility(
                visible: (localVideoController.loading ||
                        playerController.loading) &&
                    showDebugLog,
                child: Container(
                  color: Colors.black,
                  child: Align(
                    alignment: Alignment.center,
                    child: Observer(builder: (context) {
                      final lines = _debugLogLines;
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: lines.length,
                        itemBuilder: (context, index) {
                          return Text(
                            lines[index],
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          );
                        },
                      );
                    }),
                  ),
                ),
              ),
              Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: EmbeddedNativeControlArea(
                      requireOffset: !localVideoController.isFullscreen,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
                            onPressed: () => onBackPressed(context),
                          ),
                          const Expanded(
                              child: dtb.DragToMoveArea(
                                  child: SizedBox(height: 40))),
                          IconButton(
                            icon: const Icon(Icons.refresh_outlined,
                                color: Colors.white),
                            onPressed: () {
                              changeEpisode(localVideoController.currentEpisode,
                                  currentRoad:
                                      localVideoController.currentRoad);
                            },
                          ),
                          Visibility(
                            visible: MediaQuery.sizeOf(context).width >
                                MediaQuery.sizeOf(context).height,
                            child: IconButton(
                              onPressed: () {
                                localVideoController.showTabBody =
                                    !localVideoController.showTabBody;
                                openTabBodyAnimated();
                              },
                              icon: Icon(
                                localVideoController.showTabBody
                                    ? Icons.menu_open
                                    : Icons.menu_open_outlined,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                                showDebugLog
                                    ? Icons.bug_report
                                    : Icons.bug_report_outlined,
                                color: Colors.white),
                            onPressed: () {
                              switchDebugConsole();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: playerController.loading
              ? Container()
              : PlayerItem(
                  key: _playerItemKey,
                  capabilities: detectAppPlatform(),
                  exitCoordinator: _exitCoordinator,
                  openMenu: openTabBodyAnimated,
                  locateEpisode: menuJumpToCurrentEpisode,
                  changeEpisode: changeEpisode,
                  onBackPressed: onBackPressed,
                  keyboardFocus: keyboardFocus,
                  disableAnimations: disableAnimations,
                  pauseForTimedShutdown: pauseForTimedShutdown,
                ),
        ),
        Positioned(
          top: 56,
          left: 32,
          right: 32,
          child: Observer(builder: (context) {
            final presentation = _relayPresentation();
            final playbackIdentity = _relayPlaybackIdentity;
            final dismissed = presentation != null &&
                _relayStatusDismissal.hides(presentation, playbackIdentity);
            _syncRelayVisibility(presentation);
            final visible = presentation != null &&
                !_relayStatusHidden &&
                !dismissed &&
                !localVideoController.loading &&
                !playerController.loading;
            final foregroundColor = presentation?.warning == true
                ? Theme.of(context).colorScheme.onErrorContainer
                : Colors.white;
            final dismissButton = presentation?.dismissible == true
                ? IconButton(
                    tooltip: '隐藏本视频低速提示',
                    color: foregroundColor,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(
                      () => _relayStatusDismissal.dismiss(playbackIdentity),
                    ),
                  )
                : null;
            return IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: StyleString.fastAnimationDuration,
                curve: StyleString.defaultCurve,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: presentation?.warning == true
                          ? Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.92)
                          : Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            presentation?.text ?? '',
                            style: TextStyle(
                              color: foregroundColor,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (dismissButton != null) dismissButton,
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget get menuBar {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(' 合集 '),
          Expanded(
            child: Text(
              localVideoController.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(width: 10),
          MenuAnchor(
            consumeOutsideTap: true,
            builder: (_, MenuController controller, __) {
              return SizedBox(
                height: 34,
                child: TextButton(
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(EdgeInsets.zero),
                  ),
                  onPressed: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  child: Text(
                    '播放列表${currentRoad + 1} ',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              );
            },
            menuChildren: List<MenuItemButton>.generate(
              localVideoController.roadList.length,
              (int i) => MenuItemButton(
                onPressed: () {
                  setState(() {
                    currentRoad = i;
                  });
                },
                child: Container(
                  height: 48,
                  constraints: BoxConstraints(minWidth: 112),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '播放列表${i + 1}',
                      style: TextStyle(
                        color: i == currentRoad
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget get menuBody {
    return Observer(
      builder: (context) {
        final episodes = <_EpisodeMenuItem>[];
        if (currentRoad >= 0 &&
            currentRoad < localVideoController.roadList.length) {
          final road = localVideoController.roadList[currentRoad];
          int count = 1;
          for (var urlItem in road.data) {
            episodes.add(
              _EpisodeMenuItem(
                index: count,
                url: urlItem,
                title: road.identifier[count - 1],
              ),
            );
            count++;
          }
        }
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 0, right: 8, left: 8),
            child: Builder(
              builder: (context) {
                final isTv = detectAppPlatform().isAndroidTv;
                final list = ListView.builder(
                  scrollDirection: Axis.vertical,
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: episodes.length,
                  itemBuilder: (context, index) {
                    final item = episodes[index];
                    final isCurrent =
                        item.index == localVideoController.currentEpisode &&
                            currentRoad == localVideoController.currentRoad;
                    return _buildEpisodeMenuTile(item, isCurrent);
                  },
                );
                return isTv
                    ? FocusTraversalGroup(
                        policy: WidgetOrderTraversalPolicy(),
                        child: list,
                      )
                    : list;
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectEpisode(
    _EpisodeMenuItem item,
    bool isCurrent,
  ) async {
    if (isCurrent) return;
    AppLogger().i('LocalVideoController: video path is ${item.url}');
    closeTabBodyAnimated();
    await changeEpisode(item.index, currentRoad: currentRoad);
  }

  Widget _buildEpisodeMenuTile(_EpisodeMenuItem item, bool isCurrent) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleColor = isCurrent ? colorScheme.primary : colorScheme.onSurface;
    final isTv = detectAppPlatform().isAndroidTv;
    final technicalBadges = const MediaTechnicalBadgeResolver().resolve(
      names: [item.title, item.url],
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: isCurrent
                  ? Image.asset(
                      'assets/images/playing.gif',
                      color: colorScheme.primary,
                      height: 12,
                    )
                  : Text(
                      item.index.toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: titleColor,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (technicalBadges.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  MediaTechnicalBadgeRow(badges: technicalBadges),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    final tile = Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isCurrent
            ? colorScheme.primaryContainer.withValues(alpha: 0.35)
            : colorScheme.onInverseSurface,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.hardEdge,
        child: isTv
            ? content
            : InkWell(
                onTap: () => unawaited(_selectEpisode(item, isCurrent)),
                child: content,
              ),
      ),
    );
    if (!isTv) return tile;
    return TvEpisodeTileSurface(
      autofocus: isCurrent,
      current: isCurrent,
      onPressed: () => unawaited(_selectEpisode(item, isCurrent)),
      child: tile,
    );
  }

  Widget get tabBody {
    return Container(
      color: Theme.of(context).canvasColor,
      child: DefaultTabController(
        length: 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TabBar(
                  controller: tabController,
                  dividerHeight: 0,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding:
                      const EdgeInsetsDirectional.only(start: 30, end: 30),
                  onTap: (index) {
                    if (index == 0) {
                      menuJumpToCurrentEpisode();
                    }
                  },
                  tabs: const [Tab(text: '选集')],
                ),
                const SizedBox(width: 8),
              ],
            ),
            Divider(height: Utils.isDesktop() ? 0.5 : 0.2),
            Expanded(
              child: TabBarView(
                controller: tabController,
                children: [
                  ListViewObserver(
                    controller: observerController,
                    child: Column(
                      children: [
                        menuBar,
                        menuBody,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeMenuItem {
  final int index;
  final String url;
  final String title;

  const _EpisodeMenuItem({
    required this.index,
    required this.url,
    required this.title,
  });
}
