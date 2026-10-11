import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.kanyingyin.player/intent');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => installAppPlatformCapabilities(AppPlatformCapabilities.windows));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('无变化请求不会吞掉同一轮紧随的反向请求', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final controller = LocalVideoController();
    await Future.wait([
      controller.exitFullScreen(),
      controller.enterFullScreen(),
    ]);
    expect(calls, ['enterFullscreen']);
    expect(controller.isFullscreen, isTrue);
    await Future.wait([
      controller.enterFullScreen(),
      controller.exitFullScreen(),
    ]);
    expect(calls, ['enterFullscreen', 'exitFullscreen']);
    expect(controller.isFullscreen, isFalse);
  });

  test('全屏标志等待原生过渡完成，重复请求合并', () async {
    final native = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      await native.future;
      return null;
    });
    final controller = LocalVideoController();
    final first = Future<void>.sync(controller.enterFullScreen);
    final second = Future<void>.sync(controller.enterFullScreen);
    await Future<void>.delayed(Duration.zero);
    expect(controller.isFullscreen, isFalse);
    expect(calls, ['enterFullscreen']);
    native.complete();
    await Future.wait([first, second]);
    expect(controller.isFullscreen, isTrue);
  });

  test('全屏中途反向请求串行完成并到达最后目标', () async {
    final entering = Completer<void>();
    final leaving = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      await (call.method == 'enterFullscreen'
          ? entering.future
          : leaving.future);
      return null;
    });
    final controller = LocalVideoController();
    final first = Future<void>.sync(controller.enterFullScreen);
    final last = Future<void>.sync(controller.exitFullScreen);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['enterFullscreen']);
    entering.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['enterFullscreen', 'exitFullscreen']);
    leaving.complete();
    await Future.wait([first, last]);
    expect(controller.isFullscreen, isFalse);
  });

  test('原生失败不提交全屏状态且允许重试', () async {
    var fail = true;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (fail) throw PlatformException(code: 'fullscreen_failed');
      return null;
    });
    final controller = LocalVideoController();
    await expectLater(Future<void>.sync(controller.enterFullScreen),
        throwsA(isA<PlatformException>()));
    expect(controller.isFullscreen, isFalse);
    fail = false;
    await Future<void>.sync(controller.enterFullScreen);
    expect(controller.isFullscreen, isTrue);
  });
}
