import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('关于页面仅显示看影音自身内容', () {
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

  test('许可证页使用看影音应用名', () {
    final source = File('lib/pages/about/about_module.dart').readAsStringSync();

    expect(source, contains("applicationName: '看影音'"));
    final oldName = String.fromCharCodes([23601, 30475]);
    expect(source, isNot(contains("applicationName: '$oldName'")));
  });

  test('README 和关于页面简单注明 Kazumi 来源', () {
    final readme = File('README.md').readAsStringSync();
    final about = File('lib/pages/about/about_page.dart').readAsStringSync();

    expect(
      readme,
      contains(
        '界面与操作参考 [Kazumi](https://github.com/Predidit/Kazumi)',
      ),
    );
    expect(about, contains('界面与操作参考 Kazumi'));
  });

  test('Linux 安装包描述符合本地媒体定位', () {
    for (final workflowPath in [
      '.github/workflows/pr.yaml',
      '.github/workflows/release.yaml',
    ]) {
      final workflow = File(workflowPath).readAsStringSync();
      final description = RegExp(
        r'^\s*Description:\s*(.+)$',
        multiLine: true,
      ).firstMatch(workflow);

      expect(description, isNotNull, reason: workflowPath);
      expect(description!.group(1), 'Local video library and player.');
      expect(description.group(1)!.toLowerCase(), isNot(contains('online')));
    }
  });
}
