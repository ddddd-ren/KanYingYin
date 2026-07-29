import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/utils/proxy_manager.dart';

void main() {
  test('Android 不扫描本机代理端口且 Windows 保留自动探测', () {
    expect(
      ProxyPlatformPolicy.canAutoDetectLocalProxy(
        AppPlatformCapabilities.android,
      ),
      isFalse,
    );
    expect(
      ProxyPlatformPolicy.canAutoDetectLocalProxy(
        AppPlatformCapabilities.windows,
      ),
      isTrue,
    );
  });

  test('Android 网盘依赖、HTTP 兼容和 WebView 安全守卫完整', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final webView = File(
      'lib/pages/cloud/xunlei/xunlei_verification_dialog.dart',
    ).readAsStringSync();

    expect(lock, contains('flutter_inappwebview_android:'));
    expect(lock, contains('flutter_secure_storage:'));
    expect(lock, contains('media_kit_libs_android_video:'));
    expect(manifest, contains('android:usesCleartextTraffic="true"'));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(webView, contains('onCreateWindow'));
    expect(webView, contains('onDownloadStarting'));
    expect(webView, contains('PermissionResponseAction.DENY'));
    expect(webView, contains('XunleiVerificationNavigationPolicy'));
  });
}
