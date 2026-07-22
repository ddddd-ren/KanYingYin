import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/app_identity.dart';

void main() {
  test('使用独立的看影音应用身份', () {
    expect(AppIdentity.displayName, '看影音');
    expect(AppIdentity.packageName, 'kanyingyin');
    expect(AppIdentity.windowsIdentity, 'com.kanyingyin.player');
    expect(AppIdentity.storageNamespace, 'kanyingyin');
    expect(AppIdentity.supportsRemoteUpdates, isFalse);
  });

  test('项目定位覆盖本地与个人网盘且排除公共在线影视能力', () {
    final instructions = File('AGENTS.md').readAsStringSync();

    expect(instructions, contains('本地与个人网盘视频媒体库'));
    expect(instructions, contains('用户自有媒体入口'));
    expect(
      instructions,
      contains('不包含公共在线影视搜索、插件规则、WebView 视频解析或在线评论'),
    );
  });
}
