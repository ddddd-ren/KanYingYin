import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('用户界面不再提供历史记录和隐身模式', () {
    final myPage = File('lib/pages/my/my_page.dart').readAsStringSync();
    final playerSettings =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();
    final settingsModule =
        File('lib/pages/settings/settings_module.dart').readAsStringSync();

    expect(myPage, isNot(contains('历史记录')));
    expect(playerSettings, isNot(contains('privateMode')));
    expect(playerSettings, isNot(contains('隐身模式')));
    expect(settingsModule, isNot(contains('HistoryModule')));
    expect(settingsModule, isNot(contains('"/history"')));
  });

  test('媒体库不再提供断点续播和观看进度', () {
    final librarySheet =
        File('lib/pages/local/library_sheet.dart').readAsStringSync();

    for (final text in [
      'continueEpisodeForSeries',
      'nextEpisodeForSeries',
      'getLocalPlaybackProgress',
      '继续播放',
      '下一集',
      '已看到',
    ]) {
      expect(librarySheet, isNot(contains(text)), reason: text);
    }
  });

  test('运行时不再注册或写入观看历史', () {
    final indexModule = File('lib/pages/index_module.dart').readAsStringSync();
    final playerItem =
        File('lib/pages/player/player_item.dart').readAsStringSync();
    final storage = File('lib/utils/storage.dart').readAsStringSync();

    for (final text in [
      'HistoryController',
      'IHistoryRepository',
      'HistoryRepository',
      'updateHistory(',
      'historySource',
      'HistorySourceType',
    ]) {
      expect('$indexModule\n$playerItem', isNot(contains(text)));
    }
    expect(storage, isNot(contains('Box<History>')));
    expect(storage, isNot(contains('HistoryAdapter')));
    expect(storage, isNot(contains('ProgressAdapter')));
    expect(storage, isNot(contains("privateMode = 'privateMode'")));
  });

  test('历史领域源码已删除', () {
    for (final path in [
      'lib/modules/history/history_module.dart',
      'lib/modules/history/history_module.g.dart',
      'lib/repositories/history_repository.dart',
      'lib/pages/history/history_controller.dart',
      'lib/pages/history/history_controller.g.dart',
      'lib/pages/history/history_module.dart',
      'lib/pages/history/history_page.dart',
      'lib/bean/card/bangumi_history_card.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });
}
