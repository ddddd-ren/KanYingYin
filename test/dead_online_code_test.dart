import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('本地播放器项目不再包含不可达的在线页面目录', () {
    for (final path in [
      'lib/pages/bangumi',
      'lib/pages/collect',
      'lib/pages/download',
      'lib/pages/info',
      'lib/pages/plugin_editor',
      'lib/pages/popular',
      'lib/pages/search',
      'lib/pages/timeline',
      'lib/pages/webdav_editor',
      'lib/plugins',
      'lib/webview',
    ]) {
      expect(Directory(path).existsSync(), isFalse, reason: path);
    }
  });

  test('本地播放器项目不再包含旧在线控制器和服务', () {
    for (final path in [
      'lib/pages/video/comments_controller.dart',
      'lib/pages/video/comments_controller.g.dart',
      'lib/pages/player/episode_comments_sheet.dart',
      'lib/services/background_download_service.dart',
      'lib/utils/auto_updater.dart',
      'lib/utils/remote.dart',
      'lib/utils/search_parser.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('项目不再包含历史卡片', () {
    expect(
      File('lib/bean/card/bangumi_history_card.dart').existsSync(),
      isFalse,
    );
  });

  test('播放器接口和存储不再保留在线兼容结构', () {
    final interfaceSource = File(
      'lib/pages/video/video_page_controller_interface.dart',
    ).readAsStringSync();
    final storageFileSource = File('lib/utils/storage.dart').readAsStringSync();
    final storageSource = storageFileSource.split('class SettingBoxKey').first;

    for (final text in [
      'Plugin',
      'currentPlugin',
      'isOfflineMode',
      'offlinePluginName',
    ]) {
      expect(interfaceSource, isNot(contains(text)));
    }
    for (final text in [
      'favorites',
      'collectibles',
      'collectChanges',
      'searchHistory',
      'downloads',
      'CollectedBangumi',
      'SearchHistory',
      'DownloadRecord',
    ]) {
      expect(storageSource, isNot(contains(text)));
    }
  });

  test('播放器内核不再包含一起看客户端', () {
    final source =
        File('lib/pages/player/player_controller.dart').readAsStringSync();

    expect(source.toLowerCase(), isNot(contains('syncplay')));
    for (final path in [
      'lib/services/syncplay.dart',
      'lib/services/syncplay_endpoint.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('依赖和资源配置不再包含在线播放组件', () {
    final source = File('pubspec.yaml').readAsStringSync();

    for (final text in [
      'cookie_jar:',
      'xpath_selector:',
      'xpath_selector_html_parser:',
      'webdav_client:',
      'dlna_dart:',
      'flutter_rating_bar:',
      'flutter_svg:',
      'fl_chart:',
      'flutter_foreground_task:',
      'skeletonizer:',
      'flutter_inappwebview_',
      'upgrader:',
      'open_filex:',
      'html:',
      'image_picker:',
      'webview_windows:',
      'desktop_webview_window:',
      'assets/plugins/',
      'assets/statements/',
    ]) {
      expect(source, isNot(contains(text)));
    }
  });

  test('播放器详情不再包含在线源诊断', () {
    for (final path in [
      'lib/pages/player/player_controller.dart',
      'lib/pages/player/player_item.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('OnlineSource')), reason: path);
      expect(source, isNot(contains('onlineSource')), reason: path);
    }
    expect(
      File('lib/services/online_source_speed_probe.dart').existsSync(),
      isFalse,
    );
  });

  test('界面设置和版本配置不再包含旧在线项目选项', () {
    final interfaceSource =
        File('lib/pages/settings/interface_settings.dart').readAsStringSync();
    final endpointSource = File(
      'lib/request/config/api_endpoints.dart',
    ).readAsStringSync();

    expect(interfaceSource, isNot(contains('显示评分')));
    expect(interfaceSource, isNot(contains('showRating')));
    for (final text in [
      'kanyingyin' '.app',
      'Predidit/' 'KanYingYin',
      'bangumi',
      'trace.moe',
      'latestApp',
      'pluginShop',
    ]) {
      expect(endpointSource.toLowerCase(), isNot(contains(text.toLowerCase())));
    }
  });
}
