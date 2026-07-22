import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('启动页未知值回退本地媒体库且不再显示推荐遗留文案', () {
    final source =
        File('lib/pages/settings/interface_settings.dart').readAsStringSync();

    expect(
      source,
      contains("defaultStartupPageLabels[defaultPage] ?? '本地媒体库'"),
    );
    expect(source, isNot(contains("?? '推荐'")));
    expect(source, contains("title: Text('启动时打开'"));
    expect(source, contains('选择看影音启动后显示的媒体库'));
  });
}
