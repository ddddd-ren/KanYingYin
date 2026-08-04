import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('设置页提供统一观看历史入口', () {
    final myPage = File('lib/pages/my/my_page.dart').readAsStringSync();
    final playerSettings =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();
    final settingsModule =
        File('lib/pages/settings/settings_module.dart').readAsStringSync();

    expect(myPage, contains('观看历史'));
    expect(playerSettings, isNot(contains('privateMode')));
    expect(playerSettings, isNot(contains('隐身模式')));
    expect(settingsModule, contains('HistoryPage'));
    expect(settingsModule, contains('"/history"'));
  });

  test('历史功能同时覆盖本地与网盘来源', () {
    final entry =
        File('lib/features/history/domain/playback_history_entry.dart')
            .readAsStringSync();
    final controller =
        File('lib/pages/video/video_page.dart').readAsStringSync();

    expect(entry, contains('PlaybackHistorySource.local'));
    expect(entry, contains('PlaybackHistorySource.cloud'));
    expect(controller, contains('buildPlaybackHistoryEntry'));
    expect(controller, contains('resumePosition'));
  });

  test('历史使用设置盒 JSON 存储，不引入 Hive 适配器', () {
    final repository = File(
      'lib/features/history/application/playback_history_repository.dart',
    ).readAsStringSync();
    final settings =
        File('lib/features/settings/application/typed_settings.dart')
            .readAsStringSync();

    expect(repository, contains('SettingBoxKey.playbackHistory'));
    expect(repository, contains('toJson()'));
    expect(settings, contains("playbackHistory = 'playbackHistory'"));
  });

  test('历史页面和绑定已注册', () {
    expect(
      File('lib/features/history/presentation/history_page.dart').existsSync(),
      isTrue,
    );
    final bindings =
        File('lib/app/bindings/history_bindings.dart').readAsStringSync();
    expect(bindings, contains('PlaybackHistoryController'));
  });
}
