import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/android/android_platform_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.kanyingyin.player/android.test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('进入画中画传递合法宽高比', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    const client = AndroidPlatformChannel(channel: channel);

    expect(
      await client.enterPictureInPicture(width: 1920, height: 1080),
      isTrue,
    );
    expect(received!.method, 'enterPictureInPicture');
    expect(received!.arguments, {'width': 1920, 'height': 1080});
  });

  test('非法画中画尺寸回退到 16 比 9', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    const client = AndroidPlatformChannel(channel: channel);

    await client.enterPictureInPicture(width: 0, height: -1);

    expect(received!.arguments, {'width': 16, 'height': 9});
  });

  test('亮度、截图和外部播放器使用固定方法与参数', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'saveScreenshot' => 'content://media/image/1',
        'openWithMime' => true,
        _ => null,
      };
    });
    const client = AndroidPlatformChannel(channel: channel);

    await client.setBrightness(5);
    expect(
      await client.saveScreenshot(Uint8List.fromList([1, 2, 3])),
      'content://media/image/1',
    );
    expect(
      await client.openWithMime(
        'content://provider/document/video%3A1',
        'video/mp4',
      ),
      isTrue,
    );

    expect(calls[0], isA<MethodCall>());
    expect(calls[0].method, 'setBrightness');
    expect(calls[0].arguments, 1.0);
    expect(calls[1].method, 'saveScreenshot');
    expect(calls[1].arguments, Uint8List.fromList([1, 2, 3]));
    expect(calls[2].method, 'openWithMime');
    expect(calls[2].arguments, {
      'url': 'content://provider/document/video%3A1',
      'mimeType': 'video/mp4',
    });
  });

  test('后台播放通知授权使用固定平台方法', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    const client = AndroidPlatformChannel(channel: channel);

    expect(await client.requestNotificationPermission(), isTrue);
    expect(received?.method, 'requestNotificationPermission');
    expect(received?.arguments, isNull);
  });

  test('Android 设备能力使用固定平台方法', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return <String, Object?>{
        'sdkInt': 36,
        'leanback': true,
        'television': true,
        'touchscreen': false,
        'webView': true,
        'manufacturer': 'vivo',
        'model': 'V2219A',
        'hardware': 'mt6877',
        'socModel': 'MT6877V/TTZA',
        'currentRefreshRate': 120.0,
        'supportedRefreshRates': <double>[60.0, 90.0, 120.0],
        'preferredDisplayModeId': 3,
      };
    });
    const client = AndroidPlatformChannel(channel: channel);

    final result = await client.getDeviceCapabilities();

    expect(received?.method, 'getDeviceCapabilities');
    expect(result?['sdkInt'], 36);
    expect(result?['leanback'], isTrue);
    expect(result?['socModel'], 'MT6877V/TTZA');
    expect(result?['supportedRefreshRates'], <double>[60.0, 90.0, 120.0]);
  });

  test('Android TV 文件选择由应用原生通道流式复制到缓存', () {
    final source = File(
      'android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt',
    ).readAsStringSync();
    final resolver = File(
      'android/app/src/main/kotlin/com/kanyingyin/player/'
      'AndroidPickedFileResolver.kt',
    ).readAsStringSync();

    expect(source, contains('"pickFile" -> handlePickFile(call, result)'));
    expect(source, contains('Intent(Intent.ACTION_OPEN_DOCUMENT)'));
    expect(source, contains('Intent.CATEGORY_OPENABLE'));
    expect(source, contains('File.createTempFile'));
    expect(source, contains('FLAG_GRANT_READ_URI_PERMISSION'));
    expect(source, contains('OpenableColumns.DISPLAY_NAME'));
    expect(source, contains('resolvePickedFileExtension'));
    expect('$source\n$resolver', contains('normalizedAllowed.single()'));
  });
}
