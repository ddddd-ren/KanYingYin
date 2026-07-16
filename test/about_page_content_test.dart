import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('关于页面不再显示旧项目外部链接', () {
    final source = File('lib/pages/about/about_page.dart').readAsStringSync();
    for (final text in [
      '外部链接',
      '项目主页',
      '代码仓库',
      '图标创作',
      '番剧索引',
      '以图搜番',
    ]) {
      expect(source, isNot(contains(text)));
    }
  });
}
