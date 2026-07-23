import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:kanyingyin/pages/player/player_item_panel.dart';
import 'package:kanyingyin/pages/player/smallest_player_item_panel.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:kanyingyin/utils/pip_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/video/video_page_controller_interface.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/pages/player/player_item_surface.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:kanyingyin/services/audio_controller.dart';
import 'package:kanyingyin/services/local_subtitle_importer.dart';
import 'package:kanyingyin/pages/player/widgets/player_gestures.dart';
import 'package:kanyingyin/pages/player/widgets/subtitle_settings_overlay.dart';
import 'package:kanyingyin/pages/player/widgets/track_language_confirmation_dialog.dart';
import 'package:kanyingyin/features/player/presentation/player_overlay_coordinator.dart';
import 'package:kanyingyin/features/player/presentation/player_shortcut_handler.dart';
import 'package:kanyingyin/features/player/presentation/player_exit_coordinator.dart';
import 'package:path/path.dart' as p;

class PlayerItem extends StatefulWidget {
  const PlayerItem({
    super.key,
    required this.openMenu,
    required this.locateEpisode,
    required this.changeEpisode,
    required this.onBackPressed,
    required this.keyboardFocus,
    required this.pauseForTimedShutdown,
    required this.exitCoordinator,
    this.disableAnimations = false,
  });

  final VoidCallback openMenu;
  final VoidCallback locateEpisode;
  final Future<void> Function(int episode, {int currentRoad, int offset})
      changeEpisode;
  final void Function(BuildContext) onBackPressed;
  final FocusNode keyboardFocus;
  final bool disableAnimations;
  final VoidCallback pauseForTimedShutdown;
  final PlayerExitCoordinator exitCoordinator;

  @override
  State<PlayerItem> createState() => _PlayerItemState();
}

