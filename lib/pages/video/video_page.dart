import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/pages/player/player_item.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:kanyingyin/utils/pip_utils.dart';
import 'package:kanyingyin/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kanyingyin/bean/widget/embedded_native_control_area.dart';
import 'package:kanyingyin/services/timed_shutdown_service.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/pages/video/cloud_relay_status_presenter.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/features/player/presentation/player_exit_coordinator.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with TickerProviderStateMixin, WindowListener {
  Box<Object?> setting = GStorage.setting;
  final PlayerController playerController = Modular.get<PlayerController>();
  final LocalVideoController localVideoController =
      Modular.get<LocalVideoController>();
  bool showDebugLog = false;
  bool _relayStatusHidden = false;
  bool _relayVisibilityResetScheduled = false;
  Timer? _relayStableTimer;
  final FocusNode keyboardFocus = FocusNode();
  final PlayerExitCoordinator _exitCoordinator = PlayerExitCoordinator();

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
    windowManager.addListener(this);
    windowManager.isFullScreen().then((value) {
      localVideoController.isFullscreen = value;
    });
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await changeEpisode(
          localVideoController.currentEpisode,
          currentRoad: localVideoController.currentRoad,
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
    _exitCoordinator.beginExit();
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    try {
      observerController.controller?.dispose();
    } catch (_) {}
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
    if (!Utils.isDesktop()) {
      try {
        ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
      } catch (_) {}
    }
    Utils.unlockScreenRotation();
    tabController.dispose();
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

  void clearWebviewLog() {
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
    _resetRelayVisibility();
    clearWebviewLog();
    hideDebugConsole();
    localVideoController.loading = true;
    localVideoController.errorMessage = null;
    await playerController.stop();
    if (!mounted) return;
    await localVideoController.changeEpisode(episode,
        currentRoad: currentRoad, offset: offset);
    if (mounted) setState(() {});
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
    if (AppDialog.observer.hasAppDialog) {
      AppDialog.dismiss<void>();
      return;
    }
    if (localVideoController.isPip && Utils.isDesktop()) {
      PipUtils.exitDesktopPIPWindow();
      localVideoController.isPip = false;
      return;
    }
    if (localVideoController.isFullscreen && !Utils.isTablet()) {
      menuJumpToCurrentEpisode();
      await Utils.exitFullScreen();
      localVideoController.showTabBody = false;
      localVideoController.isFullscreen = false;
      return;
    }
    if (localVideoController.isFullscreen) {
      Utils.exitFullScreen();
      localVideoController.isFullscreen = false;
    }
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
    return PopScope(
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
            _syncRelayVisibility(presentation);
            final visible = presentation != null &&
                !_relayStatusHidden &&
                !localVideoController.loading &&
                !playerController.loading;
            return IgnorePointer(
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
                    child: Text(
                      presentation?.text ?? '',
                      style: TextStyle(
                        color: presentation?.warning == true
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : Colors.white,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
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
            child: ListView.builder(
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildEpisodeMenuTile(_EpisodeMenuItem item, bool isCurrent) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleColor = isCurrent ? colorScheme.primary : colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isCurrent
            ? colorScheme.primaryContainer.withValues(alpha: 0.35)
            : colorScheme.onInverseSurface,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: () async {
            if (isCurrent) {
              return;
            }
            AppLogger().i('LocalVideoController: video path is ${item.url}');
            closeTabBodyAnimated();
            changeEpisode(item.index, currentRoad: currentRoad);
          },
          child: Padding(
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
                  child: Text(
                    item.title,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: titleColor,
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
