import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('关于页面不提供无关在线入口或文案', () {
    final source = File('lib/pages/about/about_page.dart').readAsStringSync();

    for (final text in [
      '自动更新',
      '检查更新',
      'myController.checkUpdate',
      '退出 ${String.fromCharCodes([23601, 30475])}',
      '番剧封面',
    ]) {
      expect(source, isNot(contains(text)));
    }
  });

  test('播放器设置不再提供在线流广告过滤选项', () {
    final source =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();

    for (final text in ['强制启用HLS广告过滤', 'forceAdBlocker']) {
      expect(source, isNot(contains(text)));
    }
  });

  test('设置页不再提供历史记录和隐身模式', () {
    final myPage = File('lib/pages/my/my_page.dart').readAsStringSync();
    final playerSettings =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();

    expect(myPage, isNot(contains('历史记录')));
    expect(playerSettings, isNot(contains('隐身模式')));
    expect(playerSettings, isNot(contains('privateMode')));
  });

  test('启动流程不再初始化在线资源服务', () {
    final source = File('lib/pages/init_page.dart').readAsStringSync();

    for (final text in [
      'PluginsController',
      'DownloadController',
      'CollectController',
      'WebDav',
      'BangumiSyncService',
      'BackgroundDownloadService',
      'queryPluginHTTPList',
      'checkUpdate',
      'assets/statements/statements.txt',
    ]) {
      expect(source, isNot(contains(text)));
    }
  });

  test('根模块不再注册不可达的在线页面和控制器', () {
    final source = File('lib/pages/index_module.dart').readAsStringSync();

    for (final text in [
      'PopularController',
      'TimelineController',
      'ISearchHistoryRepository',
      'SearchHistoryRepository',
      'InfoModule',
      'SearchModule',
      'r.module("/info"',
      'r.module("/search"',
    ]) {
      expect(source, isNot(contains(text)));
    }
  });

  test('活动源码不再使用旧项目命名或在线能力', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.startsWith('lib/legacy/')) continue;
      final source = entity.readAsStringSync();
      for (final token in const <String>[
        'BangumiItem',
        'matchWithBangumi',
        'isMatchingBangumi',
        'bangumiMatchProgress',
        'bangumiHTTPHeader',
        'bgm.tv',
        'clearWebviewLog',
        'Bangumi fallback',
        'pluginName',
        'adBlockerEnabled',
      ]) {
        if (source.contains(token)) offenders.add('$path: $token');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
