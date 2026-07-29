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
}