class _PlayerItemState extends State<PlayerItem>
    with
        WindowListener,
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin {
  Box<Object?> setting = GStorage.setting;
  final PlayerController playerController = Modular.get<PlayerController>();
  final IVideoPageController videoPageController =
      Modular.get<IVideoPageController>();
  final AudioController _audioController = AudioController();
  late PlayerShortcutHandler _shortcutHandler;
  late Map<PlayerShortcutAction, PlayerShortcutCallback> keyboardActions;
  final PlayerOverlayCoordinator _overlayCoordinator =
      PlayerOverlayCoordinator();
  late final PlayerExitCoordinator _exitCoordinator;
  PlayerOverlay _lastOverlay = PlayerOverlay.none;
  bool _acceptingInput = true;

  // 硬件解码
  late bool haEnable;
  late bool autoPlayNext;
  late bool backgroundPlayback;
  late bool brightnessVolumeGesture;

  Timer? hideTimer;
  Timer? playerTimer;
  Timer? mouseScrollerTimer;
  Timer? hideVolumeUITimer;

  double lastVolume = 0;
  // 过渡动画控制器
  AnimationController? animationController;

  double lastPlayerSpeed = 1.0;
  int episodeNum = 0;
  late mobx.ReactionDisposer _playerSizeListener;

  late mobx.ReactionDisposer _fullscreenListener;

  bool get _canUsePlayer =>
      mounted && _acceptingInput && playerController.hasActivePlayer;

  Future<void> _showTrackLanguageConfirmationForTrack(
    EmbeddedTrackInfo track,
  ) async {
    if (!_canUsePlayer) return;
    final pending = playerController.pendingTrackLanguageFor(track);
    if (pending == null) return;
    final revision = playerController.trackLanguageConfirmationRevision;
    final warning = await showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (_) => TrackLanguageConfirmationDialog(
        tracks: [pending],
        onConfirm: (choices) {
          final choice = choices[pending.fingerprint];
          if (choice == null) return Future.value('请选择语言');
          return playerController.confirmTrackLanguage(
            revision,
            pending.fingerprint,
            choice,
          );
        },
      ),
    );
    if (!mounted || !_canUsePlayer) return;
    if (warning != null && warning.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(warning)),
      );
    }
  }

  void _stopInteractiveWorkForExit() {
    if (!_acceptingInput) return;
    _acceptingInput = false;
    playerTimer?.cancel();
    playerTimer = null;
    hideTimer?.cancel();
    hideTimer = null;
    mouseScrollerTimer?.cancel();
    mouseScrollerTimer = null;
    hideVolumeUITimer?.cancel();
    hideVolumeUITimer = null;
    AppLogger().i('PlayerItem: timers and input stopped for route exit');
  }

  /// 处理应用进入后台。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused &&
        !backgroundPlayback &&
        _canUsePlayer &&
        playerController.playerPlaying) {
      try {
        await playerController.pause(enableSync: false);
      } catch (_) {}
      return;
    }
  }

  Future<void> _syncPIPAspectWhenVideoSizeReady() async {
    if (playerController.playerWidth <= 0 ||
        playerController.playerHeight <= 0) {
      return;
    }
    if (videoPageController.isPip) {
      await PipUtils.enterDesktopPIPWindow(
        width: playerController.playerWidth,
        height: playerController.playerHeight,
      );
    }
  }

  void _loadShortcuts() {
    final shortcuts = <String, Object?>{};
    defaultShortcuts.forEach((key, defaultValue) {
      shortcuts[key] = setting.get('shortcut_$key', defaultValue: defaultValue);
    });
    _shortcutHandler = PlayerShortcutHandler.fromConfig(
      shortcuts: shortcuts,
      actions: keyboardActions,
      onError: (error, stackTrace) {
        AppLogger().e(
          'PlayerItem: shortcut action failed',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  void _initKeyboardActions() {
    //快捷键功能对应表
    keyboardActions = {
      PlayerShortcutAction.playOrPause: () => playerController.playOrPause(),
      PlayerShortcutAction.forward: () async => handleShortcutForwardDown(),
      PlayerShortcutAction.rewind: () async => handleShortcutRewind(),
      PlayerShortcutAction.next: () async => handlePreNextEpisode('next'),
      PlayerShortcutAction.prev: () async => handlePreNextEpisode('prev'),
      PlayerShortcutAction.volumeUp: () async =>
          handleShortcutVolumeChange('up'),
      PlayerShortcutAction.volumeDown: () async =>
          handleShortcutVolumeChange('down'),
      PlayerShortcutAction.toggleMute: () async =>
          handleShortcutVolumeChange('mute'),
      PlayerShortcutAction.fullscreen: () => handleShortcutFullscreen(),
      PlayerShortcutAction.screenshot: () async => handleScreenshot(),
      PlayerShortcutAction.skip: () async => skipOP(),
      PlayerShortcutAction.exitFullscreen: () => handleShortcutExitFullscreen(),
      PlayerShortcutAction.speed1: () async => setPlaybackSpeed(1.0),
      PlayerShortcutAction.speed2: () async => setPlaybackSpeed(2.0),
      PlayerShortcutAction.speed3: () async => setPlaybackSpeed(3.0),
      PlayerShortcutAction.speedUp: () async => handleSpeedChange('up'),
      PlayerShortcutAction.speedDown: () async => handleSpeedChange('down'),
      // 开始对应长按功能
      // 如需对应长按功能，例如对功能'func'对应长按，请分别添加'funcRepeat'和'funcUp'。
      PlayerShortcutAction.forwardRepeat: () async =>
          handleShortcutForwardRepeat(),
      PlayerShortcutAction.forwardUp: () async => handleShortcutForwardUp(),
    };
  }

  //上一集下一集动作
  Future<void> handlePreNextEpisode(String direction) async {
    if (videoPageController.loading) return;
    final currentRoad = videoPageController.currentRoad;
    final episodes = videoPageController.roadList[currentRoad].data;
    int targetEpisode;
    if (direction == 'next') {
      targetEpisode = videoPageController.currentEpisode + 1;
    } else if (direction == 'prev') {
      targetEpisode = videoPageController.currentEpisode - 1;
    } else {
      return;
    }

    if (targetEpisode > episodes.length) {
      AppDialog.showToast(message: '已经是最新一集');
      return;
    }
    if (targetEpisode <= 0) {
      AppDialog.showToast(message: '已经是第一集');
      return;
    }

    final identifier =
        videoPageController.roadList[currentRoad].identifier[targetEpisode - 1];
    AppDialog.showToast(message: '正在加载$identifier');
    widget.changeEpisode(targetEpisode, currentRoad: currentRoad);
  }

  //快退快捷键动作
  Future<void> handleShortcutRewind() async {
    if (!_canUsePlayer) return;
    int skipTime = playerController.arrowKeySkipTime;
    int current = playerController.currentPosition.inSeconds;
    int targetPosition;

    targetPosition = current - skipTime;
    if (targetPosition < 0) targetPosition = 0;

    try {
      playerTimer?.cancel();
      await playerController.seek(Duration(seconds: targetPosition));
      if (!_canUsePlayer) return;
      playerTimer = getPlayerTimer();
    } catch (e) {
      AppLogger().e('PlayerController: seek failed', error: e);
    }
  }

  // 快进快捷键动作
  Future<void> handleShortcutForwardDown() async {
    lastPlayerSpeed = playerController.playerSpeed;
  }

  Future<void> handleShortcutForwardRepeat() async {
    final double defaultShortcutForwardPlaySpeed = setting.getTyped<double>(
      SettingBoxKey.defaultShortcutForwardPlaySpeed,
      defaultValue: 2.0,
    );
    if (playerController.playerSpeed < defaultShortcutForwardPlaySpeed) {
      playerController.showPlaySpeed = true;
      setPlaybackSpeed(defaultShortcutForwardPlaySpeed);
    }
  }

  Future<void> handleShortcutForwardUp() async {
    if (!_canUsePlayer) return;
    int skipTime = playerController.arrowKeySkipTime;
    int current = playerController.currentPosition.inSeconds;
    int total = playerController.duration.inSeconds;
    int targetPosition;

    targetPosition = current + skipTime;
    if (targetPosition > total) targetPosition = total;
    if (playerController.showPlaySpeed) {
      playerController.showPlaySpeed = false;
      setPlaybackSpeed(lastPlayerSpeed);
    } else {
      try {
        playerTimer?.cancel();
        await playerController.seek(Duration(seconds: targetPosition));
        if (!_canUsePlayer) return;
        playerTimer = getPlayerTimer();
      } catch (e) {
        AppLogger().e('PlayerController: seek failed', error: e);
      }
    }
  }

  //全屏快捷键动作
  void handleShortcutFullscreen() {
    if (!_acceptingInput) return;
    if (!videoPageController.isPip) handleFullscreen();
  }

  //退出全屏快捷键动作
  void handleShortcutExitFullscreen() {
    if (!_acceptingInput) return;
    if (videoPageController.isFullscreen && !Utils.isTablet()) {
      Utils.exitFullScreen();
      videoPageController.isFullscreen = !videoPageController.isFullscreen;
    } else {
      playerController.pause();
      windowManager.hide();
    }
  }

  void _handleTap() {
    if (!_canUsePlayer) return;
    if (_overlayCoordinator.visible == PlayerOverlay.subtitleSettings) {
      closeSubtitleSettingsOverlay();
      return;
    }
    if (Utils.isDesktop()) {
      playerController.playOrPause();
    } else {
      if (playerController.showVideoController) {
        hideVideoController();
      } else {
        displayVideoController();
      }
    }
  }

  void _handleDoubleTap() {
    if (!_canUsePlayer) return;
    if (Utils.isDesktop() && !videoPageController.isPip) {
      handleFullscreen();
    } else {
      playerController.playOrPause();
    }
  }

  void _handleHove() {
    if (!_acceptingInput) return;
    if (!playerController.showVideoController) {
      displayVideoController();
    }
    hideTimer?.cancel();
    startHideTimer();
  }

  void _handleMouseScroller() {
    if (!_canUsePlayer) return;
    playerController.showVolume = true;
    mouseScrollerTimer?.cancel();
    mouseScrollerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _acceptingInput) {
        playerController.showVolume = false;
      }
      mouseScrollerTimer = null;
    });
  }

  //跳过指定秒数
  Future<void> skipOP() async {
    if (!_canUsePlayer) return;
    await playerController.seek(playerController.currentPosition +
        Duration(seconds: playerController.buttonSkipTime));
  }

  Future<void> _bindAudioService() async {
    try {
      await _audioController.bindCallbacks(
        onPlay: () => playerController.play(),
        onPause: () => playerController.pause(),
        onSkipToNext: () => handlePreNextEpisode('next'),
        onSkipToPrevious: () => handlePreNextEpisode('prev'),
        onSeek: (position) => playerController.seek(position),
      );
      if (!_acceptingInput || !mounted) return;
      _syncAudioServiceState();
    } catch (e) {
      AppLogger().w('AudioController: failed to bind callbacks', error: e);
    }
  }

  void _syncAudioServiceState() {
    if (!_acceptingInput) return;
    try {
      final currentRoad = videoPageController.currentRoad;
      final currentEpisode = videoPageController.currentEpisode;
      if (videoPageController.roadList.isEmpty ||
          currentRoad < 0 ||
          currentRoad >= videoPageController.roadList.length) {
        return;
      }
      final currentRoadData = videoPageController.roadList[currentRoad];
      if (currentEpisode <= 0 || currentRoadData.identifier.isEmpty) return;
      final safeEpisodeIndex = currentEpisode - 1;
      if (safeEpisodeIndex >= currentRoadData.identifier.length) return;

      if (playerController.duration <= Duration.zero) return;

      final canSkipToPrevious = currentEpisode > 1;
      final canSkipToNext = currentEpisode < currentRoadData.data.length;
      final bangumiTitle = videoPageController.bangumiItem.nameCn.isNotEmpty
          ? videoPageController.bangumiItem.nameCn
          : videoPageController.bangumiItem.name;
      final episodeTitle = currentRoadData.identifier[safeEpisodeIndex];
      final artworkUrl = videoPageController.bangumiItem.images['large'];
      final artworkUri = (artworkUrl == null || artworkUrl.isEmpty)
          ? null
          : Uri.tryParse(artworkUrl);

      unawaited(
        _audioController.updateSession(
          mediaId:
              '${videoPageController.bangumiItem.id}_${currentRoad}_$currentEpisode',
          title: bangumiTitle,
          album: '本地文件',
          artist: episodeTitle,
          artUri: artworkUri,
          duration: playerController.duration,
          playing: playerController.playing,
          loading: playerController.loading,
          buffering: playerController.isBuffering,
          completed: playerController.completed,
          updatePosition: playerController.currentPosition,
          bufferedPosition: playerController.buffer,
          speed: playerController.playerSpeed,
          queueIndex: safeEpisodeIndex,
          canSkipToNext: canSkipToNext,
          canSkipToPrevious: canSkipToPrevious,
        ),
      );
    } catch (e) {
      AppLogger().w('AudioController: failed to sync playback state', error: e);
    }
  }

  void _handleFullscreenChange(BuildContext context) async {
    playerController.lockPanel = false;
  }

  void _handleGestureDragStart() {
    playerTimer?.cancel();
    playerController.pause(enableSync: false);
    _syncAudioServiceState();
    hideTimer?.cancel();
    playerController.showVideoController = true;
  }

  void handleProgressBarDragStart(ThumbDragDetails details) {
    playerTimer?.cancel();
    playerController.pause(enableSync: false);
    _syncAudioServiceState();
    hideTimer?.cancel();
    playerController.showVideoController = true;
  }

  void handleProgressBarDragEnd() {
    playerController.play(enableSync: false);
    _syncAudioServiceState();
    startHideTimer();
    playerTimer?.cancel();
    playerTimer = getPlayerTimer();
  }

  //截图
  Future<void> handleScreenshot() async {
    if (!_canUsePlayer) return;
    AppDialog.showToast(message: '截图中...');
    try {
      Uint8List? screenshot =
          await playerController.screenshot(format: 'image/png');
      if (!_canUsePlayer) return;

      if (screenshot == null) {
        AppDialog.showToast(message: '截图失败：未获取到图像');
        return;
      }

      final target = await FilePicker.saveFile(
        dialogTitle: '保存截图',
        fileName: '看影音-${DateTime.now().millisecondsSinceEpoch}.png',
        type: FileType.custom,
        allowedExtensions: const <String>['png'],
      );
      if (target == null || !_acceptingInput || !mounted) return;
      await File(target).writeAsBytes(screenshot, flush: true);
      if (!_acceptingInput || !mounted) return;
      AppDialog.showToast(message: '截图已保存');
    } catch (e) {
      AppDialog.showToast(message: '截图失败：$e');
    }
  }

  // 启用超分辨率（质量档）时弹出提示
  Future<void> handleSuperResolutionChange(int shaderIndex) async {
    if (!_canUsePlayer) return;

    final bool isHighMode = shaderIndex == 3;
    final bool alreadyShown = setting.getTyped<bool>(
      SettingBoxKey.superResolutionWarn,
      defaultValue: false,
    );

    if (isHighMode && !alreadyShown) {
      bool confirmed = false;

      await AppDialog.show<void>(builder: (context) {
        bool dontAskAgain = false;

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('性能提示'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('启用超分辨率（质量档）可能会造成设备卡顿，是否继续？'),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: dontAskAgain,
                      onChanged: (value) =>
                          setState(() => dontAskAgain = value ?? false),
                    ),
                    const Text('下次不再询问'),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (dontAskAgain) {
                    await setting.put(SettingBoxKey.superResolutionWarn, true);
                  }
                  AppDialog.dismiss<void>();
                },
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  confirmed = true;
                  if (dontAskAgain) {
                    await setting.put(SettingBoxKey.superResolutionWarn, true);
                  }
                  AppDialog.dismiss<void>();
                },
                child: const Text('确认'),
              ),
            ],
          );
        });
      });

      if (!_canUsePlayer) return;

      if (confirmed) {
        playerController.setShader(shaderIndex);
      }
    } else {
      playerController.setShader(shaderIndex);
    }
  }

  void handleFullscreen() {
    if (!_acceptingInput) return;
    _handleFullscreenChange(context);
    if (videoPageController.isFullscreen) {
      Utils.exitFullScreen();
      if (!Utils.isDesktop()) {
        widget.locateEpisode();
        videoPageController.showTabBody = true;
      }
    } else {
      Utils.enterFullScreen();
      videoPageController.showTabBody = false;
    }
    videoPageController.isFullscreen = !videoPageController.isFullscreen;
  }

  void displayVideoController() {
    if (!_acceptingInput) return;
    animationController?.forward();
    hideTimer?.cancel();
    startHideTimer();
    playerController.showVideoController = true;
  }

  void hideVideoController() {
    if (!_acceptingInput) return;
    animationController?.reverse();
    hideTimer?.cancel();
    playerController.showVideoController = false;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!_canUsePlayer) return;
    await playerController.setPlaybackSpeed(speed);
  }

  Future<void> handleSpeedChange(String type) async {
    if (!_canUsePlayer) return;
    try {
      final currentSpeed = playerController.playerSpeed;
      int index = defaultPlaySpeedList.indexOf(currentSpeed);
      if (type == "up") {
        if (index < defaultPlaySpeedList.length - 1) {
          index++;
          setPlaybackSpeed(defaultPlaySpeedList[index]);
        } else {
          AppDialog.showToast(message: '已达倍速上限');
        }
      } else if (type == "down") {
        if (index > 0) {
          index--;
          setPlaybackSpeed(defaultPlaySpeedList[index]);
        } else {
          AppDialog.showToast(message: '已达倍速下限');
        }
      }
    } catch (e) {
      AppLogger().e('PlayerController: speed change failed', error: e);
    }
  }

  Future<void> handleShortcutVolumeChange(String type) async {
    if (!_canUsePlayer) return;
    try {
      switch (type) {
        case 'up':
          await playerController.setVolume(playerController.volume + 10);
          break;
        case 'down':
          await playerController.setVolume(playerController.volume - 10);
          break;
        case 'mute':
          if (playerController.volume > 0) {
            lastVolume = playerController.volume;
            await playerController.setVolume(0);
          } else {
            await playerController.setVolume(lastVolume);
          }
          break;
        default:
          return;
      }
      if (!_canUsePlayer) return;
      playerController.showVolume = true;
      hideVolumeUITimer?.cancel();
      hideVolumeUITimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _acceptingInput) {
          playerController.showVolume = false;
        }
        hideVolumeUITimer = null;
      });
    } catch (e) {
      AppLogger().e('PlayerController: volume change failed', error: e);
    }
  }

  void startHideTimer() {
    if (!_acceptingInput) return;
    hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && playerController.canHidePlayerPanel) {
        playerController.showVideoController = false;
        animationController?.reverse();
      }
      hideTimer = null;
    });
  }

  // Used to pass hideTimer operation to panel layer
  void cancelHideTimer() {
    hideTimer?.cancel();
  }

  Timer getPlayerTimer() {
    return Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_acceptingInput || !mounted) {
        timer.cancel();
        if (identical(playerTimer, timer)) playerTimer = null;
        return;
      }
      final snapshot = playerController.readRuntimeSnapshot();
      if (snapshot == null) {
        timer.cancel();
        if (identical(playerTimer, timer)) playerTimer = null;
        return;
      }
      playerController.playing = snapshot.playing;
      playerController.isBuffering = snapshot.buffering;
      playerController.currentPosition = snapshot.position;
      playerController.buffer = snapshot.buffer;
      playerController.duration = snapshot.duration;
      playerController.completed = snapshot.completed;
      _syncAudioServiceState();
      // 音量相关
      if (!playerController.volumeSeeking) {
        playerController.volume = snapshot.volume;
      }
      // 自动播放下一集
      if (playerController.completed &&
          videoPageController.currentEpisode <
              videoPageController
                  .roadList[videoPageController.currentRoad].data.length &&
          !videoPageController.loading &&
          autoPlayNext) {
        AppDialog.showToast(
            message:
                '正在加载${videoPageController.roadList[videoPageController.currentRoad].identifier[videoPageController.currentEpisode]}');
        try {
          playerTimer!.cancel();
        } catch (_) {}
        widget.changeEpisode(videoPageController.currentEpisode + 1,
            currentRoad: videoPageController.currentRoad);
      }
    });
  }

  Widget get videoInfoBody {
    return Observer(builder: (context) {
      final safeSource = playerController.playerDebugSource;
      final safePlaylist = playerController.playerDebugPlaylist;
      return ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.closed_caption_outlined),
            title: Text(playerController.isLocalPlayback ? '字幕设置' : '选择字幕'),
            subtitle: Text(
              playerController.currentSubtitlePath.isEmpty
                  ? (playerController.isLocalPlayback
                      ? '未加载字幕'
                      : '支持 ass / ssa / srt / vtt')
                  : p.basename(playerController.currentSubtitlePath),
            ),
            onTap: playerController.isLocalPlayback
                ? () {
                    Navigator.of(context).maybePop();
                    openSubtitleSettingsOverlay();
                  }
                : () {
                    Navigator.of(context).maybePop();
                    openSubtitleSettingsOverlay();
                  },
          ),
          ListTile(
            title: const Text("Source"),
            subtitle: Text(safeSource),
            onTap: () {
              AppDialog.showToast(message: '已复制到剪贴板');
              Clipboard.setData(
                ClipboardData(text: safeSource),
              );
            },
          ),
          ListTile(
            title: const Text("Resolution"),
            subtitle: Text(
                '${playerController.playerWidth}x${playerController.playerHeight}'),
            onTap: () {
              AppDialog.showToast(message: '已复制到剪贴板');
              Clipboard.setData(
                ClipboardData(
                  text:
                      "Resolution\n${playerController.playerWidth}x${playerController.playerHeight}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("VideoParams"),
            subtitle: Text(playerController.playerVideoParams.toString()),
            onTap: () {
              AppDialog.showToast(message: '已复制到剪贴板');
              Clipboard.setData(
                ClipboardData(
                  text:
                      "VideoParams\n${playerController.playerVideoParams.toString()}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("AudioParams"),
            subtitle: Text(playerController.playerAudioParams.toString()),
            onTap: () {
              AppDialog.showToast(message: '已复制到剪贴板');
              Clipboard.setData(
                ClipboardData(
                  text:
                      "AudioParams\n${playerController.playerAudioParams.toString()}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("Media"),
            subtitle: Text(safePlaylist),
            onTap: () {
              AppDialog.showToast(message: '已复制到剪贴板');
              Clipboard.setData(
                ClipboardData(
                  text: "Media\n$safePlaylist",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("AudioTrack"),
            subtitle: Text(playerController.playerAudioTracks.toString()),
            onTap: () {
              AppDialog.showToast(message: '已复制到剪贴板');
              Clipboard.setData(
                ClipboardData(
                  text:
                      "AudioTrack\n${playerController.playerAudioTracks.toString()}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("VideoTrack"),
            subtitle: Text(playerController.playerVideoTracks.toString()),
            onTap: () {
              AppDialog.showToast(message: '已复制到剪贴板');
              Clipboard.setData(
                ClipboardData(
                  text:
                      "VideoTrack\n${playerController.playerVideoTracks.toString()}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("AudioBitrate"),
            subtitle: Text(playerController.playerAudioBitrate.toString()),
            onTap: () {
              AppDialog.showToast(message: '已复制到剪贴板');
              Clipboard.setData(
                ClipboardData(
                  text:
                      "AudioBitrate\n${playerController.playerAudioBitrate.toString()}",
                ),
              );
            },
          ),
        ],
      );
    });
  }

  Future<String?> _pickSubtitlePath({String title = '选择字幕文件'}) async {
    if (!_acceptingInput) return null;
    final result = await FilePicker.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: const ['ass', 'ssa', 'srt', 'vtt'],
      allowMultiple: false,
    );
    if (!_acceptingInput || !mounted) return null;
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return null;
    return path;
  }

  Future<void> _pickAndLoadSubtitle() async {
    final path = await _pickSubtitlePath();
    if (path == null || !_canUsePlayer) return;
    final loaded = await playerController.selectSubtitle(path);
    if (!_acceptingInput || !mounted) return;
    AppDialog.showToast(message: loaded ? '字幕已加载' : '字幕加载失败');
  }

  Future<void> _importSubtitle(LocalSubtitleImportTarget target) async {
    final path = await _pickSubtitlePath(title: '导入字幕文件');
    if (path == null || !_canUsePlayer) return;
    try {
      final result = await playerController.importSubtitle(
        path,
        target: target,
      );
      if (!_acceptingInput || !mounted) return;
      if (result == null) {
        AppDialog.showToast(message: '当前不是本地播放');
        return;
      }
      AppDialog.showToast(
        message: result.renamed ? '字幕已导入并自动重命名' : '字幕已导入',
      );
    } on LocalSubtitleImportException catch (e) {
      AppDialog.showToast(message: e.message);
    } catch (_) {
      AppDialog.showToast(message: '字幕导入失败');
    }
  }

  void _handleOverlayChanged() {
    if (!_acceptingInput) return;
    final current = _overlayCoordinator.visible;
    if (_lastOverlay == PlayerOverlay.subtitleSettings &&
        current != PlayerOverlay.subtitleSettings) {
      playerController.canHidePlayerPanel = true;
      startHideTimer();
    }
    _lastOverlay = current;
    if (mounted) setState(() {});
  }

  void openSubtitleSettingsOverlay() {
    if (!_acceptingInput) return;
    if (playerController.isLocalPlayback) {
      playerController.refreshSubtitleCandidates();
    }
    if (!mounted) return;
    cancelHideTimer();
    playerController.canHidePlayerPanel = false;
    playerController.showVideoController = true;
    animationController?.forward();
    _overlayCoordinator.openSubtitleSettings();
  }

  void closeSubtitleSettingsOverlay() {
    if (_overlayCoordinator.visible != PlayerOverlay.subtitleSettings) return;
    _overlayCoordinator.closeSubtitleSettings();
  }

  void toggleSubtitleSettingsOverlay() {
    if (_overlayCoordinator.visible == PlayerOverlay.subtitleSettings) {
      closeSubtitleSettingsOverlay();
    } else {
      openSubtitleSettingsOverlay();
    }
  }

  void showSubtitleSettings() {
    toggleSubtitleSettingsOverlay();
  }

  Widget get videoDebugLogBody {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0),
        child: Observer(builder: (context) {
          return ListView.builder(
            itemCount: playerController.playerLog.length,
            itemBuilder: (context, index) {
              return Text(
                playerController.sanitizePlayerDiagnostic(
                  playerController.playerLog[index],
                ),
              );
            },
          );
        }),
      ),
      floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.copy),
          onPressed: () {
            final safeLog = playerController.playerLog
                .map(
                  playerController.sanitizePlayerDiagnostic,
                )
                .join('\n');
            Clipboard.setData(
              ClipboardData(text: safeLog),
            );
          }),
    );
  }

  void showVideoInfo() {
    _overlayCoordinator.openVideoInfo();
  }

  Widget _buildVideoInfo(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            const PreferredSize(
              preferredSize: Size.fromHeight(kToolbarHeight),
              child: Material(
                child: TabBar(
                  tabs: [
                    Tab(text: '状态'),
                    Tab(text: '日志'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  videoInfoBody,
                  videoDebugLogBody,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Used to decide which panel is used.
  /// It's too complicated to write these in conditional sentence.
  /// * true: use [PlayerItemPanel]
  /// * false: use [SmallestPlayerItemPanel]
  bool needFullPanel(BuildContext context) {
    // windows too small, workaround for ohos floating window
    if (MediaQuery.sizeOf(context).width < LayoutBreakpoint.compact['width']!) {
      return false;
    }
    // in desktop pip mode
    if (videoPageController.isPip) {
      return false;
    }
    // does not meet Google's phone landscape height and tablet landscape width requirements.
    if (!Utils.isDesktop() &&
        (MediaQuery.sizeOf(context).height >
                LayoutBreakpoint.compact['height']! &&
            MediaQuery.sizeOf(context).width <
                LayoutBreakpoint.medium['width']!)) {
      return false;
    }
    if (Utils.isDesktop() &&
        (MediaQuery.sizeOf(context).height >
                LayoutBreakpoint.compact['height']! &&
            MediaQuery.sizeOf(context).width <
                LayoutBreakpoint.compact['width']!)) {
      return false;
    }
    return true;
  }

  @override
  void onWindowRestore() {}

  @override
  void initState() {
    super.initState();
    _exitCoordinator = widget.exitCoordinator;
    _exitCoordinator.addListener(_stopInteractiveWorkForExit);
    _initKeyboardActions();
    _loadShortcuts();
    _overlayCoordinator.addListener(_handleOverlayChanged);
    _fullscreenListener = mobx.reaction<bool>(
      (_) => videoPageController.isFullscreen,
      (_) {
        _handleFullscreenChange(context);
      },
    );
    _playerSizeListener = mobx.reaction<String>(
      (_) => '${playerController.playerWidth}:${playerController.playerHeight}',
      (_) {
        unawaited(_syncPIPAspectWhenVideoSizeReady());
      },
    );
    WidgetsBinding.instance.addObserver(this);
    animationController ??= AnimationController(
      duration: StyleString.animationDuration,
      vsync: this,
    );
    haEnable =
        setting.getTyped<bool>(SettingBoxKey.hAenable, defaultValue: true);
    autoPlayNext = setting.getTyped<bool>(
      SettingBoxKey.autoPlayNext,
      defaultValue: true,
    );
    backgroundPlayback = setting.getTyped<bool>(
      SettingBoxKey.backgroundPlayback,
      defaultValue: false,
    );
    brightnessVolumeGesture = setting.getTyped<bool>(
      SettingBoxKey.brightnessVolumeGesture,
      defaultValue: true,
    );
    unawaited(_bindAudioService());
    playerTimer = getPlayerTimer();
    windowManager.addListener(this);
    displayVideoController();
  }

  @override
  void dispose() {
    // Don't dispose player here
    // We need to reuse the player after episode is changed and player item is disposed
    // We dispose player after video page disposed
    _exitCoordinator.removeListener(_stopInteractiveWorkForExit);
    _stopInteractiveWorkForExit();
    _fullscreenListener();
    _playerSizeListener();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    playerTimer?.cancel();
    hideTimer?.cancel();
    mouseScrollerTimer?.cancel();
    hideVolumeUITimer?.cancel();
    animationController?.dispose();
    animationController = null;
    _overlayCoordinator
      ..removeListener(_handleOverlayChanged)
      ..dispose();
    // Reset player panel state
    playerController.lockPanel = false;
    playerController.showVideoController = true;
    playerController.showSeekTime = false;
    playerController.showBrightness = false;
    playerController.showVolume = false;
    playerController.showPlaySpeed = false;
    playerController.brightnessSeeking = false;
    playerController.volumeSeeking = false;
    playerController.canHidePlayerPanel = true;
    unawaited(_audioController.deactivate());
    _audioController.clearCallbacks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        return ClipRect(
          child: Container(
            color: Colors.black,
            child: MouseRegion(
              cursor: (videoPageController.isFullscreen &&
                      !playerController.showVideoController)
                  ? SystemMouseCursors.none
                  : SystemMouseCursors.basic,
              onHover: (PointerEvent pointerEvent) {
                if (!_acceptingInput) return;
                // workaround for android.
                // I don't know why, but android tap event will trigger onHover event.
                if (Utils.isDesktop()) {
                  if (pointerEvent.position.dy > 50 &&
                      pointerEvent.position.dy <
                          MediaQuery.of(context).size.height - 70) {
                    _handleHove();
                  } else {
                    if (!playerController.showVideoController) {
                      animationController?.forward();
                      playerController.showVideoController = true;
                    }
                  }
                }
              },
              child: Listener(
                onPointerSignal: (pointerSignal) {
                  if (!_canUsePlayer) return;
                  if (pointerSignal is PointerScrollEvent) {
                    if (_overlayCoordinator.blocksPlayerMouseWheelVolume) {
                      return;
                    }
                    _handleMouseScroller();
                    final scrollDelta = pointerSignal.scrollDelta;
                    final double volume =
                        playerController.volume - scrollDelta.dy / 60;
                    playerController.setVolume(volume);
                  }
                },
                child: SizedBox(
                  height: videoPageController.isFullscreen ||
                          videoPageController.isPip
                      ? (MediaQuery.of(context).size.height)
                      : (MediaQuery.of(context).size.width * 9.0 / (16.0)),
                  width: MediaQuery.of(context).size.width,
                  child: Stack(alignment: Alignment.center, children: [
                    PlayerOverlayPresenter(
                      coordinator: _overlayCoordinator,
                      videoInfoBuilder: _buildVideoInfo,
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 3 / 4,
                        maxWidth: (Utils.isDesktop() || Utils.isTablet())
                            ? MediaQuery.of(context).size.width * 9 / 16
                            : MediaQuery.of(context).size.width,
                      ),
                      child: const SizedBox.shrink(),
                    ),
                    Center(
                        child: Focus(
                            // workaround for #461
                            // I don't know why, but the focus node will break popscope.
                            focusNode: widget.keyboardFocus,
                            autofocus: true,
                            onKeyEvent: (focusNode, KeyEvent event) {
                              if (!_acceptingInput) {
                                return KeyEventResult.ignored;
                              }
                              bool handled = false;
                              final keyLabel =
                                  event.logicalKey.keyLabel.isNotEmpty
                                      ? event.logicalKey.keyLabel
                                      : event.logicalKey.debugName ?? '';
                              if (event is KeyDownEvent) {
                                handled = _shortcutHandler.handleKey(
                                  keyLabel,
                                  PlayerShortcutPhase.down,
                                );
                              } else if (event is KeyRepeatEvent) {
                                handled = _shortcutHandler.handleKey(
                                  keyLabel,
                                  PlayerShortcutPhase.repeat,
                                );
                              } else if (event is KeyUpEvent) {
                                handled = _shortcutHandler.handleKey(
                                  keyLabel,
                                  PlayerShortcutPhase.up,
                                );
                              }
                              return handled
                                  ? KeyEventResult.handled
                                  : KeyEventResult.ignored;
                            },
                            child: const PlayerItemSurface())),
                    (playerController.isBuffering ||
                            videoPageController.loading)
                        ? const Positioned.fill(
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : Container(),
                    GestureDetector(
                      onTap: () {
                        _handleTap();
                      },
                      onDoubleTap: (playerController.lockPanel)
                          ? null
                          : () {
                              _handleDoubleTap();
                            },
                      onLongPressStart: (_) {
                        if (!_canUsePlayer || playerController.lockPanel) {
                          return;
                        }
                        setState(() {
                          playerController.showPlaySpeed = true;
                        });
                        lastPlayerSpeed = playerController.playerSpeed;
                        setPlaybackSpeed(2.0);
                      },
                      onLongPressEnd: (_) {
                        if (!_canUsePlayer || playerController.lockPanel) {
                          return;
                        }
                        setState(() {
                          playerController.showPlaySpeed = false;
                        });
                        setPlaybackSpeed(lastPlayerSpeed);
                      },
                      child: Container(
                        color: Colors.transparent,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                    // 播放器控制面板
                    (needFullPanel(context))
                        ? PlayerItemPanel(
                            onBackPressed: widget.onBackPressed,
                            setPlaybackSpeed: setPlaybackSpeed,
                            changeEpisode: widget.changeEpisode,
                            openMenu: widget.openMenu,
                            handleFullscreen: handleFullscreen,
                            handleProgressBarDragStart:
                                handleProgressBarDragStart,
                            handleProgressBarDragEnd: handleProgressBarDragEnd,
                            handleSuperResolutionChange:
                                handleSuperResolutionChange,
                            handlePreNextEpisode: handlePreNextEpisode,
                            animationController: animationController!,
                            keyboardFocus: widget.keyboardFocus,
                            startHideTimer: startHideTimer,
                            cancelHideTimer: cancelHideTimer,
                            showVideoInfo: showVideoInfo,
                            showSubtitleSettings: showSubtitleSettings,
                            onConfirmTrackLanguage:
                                _showTrackLanguageConfirmationForTrack,
                            pauseForTimedShutdown: widget.pauseForTimedShutdown,
                            disableAnimations: widget.disableAnimations,
                            handleScreenShot: handleScreenshot,
                            skipOP: skipOP,
                          )
                        : SmallestPlayerItemPanel(
                            onBackPressed: widget.onBackPressed,
                            setPlaybackSpeed: setPlaybackSpeed,
                            handleFullscreen: handleFullscreen,
                            handleProgressBarDragStart:
                                handleProgressBarDragStart,
                            handleProgressBarDragEnd: handleProgressBarDragEnd,
                            handleSuperResolutionChange:
                                handleSuperResolutionChange,
                            animationController: animationController!,
                            keyboardFocus: widget.keyboardFocus,
                            handleHove: _handleHove,
                            startHideTimer: startHideTimer,
                            cancelHideTimer: cancelHideTimer,
                            showVideoInfo: showVideoInfo,
                            showSubtitleSettings: showSubtitleSettings,
                            onConfirmTrackLanguage:
                                _showTrackLanguageConfirmationForTrack,
                            pauseForTimedShutdown: widget.pauseForTimedShutdown,
                            disableAnimations: widget.disableAnimations,
                            skipOP: skipOP,
                          ),
                    // 播放器手势控制
                    PlayerGestures(
                      playerController: playerController,
                      animationController: animationController!,
                      brightnessVolumeGesture: brightnessVolumeGesture,
                      onDragStart: () {
                        if (_canUsePlayer) _handleGestureDragStart();
                      },
                      onDragEnd: () {
                        if (_canUsePlayer) handleProgressBarDragEnd();
                      },
                      onSeek: (pos) {
                        if (_canUsePlayer) playerController.seek(pos);
                      },
                      onSetBrightness: (_) async {},
                      startHideTimer: startHideTimer,
                    ),
                    if (_overlayCoordinator.visible ==
                        PlayerOverlay.subtitleSettings)
                      SubtitleSettingsOverlay(
                        playerController: playerController,
                        onClose: closeSubtitleSettingsOverlay,
                        onPickSubtitle: _pickAndLoadSubtitle,
                        onImportSubtitle: _importSubtitle,
                      ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
