import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播放器设置提供日志目录和诊断导出入口', () {
    final source =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();

    expect(source, contains('打开日志目录'));
    expect(source, contains('导出诊断日志'));
    expect(source, contains('最多保留 10 个日志文件'));
    expect(source, isNot(contains("title: Text('调试模式'")));
  });
}
