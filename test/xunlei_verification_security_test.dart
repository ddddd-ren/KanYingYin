import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('迅雷客户端凭据不再以字面量保存在跟踪源码', () {
    final policy = File(
      'lib/services/cloud/xunlei/xunlei_request_policy.dart',
    ).readAsStringSync();
    final configuration = File(
      'lib/services/cloud/xunlei/xunlei_client_configuration.dart',
    ).readAsStringSync();

    for (final field in <String>[
      'clientId',
      'clientSecret',
      'webClientId',
      'appKey',
    ]) {
      expect(
        policy,
        isNot(matches(RegExp("static const String $field = '[^']+';"))),
        reason: field,
      );
    }
    expect(configuration, contains('String.fromEnvironment'));
    expect(configuration, contains('KANYINGYIN_XUNLEI_CLIENT_SECRET'));
  });

  test('迅雷验证不提供网页浏览媒体解析和调试能力', () {
    final sources = <String>[
      'lib/services/cloud/xunlei/xunlei_verification_bridge.dart',
      'lib/services/cloud/xunlei/xunlei_verification_profile.dart',
      'lib/pages/cloud/xunlei/xunlei_verification_dialog.dart',
      'lib/pages/cloud/xunlei/xunlei_source_editor.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    for (final forbidden in <String>[
      'WebView 视频解析',
      'openDevTools(',
      'onConsoleMessage:',
      'Clipboard.',
      'LaunchMode.externalApplication',
      'loadData(',
      'initialData:',
      'file://',
    ]) {
      expect(sources, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(
      sources,
      contains('https://i.xunlei.com/xlcaptcha/android.html'),
    );
    expect(sources, contains("host.toLowerCase() == 'i.xunlei.com'"));
    expect(sources, contains('PermissionResponseAction.DENY'));
    expect(sources, contains('AppIdentity.storageNamespace'));
    expect(sources, contains('DebugLoggingSettings(enabled: false)'));
    expect(sources, contains('onDownloadStarting:'));
    expect(sources, contains('DownloadStartResponseAction.CANCEL'));
    expect(sources, contains('handled: true'));
    expect(sources, isNot(contains('Browser.setDownloadBehavior')));
    expect(sources, isNot(contains('Page.setDownloadBehavior')));
  });

  test('挑战模型未提供序列化持久化入口', () {
    final models = File(
      'lib/services/cloud/xunlei/xunlei_models.dart',
    ).readAsStringSync();
    final start = models.indexOf('class XunleiVerificationChallenge');
    final end = models.indexOf('\nclass ', start + 1);
    final challenge = models.substring(
      start,
      end == -1 ? models.length : end,
    );
    expect(challenge, isNot(contains('toJson')));
    expect(challenge, isNot(contains('fromJson')));
    expect(challenge, contains('<redacted>'));
  });
}
