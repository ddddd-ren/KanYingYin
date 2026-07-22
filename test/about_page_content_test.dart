import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = _findProjectRoot();

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

  test('README 和关于页面不展示 Kazumi', () {
    final readme = File('README.md').readAsStringSync();
    final about = File('lib/pages/about/about_page.dart').readAsStringSync();

    expect(readme, isNot(contains('Kazumi')));
    expect(about, isNot(contains('Kazumi')));
    expect(about, contains('开源许可与致谢'));
    expect(about, contains('开源许可证'));
  });

  test('清除缓存下方显示统一的当前版本', () {
    final source = File('lib/pages/about/about_page.dart').readAsStringSync();
    final clearCacheIndex = source.indexOf("'清除缓存'");
    final currentVersionIndex = source.indexOf("'当前版本'");

    expect(clearCacheIndex, greaterThanOrEqualTo(0));
    expect(currentVersionIndex, greaterThan(clearCacheIndex));
    expect(
      source,
      contains('package:kanyingyin/core/app_version.dart'),
    );
    expect(source, contains('AppVersion.current'));
    expect(source, isNot(contains("Text('2.1.30')")));
  });

  test('持续集成仅保留 Windows 质量门禁与发布', () {
    for (final workflowPath in [
      '.github/workflows/pr.yaml',
      '.github/workflows/release.yaml',
    ]) {
      final workflow = File(
        '${projectRoot.path}${Platform.pathSeparator}'
        '${workflowPath.replaceAll('/', Platform.pathSeparator)}',
      ).readAsStringSync();

      expect(workflow, contains('runs-on: windows-latest'),
          reason: workflowPath);
      expect(workflow, contains('flutter test --no-pub'), reason: workflowPath);
      expect(workflow, contains('flutter build windows --release --no-pub'),
          reason: workflowPath);
      expect(workflow, isNot(contains('assets/linux/')), reason: workflowPath);
    }
  });
}

Directory _findProjectRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}${Platform.pathSeparator}pubspec.yaml')
        .existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('无法定位项目根目录');
    }
    directory = parent;
  }
}
