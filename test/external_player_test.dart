import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/external_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.kanyingyin.player/intent.test');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('MIME 外部播放使用平台布尔结果', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final warnings = <String>[];
    final client = ExternalPlayerClient(
      channel: channel,
      warningReporter: warnings.add,
    );

    expect(
      await client.launchURLWithMIME('D:/视频/电影.mkv', 'video/mp4'),
      isTrue,
    );
    expect(calls.single.method, 'openWithMime');
    expect(calls.single.arguments, <String, String>{
      'url': 'D:/视频/电影.mkv',
      'mimeType': 'video/mp4',
    });
    expect(warnings, isEmpty);
  });

  test('平台返回 false 时不误报外部播放成功', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    final client = ExternalPlayerClient(
      channel: channel,
      warningReporter: (_) {},
    );

    expect(
      await client.launchURLWithMIME('D:/video.mkv', 'video/mp4'),
      isFalse,
    );
  });

  test('Referer 不受支持时只报告固定错误分类', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(
        code: 'UnsupportedHeaders',
        message: 'https://example.com/video?token=secret',
        details: 'Referer: https://example.com/private',
      );
    });
    final warnings = <String>[];
    final client = ExternalPlayerClient(
      channel: channel,
      warningReporter: warnings.add,
    );

    expect(
      await client.launchURLWithReferer(
        'https://example.com/video?token=secret',
        'https://example.com/private',
      ),
      isFalse,
    );
    expect(calls.single.method, 'openWithReferer');
    expect(warnings, <String>['UnsupportedHeaders']);
    expect(warnings.join(), isNot(contains('secret')));
    expect(warnings.join(), isNot(contains('example.com')));
  });

  test('未知平台错误归类为外部播放失败', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'Unexpected', message: 'token=secret');
    });
    final warnings = <String>[];
    final client = ExternalPlayerClient(
      channel: channel,
      warningReporter: warnings.add,
    );

    expect(
      await client.launchURLWithMIME('D:/video.mkv', 'video/mp4'),
      isFalse,
    );
    expect(warnings, <String>['LaunchFailed']);
  });
}
