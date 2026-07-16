import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('关于页面不再提供旧在线更新入口或旧项目文案', () {
    final source = File('lib/pages/about/about_page.dart').readAsStringSync();

    for (final text in [
      '自动更新',
      '检查更新',
      'myController.checkUpdate',
      '退出 就看',
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
}
