import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String controller;
  late String mainActivity;
  late String manifest;
  late String windowUtils;
  late String immersiveModeController;
  late String immersiveModeApplier;
  late String videoPage;

  setUpAll(() {
    controller =
        File('lib/pages/player/player_controller.dart').readAsStringSync();
    mainActivity = File(
      'android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt',
    ).readAsStringSync();
    manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    windowUtils = File('lib/utils/window_utils.dart').readAsStringSync();
    immersiveModeController = File(
      'android/app/src/main/kotlin/com/kanyingyin/player/'
      'ImmersiveModeController.kt',
    ).readAsStringSync();
    immersiveModeApplier = File(
      'android/app/src/main/kotlin/com/kanyingyin/player/'
      'AndroidImmersiveModeApplier.kt',
    ).readAsStringSync();
    videoPage = File('lib/pages/video/video_page.dart').readAsStringSync();
  });

  test('Android 平板启动即固定为双向横屏且退出全屏不切回竖屏', () {
    expect(mainActivity, contains('smallestScreenWidthDp >= 600'));
    expect(
      mainActivity,
      contains('ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE'),
    );
    expect(
      manifest,
      contains(
        'android.window.PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY',
      ),
    );
    expect(windowUtils, contains('view.physicalSize.shortestSide'));
    expect(
      windowUtils,
      contains('DeviceOrientation.landscapeLeft'),
    );
    expect(
      windowUtils,
      contains('DeviceOrientation.landscapeRight'),
    );
  });

  test('Android libass 使用应用内中文字体渲染字幕', () {
    expect(
      controller,
      contains("libassAndroidFont: 'assets/fonts/MiSans-Regular.ttf'"),
    );
    expect(controller, contains("libassAndroidFontName: 'MiSans'"));
  });

  test('Android PGS 字幕使用 GPU 合成并在跳播时预读', () {
    final platform = File('lib/platform/app_platform.dart').readAsStringSync();
    final constants = File('lib/utils/constants.dart').readAsStringSync();
    expect(platform, isNot(contains("'mediacodec_embed'")));
    expect(constants, isNot(contains("'mediacodec_embed'")));
    expect(
      controller,
      contains("'demuxer-mkv-subtitle-preroll', 'yes'"),
    );
    expect(
      controller,
      contains("'demuxer-mkv-subtitle-preroll-secs', '10'"),
    );
  });

  test('没有外挂字幕时保留内嵌字幕自动选择', () {
    expect(
      controller,
      contains('if (subtitlePath != null && subtitlePath.isNotEmpty)'),
    );
    expect(
      controller,
      isNot(
        contains(
          'if (subtitlePath == null || subtitlePath.isEmpty) {\n'
          '      await _disableSubtitleTrack(clearCurrentPath: true);',
        ),
      ),
    );
  });

  test('字幕自动选择不被已完成的音轨自动选择阻断', () {
    expect(
      controller,
      isNot(
        contains(
          'if (!_embeddedTrackSelection.beginAutomaticSelection(\n'
          '      hasAudioTracks: availableAudioTracks.isNotEmpty,\n'
          '    )) {\n'
          '      return;\n'
          '    }',
        ),
      ),
    );
    expect(controller, contains('final shouldSelectAudio ='));
  });

  test('Android TrueHD 在选择音轨前启用立体声解码输出', () {
    expect(controller, contains('Future<void> _prepareAndroidAudioOutput('));
    expect(controller, contains("'audio-channels'"));
    expect(controller, contains("'stereo'"));
    expect(controller, contains("'ad-lavc-downmix'"));
    expect(controller, contains("'yes'"));
    expect(
      controller,
      contains(
        'await _prepareAudioTrackOutput(player, track);\n'
        '      await player.setAudioTrack(track);',
      ),
    );
  });

  test('Android 播放页使用黑色系统栏表面', () {
    expect(videoPage, contains('AndroidPlaybackSystemUiSurface('));
    expect(videoPage, contains('backgroundColor: Colors.black'));
  });

  test('Android 全屏保持彻底沉浸并在退出时恢复系统栏', () {
    expect(immersiveModeController, contains('var isRequested: Boolean'));
    expect(
      immersiveModeApplier,
      contains('BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE'),
    );
    expect(
      immersiveModeApplier,
      contains('window.setDecorFitsSystemWindows(false)'),
    );
    expect(immersiveModeApplier, contains('Color.TRANSPARENT'));
    expect(
      immersiveModeApplier,
      contains('window.isNavigationBarContrastEnforced = false'),
    );
    expect(
      immersiveModeApplier,
      contains('controller.hide(WindowInsets.Type.systemBars())'),
    );
    expect(
      immersiveModeApplier,
      isNot(contains('window.setDecorFitsSystemWindows(true)')),
    );
    expect(
      immersiveModeApplier,
      contains('controller.show(WindowInsets.Type.systemBars())'),
    );
    expect(mainActivity, contains('immersiveModeController.initialize()'));
    expect(mainActivity, contains('override fun onResume()'));
    expect(mainActivity, contains('override fun onWindowFocusChanged'));
    expect(
      mainActivity,
      contains('immersiveModeController.reapplyCurrent()'),
    );
    expect(
      mainActivity,
      contains('immersiveModeController.setEnabled(enabled)'),
    );
    expect(windowUtils, contains('setImmersive(true)'));
    expect(windowUtils, contains('setImmersive(false)'));
  });

  test('Android 手机在关键生命周期重新申请最高同分辨率刷新模式', () {
    expect(
      mainActivity,
      contains('AndroidHighRefreshRateController(this)'),
    );
    expect(
      mainActivity,
      contains('highRefreshRateController.applyPreferredMode()'),
    );
    expect(mainActivity, contains('override fun onResume()'));
    expect(mainActivity, contains('override fun onWindowFocusChanged'));
    expect(mainActivity, contains('override fun onConfigurationChanged'));
  });

  test('Android TrueHD 无兼容音轨时保持视频并提示导出日志', () {
    expect(
      controller,
      contains('当前播放器组件无法解码此音轨，请导出诊断日志'),
    );
    expect(controller, contains('_truehdAudioTrackFallbackAttempted = true'));
    expect(controller, isNot(contains('_retryWithSoftwareDecodingForTrueHd')));
  });

  test('Android 视频硬解打开失败时只重载视频轨并降级软解', () {
    expect(controller, contains('PlayerDecoderFailureKind.video'));
    expect(controller, contains("await platform.setProperty('hwdec', 'no')"));
    expect(
        controller, contains("await platform.command(const ['video-reload'])"));
    expect(controller, isNot(contains('_retryWithSoftwareDecodingForTrueHd')));
  });
}
