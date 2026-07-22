import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('设置主页使用档案馆控制中心且保留全部入口', () {
    final source = File('lib/pages/my/my_page.dart').readAsStringSync();

    expect(source, contains('SettingsHubCard('));
    expect(source, contains('SettingsHubLayout.columnCountFor'));
    expect(source, isNot(contains('card_settings_ui')));
    for (final label in <String>[
      'TMDB 刮削',
      '网盘数据源',
      '媒体识别',
      '播放设置',
      '操作设置',
      '外观设置',
      '界面设置',
      '关于',
    ]) {
      expect(source, contains("title: '$label'"), reason: '缺少 $label 入口');
    }
    for (final path in <String>[
      '/settings/tmdb',
      '/settings/cloud-sources',
      '/settings/media-recognition',
      '/settings/player',
      '/settings/keyboard',
      '/settings/theme',
      '/settings/interface',
      '/settings/about/',
    ]) {
      expect(
        source,
        contains("onOpenPath('$path')"),
      );
    }
    expect(source, contains('Modular.to.pushNamed(path)'));
  });

  test('所有设置路由使用影院氛围转场', () {
    final source =
        File('lib/pages/settings/settings_module.dart').readAsStringSync();

    expect(source, contains('SettingsMotion.pageDuration'));
    expect(source, contains('TransitionType.rightToLeftWithFade'));
    expect(source, contains('void _child('));
    expect(source, contains('_child(r, "/theme"'));
    expect(source, contains('_child(r, "/player"'));
    expect(
      source,
      matches(RegExp(r'_child\(\s*r,\s*"/cloud-sources"')),
    );
  });
}
